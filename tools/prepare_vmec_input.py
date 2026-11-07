#!/usr/bin/env python3
"""Prepare a VMEC INDATA file for a solver-specific benchmark run.

The upstream repositories ship inputs with optional diagnostic switches and
legacy ``&END`` terminators that are not accepted uniformly by the VMEC
implementations.  This small, loss-aware adapter removes only those output
controls, keeps the equilibrium data unchanged, and stages a referenced
``MGRID_FILE`` when a matching fixture is available in the benchmark tree.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import struct
import sys
from pathlib import Path


_MGRID = re.compile(
    r"(?im)^(\s*mgrid_file\s*=\s*)(['\"])([^'\"]*)(\2)(.*)$"
)
_OUTPUT_CONTROL = re.compile(
    r"(?i)^\s*(?:dump_[a-z0-9_]+|lspectrum_dump|ldiagno(?:_opt)?|"
    r"loldout|lwouttxt|lfull3d1out)\s*="
)
_END = re.compile(r"(?i)^\s*&end\s*$")
# Spellings of older VMEC versions that current readers reject; the meaning
# of each is that of the current name.
_LEGACY_NAMES = (
    (re.compile(r"(?i)\btype_precon(?=\s*=)"), "PRECON_TYPE"),
    (re.compile(r"(?i)\braxis_co(?=\s*[(=])"), "RAXIS_CC"),
    (re.compile(r"(?i)\bzaxis_co(?=\s*[(=])"), "ZAXIS_CC"),
)
_AC_FORM = re.compile(r"(?i)^\s*ac_form\s*=\s*([^,\s]+)\s*,?\s*$")
_SEPARATOR = re.compile(r"^\s*-{3,}\s*$")
_FORTRAN_COMMENT = re.compile(r"^\s*[cC](?:\s|$)")
_FULL_LINE_COMMENT = re.compile(r"^\s*[!#]")
_DESC_DROP = re.compile(
    r"(?i)^\s*(?:mgrid_file|time_slice|delt|ns_array|niter_array|"
    r"ftol_array|niter|nstep|nvacskip|type_precon|prec2d_threshold|"
    r"extcur|sigma_current)\b"
)
_FIELD = re.compile(r"(?i)^\s*(?:mgrid_file|extcur)\b")
_EXTCUR = re.compile(
    r"(?is)\bextcur\s*(?:\(\s*(\d+)\s*\))?\s*=\s*(.*?)(?=\b[a-z_][a-z0-9_]*\s*(?:\([^)]*\))?\s*=|/|&end|$)"
)
_NUMBER = re.compile(r"[+-]?(?:\d+\.?\d*|\.\d+)(?:[EeDd][+-]?\d+)?")
_ASSIGNMENT = re.compile(r"(?=\s+[A-Za-z_]\w*(?:\([^)]*\))?\s*=)")
_EDUCATIONAL_DROP = re.compile(
    r"(?i)^\s*(?:time_slice|type_precon|precon_type|prec2d_threshold|"
    r"bcrit|pt_type|ph_type|lforbal|sigma_current)\b"
)
_NITER_SINGLE = re.compile(r"(?i)^\s*niter\s*=")
_FTOL_SINGLE = re.compile(r"(?i)^\s*ftol\s*=")


def _strip_inline_comment(line: str) -> str:
    """Remove Fortran ``!``/``#`` comments outside quoted strings."""

    quote = ""
    for index, character in enumerate(line):
        if character in {"'", '"'}:
            if quote == character:
                # Fortran escapes a quote in a literal by doubling it.
                if index + 1 < len(line) and line[index + 1] == character:
                    continue
                quote = ""
            elif not quote:
                quote = character
        elif character in {"!", "#"} and not quote:
            return line[:index]
    return line


def _free_boundary(text: str) -> bool:
    lines = [_strip_inline_comment(line) for line in text.splitlines()]
    body = "\n".join(lines)
    # VMEC defaults LFREEB to true and runs free-boundary whenever a grid is named
    lfreeb = not re.search(r"(?i)\blfreeb\s*=\s*\.?f", body)
    mgrid = _MGRID.search(body)
    return bool(lfreeb and mgrid and mgrid.group(3).strip().lower()
                not in {"", "none", "dummy", "nonef"})


def _adiabatic(text: str) -> bool:
    body = "\n".join(_strip_inline_comment(line) for line in text.splitlines())
    match = re.search(r"(?im)^[^\n]*?\bgamma\s*=\s*([-+0-9.eEdD]+)", body)
    return bool(match) and float(match.group(1).replace("d", "e").replace("D", "e")) != 0.0


def _solves_free_boundary(code: str) -> bool:
    """Whether the code installed in this interpreter solves VMEC free-boundary inputs."""
    try:
        if code.lower() == "desc":
            from desc.input_reader import InputReader

            return hasattr(InputReader(), "free_boundary")
        if code.lower() == "gvec":
            import fbtools  # noqa: F401
            from gvec.coils import MgridField  # noqa: F401

            return True
    except Exception:
        return False
    return False


def _netcdf_mgrid_name(name: str) -> str:
    """Return the NetCDF fixture name for a legacy binary mgrid name.

    Older decks name MAKEGRID's binary output, for example ``mgrid.tftr``;
    its fixture is the NetCDF grid ``mgrid.tftr.nc`` built from the same coils.
    """
    return name if name.endswith(".nc") else name + ".nc"


def _index_candidates(search_roots: list[Path]) -> dict[str, Path]:
    """Return one existing fixture per basename, preferring the index."""

    candidates: dict[str, Path] = {}
    index_name = os.environ.get("VMEC_BENCHMARK_MGRID_INDEX", "")
    if index_name:
        index = Path(index_name)
        if index.is_file():
            for raw in index.read_text(errors="replace").splitlines():
                path = Path(raw.strip())
                if path.is_file() and path.name not in candidates:
                    candidates[path.name] = path
    for root in search_roots:
        if not root.is_dir():
            continue
        for path in root.rglob("mgrid*"):
            if path.is_file() and path.name not in candidates:
                candidates[path.name] = path
    return candidates


def _coil_groups(path: Path) -> int | None:
    """Number of coil groups of an mgrid, from its ``external_coil_groups`` dimension."""
    data = path.read_bytes()
    if data[:3] == b"CDF":
        # classic netCDF header: magic, record count, then the dimension list
        offset = 8
        tag, count = struct.unpack(">ii", data[offset:offset + 8])
        offset += 8
        if tag == 10:
            for _ in range(count):
                (size,) = struct.unpack(">i", data[offset:offset + 4])
                name = data[offset + 4:offset + 4 + size].decode()
                offset += 4 + (size + 3) // 4 * 4
                (length,) = struct.unpack(">i", data[offset:offset + 4])
                offset += 4
                if name == "external_coil_groups":
                    return length
        return None
    if data[:4] != b"\x89HDF":
        # not a netCDF file; the code reading it reports that
        return None
    try:
        import netCDF4  # type: ignore
    except ImportError:
        return None
    with netCDF4.Dataset(path) as grid:
        return len(grid.dimensions["external_coil_groups"])


def _highest_extcur(text: str) -> tuple[int, float]:
    """Highest EXTCUR index with a nonzero current, and that current."""
    currents: dict[int, float] = {}
    for start, values in _EXTCUR.findall(text):
        first = int(start) if start else 1
        for offset, value in enumerate(_NUMBER.findall(values)):
            currents[first + offset] = float(value.replace("D", "E").replace("d", "e"))
    nonzero = [index for index, value in currents.items() if value != 0.0]
    return (max(nonzero), currents[max(nonzero)]) if nonzero else (0, 0.0)


def prepare(
    source: Path,
    destination: Path,
    search_roots: list[Path],
    *,
    desc_compatible: bool = False,
    educational_compatible: bool = False,
    fixed_boundary_only: str = "",
    fixed_pressure_only: str = "",
) -> bool:
    """Write a normalized input and return whether all referenced fixtures exist.

    A missing magnetic-grid file is an unsupported benchmark fixture, not a
    solver failure.  Record that distinction next to the prepared input so
    the Fortran runner can report it without launching the code.
    """

    marker = destination.parent / "benchmark_unsupported.txt"
    marker.unlink(missing_ok=True)
    if source.suffix.lower() == ".json":
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        return True
    text = source.read_text(errors="replace")
    lines: list[str] = []
    saw_slash = False
    drop_continuation = False
    saw_indata = False
    saw_niter_array = bool(re.search(r"(?im)^\s*niter_array\s*=", text))
    saw_ftol_array = bool(re.search(r"(?im)^\s*ftol_array\s*=", text))
    legacy_unsupported = ""
    desc_field = desc_compatible and _free_boundary(text) and _solves_free_boundary("desc")
    for original_line in text.splitlines():
        # Strip comments before splitting compact assignment lines.  Otherwise
        # a prose comment such as ``! aspect ratio = 3`` is mistaken for a
        # namelist assignment by ``_ASSIGNMENT`` below.
        original_line = _strip_inline_comment(original_line)
        # DESC's parser requires one assignment per physical line, while
        # historical VMEC inputs commonly put ``MPOL = ... NTOR = ...`` (or
        # several Fourier coefficients) on one line.  Split only at tokens
        # that are unambiguously the start of another assignment; this keeps
        # array values and quoted strings intact for all other consumers.
        candidate_lines = [original_line]
        if desc_compatible or educational_compatible:
            candidate_lines = _ASSIGNMENT.split(original_line)
        for line in candidate_lines:
            if not saw_indata:
                if re.match(r"(?i)^\s*&indata\b", line):
                    saw_indata = True
                else:
                    # A few historical fixtures contain stale assignments
                    # before the actual namelist header.  They are not part
                    # of VMEC INDATA and make f90nml/DESC reject an otherwise
                    # usable equilibrium, so discard the preamble.
                    continue
            if (_END.match(line) or _SEPARATOR.match(line) or _FORTRAN_COMMENT.match(line)
                    or _FULL_LINE_COMMENT.match(line)):
                # VMEC accepts ``/`` as the namelist terminator.  A second
                # ``&END`` is interpreted as a new, unterminated group by f90nml.
                continue
            if desc_compatible and _DESC_DROP.match(line) and not (
                    desc_field and _FIELD.match(line)):
                # DESC reads the VMEC namelist itself and rejects solver controls
                # it does not consume.  Drop an unsupported assignment and its
                # continuation lines, retaining the equilibrium coefficients.
                drop_continuation = True
                continue
            if educational_compatible and _EDUCATIONAL_DROP.match(line):
                continue
            if educational_compatible and _NITER_SINGLE.match(line):
                if saw_niter_array:
                    continue
                line = re.sub(r"(?i)^\s*niter\s*=", " NITER_ARRAY =", line, count=1)
            if educational_compatible and _FTOL_SINGLE.match(line):
                if saw_ftol_array:
                    continue
                line = re.sub(r"(?i)^\s*ftol\s*=", " FTOL_ARRAY =", line, count=1)
            if desc_compatible and drop_continuation and "=" not in line:
                continue
            drop_continuation = False
            if _OUTPUT_CONTROL.match(line):
                continue
            ac_form = _AC_FORM.match(line)
            if ac_form:
                # AC_FORM = 0 selected the power series in I'(s), today's default.
                if float(ac_form.group(1).replace("d", "e").replace("D", "e")) != 0.0:
                    legacy_unsupported = "legacy AC_FORM other than 0"
                continue
            for pattern, name in _LEGACY_NAMES:
                line = pattern.sub(name, line)
            line = line.replace("(:)", "")
            if re.match(r"^\s*/\s*$", line):
                saw_slash = True
            lines.append(line)
    if not saw_slash:
        lines.append("/")

    candidates = _index_candidates(search_roots)
    staged_name = ""
    missing: list[str] = []
    for index, line in enumerate(lines):
        match = _MGRID.match(line)
        if not match:
            continue
        requested = match.group(3).strip()
        if not requested or requested.lower() in {"none", "dummy", "nonef"}:
            continue
        # Inputs from Windows checkouts occasionally retain backslashes even
        # when they are run on Linux.  Normalize before looking up a fixture.
        basename = Path(requested.replace("\\", "/")).name
        candidate = candidates.get(basename) or candidates.get(_netcdf_mgrid_name(basename))
        if candidate is None:
            missing.append(requested)
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        basename = candidate.name
        staged = destination.parent / basename
        if candidate.resolve() != staged.resolve():
            shutil.copy2(candidate, staged)
        # The solver runs in destination.parent, so retain a portable local
        # reference instead of an upstream absolute or repository-relative one.
        lines[index] = (
            f"{match.group(1)}{match.group(2)}{basename}{match.group(4)}{match.group(5)}"
        )
        staged_name = basename

    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text("\n".join(lines).rstrip() + "\n")
    if not re.search(r"(?im)^\s*&indata\b", text):
        message = "Unsupported: VMEC INDATA namelist is missing"
        marker.write_text(message + "\n")
        print(message, file=sys.stderr)
        return False
    if legacy_unsupported:
        message = f"Unsupported: {legacy_unsupported}"
        marker.write_text(message + "\n")
        print(message, file=sys.stderr)
        return False
    if desc_compatible and not fixed_boundary_only and not desc_field:
        fixed_boundary_only = "DESC"
    if fixed_boundary_only and _solves_free_boundary(fixed_boundary_only):
        fixed_boundary_only = ""
    if desc_compatible and not fixed_pressure_only:
        fixed_pressure_only = "DESC"
    if fixed_pressure_only and _adiabatic(text):
        message = (f"Unsupported: {fixed_pressure_only} holds the pressure profile fixed, "
                   "but GAMMA != 0 holds the mass profile fixed")
        marker.write_text(message + "\n")
        print(message, file=sys.stderr)
        return False
    if fixed_boundary_only and _free_boundary(text):
        message = (f"Unsupported: {fixed_boundary_only} reads free-boundary VMEC inputs "
                   "as fixed-boundary")
        marker.write_text(message + "\n")
        print(message, file=sys.stderr)
        return False
    if missing:
        unique_missing = list(dict.fromkeys(missing))
        message = "Unsupported: required MGRID fixture unavailable: " + ", ".join(unique_missing)
        marker.write_text(message + "\n")
        print(message, file=sys.stderr)
        return False
    if staged_name and _free_boundary(text):
        groups = _coil_groups(destination.parent / staged_name)
        index, current = _highest_extcur(text)
        if groups is not None and index > groups:
            message = (f"Unsupported: MGRID fixture {staged_name} has {groups} coil groups, "
                       f"but the deck sets EXTCUR({index}) = {current:g}")
            marker.write_text(message + "\n")
            print(message, file=sys.stderr)
            return False
    if staged_name:
        print(f"Staged {staged_name} for {destination.name}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument(
        "--search-root", action="append", type=Path, default=[],
        help="tree containing reusable MGRID fixtures (repeatable)",
    )
    parser.add_argument(
        "--desc", action="store_true",
        help="also remove VMEC controls that DESC rejects while parsing",
    )
    parser.add_argument(
        "--educational", action="store_true",
        help="also normalize controls rejected by the educational VMEC reader",
    )
    parser.add_argument(
        "--fixed-boundary-only", default="", metavar="CODE",
        help="mark free-boundary inputs unsupported for CODE",
    )
    parser.add_argument(
        "--fixed-pressure-only", default="", metavar="CODE",
        help="mark inputs with GAMMA != 0 unsupported for CODE",
    )
    args = parser.parse_args()
    roots = list(args.search_root)
    base_dir = os.environ.get("BENCHMARK_BASE_DIR", "")
    if base_dir:
        roots.append(Path(base_dir))
    return 0 if prepare(
        args.source,
        args.destination,
        roots,
        desc_compatible=args.desc,
        educational_compatible=args.educational,
        fixed_boundary_only=args.fixed_boundary_only,
        fixed_pressure_only=args.fixed_pressure_only,
    ) else 2


if __name__ == "__main__":
    raise SystemExit(main())
