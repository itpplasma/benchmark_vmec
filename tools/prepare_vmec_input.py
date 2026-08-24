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
from pathlib import Path


_MGRID = re.compile(
    r"(?im)^(\s*mgrid_file\s*=\s*)(['\"])([^'\"]*)(\2)(.*)$"
)
_OUTPUT_CONTROL = re.compile(
    r"(?i)^\s*(?:dump_[a-z0-9_]+|lspectrum_dump|ldiagno)\s*="
)
_END = re.compile(r"(?i)^\s*&end\s*$")


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


def prepare(source: Path, destination: Path, search_roots: list[Path]) -> None:
    if source.suffix.lower() == ".json":
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        return
    text = source.read_text(errors="replace")
    lines: list[str] = []
    saw_slash = False
    for line in text.splitlines():
        if _END.match(line):
            # VMEC accepts ``/`` as the namelist terminator.  A second
            # ``&END`` is interpreted as a new, unterminated group by f90nml.
            continue
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
    for index, line in enumerate(lines):
        match = _MGRID.match(line)
        if not match:
            continue
        requested = match.group(3).strip()
        if not requested or requested.lower() in {"none", "dummy", "nonef"}:
            continue
        basename = Path(requested).name
        candidate = candidates.get(basename)
        if candidate is None:
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
    if staged_name:
        print(f"Staged {staged_name} for {destination.name}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument(
        "--search-root", action="append", type=Path, default=[],
        help="tree containing reusable MGRID fixtures (repeatable)",
    )
    args = parser.parse_args()
    roots = list(args.search_root)
    base_dir = os.environ.get("BENCHMARK_BASE_DIR", "")
    if base_dir:
        roots.append(Path(base_dir))
    prepare(args.source, args.destination, roots)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
