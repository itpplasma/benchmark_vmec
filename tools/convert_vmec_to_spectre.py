#!/usr/bin/env python3
"""Convert a VMEC ``input.*`` namelist into a SPECTRE TOML input.

This is the ordinary (non-differentiable) benchmark bridge.  SPECTRE ships a
Simsopt-based converter, but Simsopt is an optional, MPI-heavy dependency and
is not required merely to transfer a VMEC boundary and profiles.  The bridge
therefore uses SPECTRE's own ``InputParameters`` model and keeps the generated
TOML next to the run output for inspection.
"""
from __future__ import annotations

import argparse
import math
import re
from pathlib import Path


def _number(value: object, default: float) -> float:
    try:
        result = float(value)
    except (TypeError, ValueError):
        return default
    return result if math.isfinite(result) else default


def _first(value: object, default: float) -> float:
    if isinstance(value, (list, tuple)):
        return _first(value[0], default) if value else default
    return _number(value, default)


def _polynomial(coefficients: object, s: float) -> float:
    if not isinstance(coefficients, (list, tuple)):
        coefficients = [coefficients]
    return sum(_number(coefficient, 0.0) * s**index for index, coefficient in enumerate(coefficients))


def _boundary(text: str, field: str, mpol: int, ntor: int) -> dict[str, float]:
    pattern = re.compile(
        rf"(?im)\b{field}\s*\(\s*(-?\d+)\s*,\s*(-?\d+)\s*\)\s*=\s*"
        r"([+\-0-9.eEdD]+)"
    )
    values: dict[str, float] = {}
    for match in pattern.finditer(text):
        # VMEC's namelist storage is indexed (n, m), while SPECTRE's public
        # Fourier maps use (m, n).  Preserve the physical mode rather than
        # accidentally turning an axisymmetric Solovev boundary into an
        # n=1 toroidal surface.
        n, m, value = (int(match.group(1)), int(match.group(2)), match.group(3))
        # VMEC fixtures can retain coefficients from a higher-resolution
        # output even after MPOL/NTOR was reduced in the namelist.  SPECTRE
        # allocates its Fourier arrays from those limits; passing the stale
        # modes through causes an out-of-bounds access and MPI_ABORT.  VMEC's
        # valid ranges are m=0..MPOL and n=-NTOR..NTOR.
        if abs(m) > mpol or abs(n) > ntor:
            continue
        values[f"({m}, {n})"] = _number(value.replace("D", "E").replace("d", "e"), 0.0)
    return values


def convert(source: Path, destination: Path, nvol: int) -> None:
    try:
        import f90nml  # type: ignore
        from spectre.file_io.input_parameters import InputParameters  # type: ignore
        from spectre.file_io.toml_io import write_input_parameters_to_toml  # type: ignore
    except ImportError as exc:
        raise SystemExit(
            "SPECTRE conversion needs f90nml and the selected SPECTRE Python environment"
        ) from exc

    text = source.read_text(errors="replace")
    # Older VMEC fixtures close the namelist with both ``/`` and a trailing
    # ``&END``.  Fortran accepts that legacy spelling, while f90nml treats the
    # second terminator as a new, unterminated group.
    parse_text = re.sub(r"(?im)^\s*&END\s*$", "", text)
    try:
        indata = f90nml.reads(parse_text)["indata"]
    except Exception as exc:  # pragma: no cover - parser diagnostics are code-specific
        raise SystemExit(f"Could not parse VMEC INDATA {source}: {exc}") from exc

    nvol = max(1, min(int(nvol), 32))
    nfp = max(1, int(_first(indata.get("nfp"), 1.0)))
    mpol = max(1, min(int(_first(indata.get("mpol"), 4.0)), 16))
    ntor = max(0, min(int(_first(indata.get("ntor"), 0.0)), 8))
    phiedge = _first(indata.get("phiedge"), 1.0)
    tflux = [(index + 1) / nvol for index in range(nvol)]
    pressure = [_polynomial(indata.get("am", [0.0]), s) for s in tflux]

    # The volume-current constraint is accepted for both VMEC prescribed-iota
    # and prescribed-current cases, and remains well-defined when CURTOR=0.
    # This avoids SPECTRE's singular iota-only initialization for axisymmetric
    # boundaries while retaining the ordinary VMEC current scale.
    curtor = _first(indata.get("curtor"), 0.0)
    ivolume = [curtor / nvol] * nvol
    physics = {
        "igeometry": 2 if ntor == 0 else 3,
        "nfp": nfp,
        "nvol": nvol,
        "mpol": mpol,
        "ntor": ntor,
        "lconstraint": 3,
        "lfreebound": 0,
        "phiedge": phiedge,
        "pscale": 1.0,
        "tflux": tflux,
        "pressure": pressure,
        "adiabatic": pressure,
        "ivolume": ivolume,
        "isurf": [0.0] * nvol,
        "rbc": _boundary(text, "RBC", mpol, ntor),
        "zbs": _boundary(text, "ZBS", mpol, ntor),
        "rbs": _boundary(text, "RBS", mpol, ntor),
        "zbc": _boundary(text, "ZBC", mpol, ntor),
    }
    params = InputParameters(
        physics=physics,
        numeric={
            "linitialize": 1,
            "lchangeangle": True,
            "lautoinitbn": 1,
            "ndiscrete": 2,
            "impol": -4,
            "intor": -4,
        },
        # Henneberg's auxiliary representation must fit inside the physical
        # Fourier grid.  Keeping the historical fixed value of 8 for small
        # VMEC inputs makes SPECTRE assemble a Jacobian with inconsistent
        # dimensions (and can end in MPI_ABORT); choose the largest valid
        # auxiliary grid for this case instead.
        minimization={
            "max_niter": 200,
            "max_nfev": 200,
            "mmax": max(0, min(8, mpol - 1)),
            "nmax": max(0, min(8, ntor - 1)) if ntor > 0 else 0,
        },
    )
    destination.parent.mkdir(parents=True, exist_ok=True)
    write_input_parameters_to_toml(params, str(destination))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--nvol", type=int, default=4)
    args = parser.parse_args()
    convert(args.source, args.destination, args.nvol)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
