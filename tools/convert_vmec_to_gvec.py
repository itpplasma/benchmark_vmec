#!/usr/bin/env python3
"""Convert a VMEC namelist to a GVEC parameter file.

GVEC's upstream converter expects every Fourier boundary array to be a dense
rectangular Fortran array.  VMEC inputs commonly use sparse ``RBC(m,n)`` and
``ZBS(m,n)`` assignments, which ``f90nml`` represents as ragged lists.  This
bridge densifies those assignments before delegating to GVEC's ordinary
converter; no differentiable data or solver-specific state is introduced.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

import f90nml


_BOUNDARY_FIELDS = ("rbc", "rbs", "zbc", "zbs")
_BOUNDARY_ASSIGNMENT = re.compile(
    r"(?im)^\s*(RBC|RBS|ZBC|ZBS)\s*\(\s*(-?\d+)\s*,\s*(-?\d+)\s*\)\s*=\s*"
    r"([+\-0-9.eEdD]+)"
)


def _dense_vmec_namelist(source: Path) -> dict:
    # A number of upstream VMEC fixtures use both ``/`` and a trailing
    # ``&END``.  Fortran accepts this legacy spelling, while f90nml treats the
    # second terminator as a new, unterminated namelist group.
    text = source.read_text(errors="replace")
    parse_text = re.sub(r"(?im)^\s*&END\s*$", "", text)
    parsed = f90nml.reads(parse_text)
    nml = parsed["indata"].todict()
    mpol = int(nml.get("mpol", 2))
    ntor = int(nml.get("ntor", 0))
    dense = {
        field: [[0.0 for _ in range(2 * ntor + 1)] for _ in range(mpol)]
        for field in _BOUNDARY_FIELDS
    }
    found: set[str] = set()
    for field, n_text, m_text, value_text in _BOUNDARY_ASSIGNMENT.findall(
        text
    ):
        field = field.lower()
        # VMEC declares boundary arrays as (n, m), unlike GVEC's (m, n)
        # maps.  Preserve that convention while placing values in the dense
        # GVEC array.
        n = int(n_text)
        m = int(m_text)
        if field not in dense or not (0 <= m < mpol and -ntor <= n <= ntor):
            continue
        dense[field][m][n + ntor] = float(value_text.replace("D", "E").replace("d", "e"))
        found.add(field)

    # Replace f90nml's sparse-array metadata with the dense VMEC convention:
    # n runs from -NTOR through +NTOR.
    for field in found:
        nml[field] = dense[field]
    start_index = nml.setdefault("_start_index", {})
    for field in found:
        start_index[field] = [-ntor, 0]
    return nml


def convert(source: Path, destination: Path) -> None:
    try:
        import gvec.util as gvec_util  # type: ignore
    except ImportError as exc:  # pragma: no cover - exercised in the GVEC env
        raise SystemExit("GVEC conversion needs the selected GVEC Python environment") from exc

    parameters = gvec_util.parameters_from_vmec(_dense_vmec_namelist(source), source.name)
    # GVEC's fixed-profile path requires an initial iota profile when VMEC
    # supplies neither AI nor AC.  Current-constrained TOML runs initialize
    # iota from I_tor themselves, so leave that path intact.
    if "iota" not in parameters and "I_tor" not in parameters:
        parameters["iota"] = {"type": "polynomial", "coefs": [0.0]}
    # VMEC and GVEC use opposite toroidal-angle conventions.  Apply that
    # conversion first, then correct the poloidal orientation if the resulting
    # cross-section is still left-handed.  Flipping zeta alone cannot change
    # the signed cross-sectional area and left HELIOTRON-like fixtures would
    # otherwise reach GVEC with negative Jacobians.
    parameters = gvec_util.flip_parameters_zeta(parameters)
    if not gvec_util.check_boundary_direction(parameters):
        parameters = gvec_util.flip_parameters_theta(parameters)
    if (
        parameters.get("X1_sin_cos") == "_cos_"
        and "X1_b_cos" in parameters
        and (1, 0) in parameters["X1_b_cos"]
        and parameters["X1_b_cos"][(1, 0)] < 0
    ):
        parameters = gvec_util.shift_boundary_theta_pi(parameters)
    gvec_util.write_parameters(parameters, destination)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    convert(args.source, args.destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
