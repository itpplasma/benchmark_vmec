#!/usr/bin/env python3
"""Write KIN6D's ``nested_input`` namelist for a fixed-boundary VMEC input.

KIN6D's ``nested_equilibrium`` prescribes iota(s) and p(s) as monomials in the
normalized toroidal flux s, with a positive toroidal flux. VMEC flips theta
internally when the boundary runs clockwise in (R, Z) and reverses iota with it;
the same flip is applied here, so iota keeps its handedness relative to the
boundary.

usage: convert_vmec_to_kin6d.py INPUT NAMELIST
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np

from convert_vmec_to_gvec import _dense_vmec_namelist, _mark_unsupported

# KIN6D's monomial profiles hold at most 33 coefficients
_MAX_COEFFICIENTS = 33


def _monomials(nml: dict, kind: str, prefix: str) -> np.ndarray:
    kind_type = str(nml.get(f"{kind}_type", "power_series")).strip().lower()
    if kind_type != "power_series":
        raise NotImplementedError(f"KIN6D takes power-series profiles, not {kind.upper()}_TYPE = '{kind_type}'")
    values = np.atleast_1d(np.asarray(nml.get(prefix, [0.0]), dtype=float))
    values = np.trim_zeros(np.nan_to_num(values), "b")
    if len(values) > _MAX_COEFFICIENTS:
        raise NotImplementedError(f"KIN6D holds at most {_MAX_COEFFICIENTS} {prefix.upper()} coefficients")
    return values if len(values) else np.zeros(1)


def _boundary(nml: dict) -> dict[str, dict[tuple[int, int], float]]:
    """Boundary coefficients keyed (n, m) as in VMEC, oriented counterclockwise in (R, Z)."""
    ntor = int(nml.get("ntor", 0))
    out = {}
    for field in ("rbc", "rbs", "zbc", "zbs"):
        dense = nml.get(field)
        out[field] = {}
        if not isinstance(dense, list):
            continue
        for m, row in enumerate(dense):
            for j, value in enumerate(row or []):
                if value:
                    out[field][(j - ntor, m)] = float(value)
    theta = np.linspace(0.0, 2.0 * np.pi, 512, endpoint=False)

    def at_zeta0(field, derivative=False):
        total = np.zeros_like(theta)
        for (_, m), c in out[field].items():
            if field in ("rbc", "zbc"):
                total += -c * m * np.sin(m * theta) if derivative else c * np.cos(m * theta)
            else:
                total += c * m * np.cos(m * theta) if derivative else c * np.sin(m * theta)
        return total

    area = np.sum((at_zeta0("rbc") + at_zeta0("rbs")) * (at_zeta0("zbc", True) + at_zeta0("zbs", True)))
    out["flipped"] = area < 0
    if out["flipped"]:
        # theta -> -theta: (n, m) -> (-n, m) for m > 0; sine coefficients change sign
        for field in ("rbc", "rbs", "zbc", "zbs"):
            sign = -1.0 if field in ("rbs", "zbs") else 1.0
            out[field] = {(-n if m else n, m): (sign * c if m else c) for (n, m), c in out[field].items()}
    return out


def convert(source: Path, destination: Path) -> None:
    try:
        nml = _dense_vmec_namelist(source)
    except ValueError as exc:
        _mark_unsupported(destination, str(exc))
    if int(nml.get("ncurr", 0)) == 1:
        _mark_unsupported(destination, "KIN6D prescribes iota; current-constrained inputs (NCURR = 1) are not supported")
    for key, neutral in (("bloat", 1.0), ("spres_ped", 1.0)):
        if abs(float(nml.get(key, neutral))) != neutral:
            _mark_unsupported(destination, f"KIN6D does not take {key.upper()} = {nml[key]}")
    try:
        scale = float(nml.get("pres_scale", 1.0))
        pressure = scale * _monomials(nml, "pmass", "am") if scale else np.zeros(1)
        iota = _monomials(nml, "piota", "ai")
    except NotImplementedError as exc:
        _mark_unsupported(destination, str(exc))
    if bool(nml.get("lrfp", False)):
        _mark_unsupported(destination, "KIN6D prescribes iota, not the safety factor of LRFP = T")
    boundary = _boundary(nml)
    if boundary["flipped"]:
        iota = -iota
    phiedge = abs(float(nml.get("phiedge", 1.0)))
    mpol = max([m for f in ("rbc", "rbs", "zbc", "zbs") for (_, m) in boundary[f]] + [1])
    ntor = max([abs(n) for f in ("rbc", "rbs", "zbc", "zbs") for (n, _) in boundary[f]] + [0])
    lines = [
        "&nested_input",
        f"  nfp = {int(nml.get('nfp', 1))}, mpol = {mpol}, ntor = {ntor}, phiedge = {phiedge!r},",
    ]
    for field in ("rbc", "rbs", "zbc", "zbs"):
        lines += [f"  {field}({n},{m}) = {float(c)!r}," for (n, m), c in sorted(boundary[field].items())]
    lines += [f"  iota({k}) = {float(c)!r}," for k, c in enumerate(iota) if c]
    lines += [f"  pressure({k}) = {float(c)!r}," for k, c in enumerate(pressure) if c]
    # VMEC's boundary angle is not a field-line angle, so the boundary field angle is free
    lines += ["  boundary_nodes = 16, degree = 3, angle_mpol = 4, tolerance = 1e-8, max_iterations = 400,", "/"]
    destination.write_text("\n".join(lines) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("input", type=Path)
    parser.add_argument("namelist", type=Path)
    args = parser.parse_args()
    convert(args.input, args.namelist)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
