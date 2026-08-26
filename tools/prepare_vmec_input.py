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
_SEPARATOR = re.compile(r"^\s*-{3,}\s*$")
_FORTRAN_COMMENT = re.compile(r"^\s*[cC](?:\s|$)")
_FULL_LINE_COMMENT = re.compile(r"^\s*[!#]")
_DESC_DROP = re.compile(
    r"(?i)^\s*(?:mgrid_file|time_slice|delt|ns_array|niter_array|"
    r"ftol_array|niter|nstep|nvacskip|type_precon|prec2d_threshold|"
    r"extcur|sigma_current)\b"
)
_ASSIGNMENT = re.compile(r"(?=\s+[A-Za-z_]\w*(?:\([^)]*\))?\s*=)")
_EDUCATIONAL_DROP = re.compile(
    r"(?i)^\s*(?:time_slice|type_precon|precon_type|prec2d_threshold|"
    r"bcrit|pt_type|ph_type)\b"
)
_NITER_SINGLE = re.compile(r"(?i)^\s*niter\s*=")
_FTOL_SINGLE = re.compile(r"(?i)^\s*ftol\s*=")


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


def prepare(
    source: Path,
    destination: Path,
    search_roots: list[Path],
    *,
    desc_compatible: bool = False,
    educational_compatible: bool = False,
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
    for original_line in text.splitlines():
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
            if desc_compatible and _DESC_DROP.match(line):
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
        candidate = candidates.get(basename)
        if candidate is None:
            missing.append(requested)
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
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
    if missing:
        unique_missing = list(dict.fromkeys(missing))
        message = "Unsupported: required MGRID fixture unavailable: " + ", ".join(unique_missing)
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
    ) else 2


if __name__ == "__main__":
    raise SystemExit(main())
