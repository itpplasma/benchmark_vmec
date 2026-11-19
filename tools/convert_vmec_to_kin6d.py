#!/usr/bin/env python3
"""Write KIN6D's ``nested_input`` namelist for a fixed-boundary VMEC input.

KIN6D's ``nested_equilibrium`` prescribes iota(s), p(s) and I(s) in the
normalized toroidal flux s, with a positive toroidal flux: power series as
monomials, every other VMEC profile type as piecewise cubic Hermite values and
slopes on 257 uniform knots plus the deck's spline knots, evaluated by VMEX's
profile module (``vmex/core/profiles.py`` of the VMEX checkout beside this
repository, or ``VMEC_BENCHMARK_VMEX_ROOT``). VMEC flips theta
internally when the boundary runs clockwise in (R, Z) and reverses iota with it;
the same flip is applied here, so iota keeps its handedness relative to the
boundary.

usage: convert_vmec_to_kin6d.py INPUT NAMELIST
"""
from __future__ import annotations

import argparse
import importlib.util
import os
from pathlib import Path

import numpy as np

from convert_vmec_to_gvec import _dense_vmec_namelist, _mark_unsupported

# KIN6D's monomial profiles hold at most 33 coefficients
_MAX_COEFFICIENTS = 33


_UNIFORM_KNOTS = 257


def _vmex_profiles():
    root = os.environ.get("VMEC_BENCHMARK_VMEX_ROOT")
    if not root:
        root = str(Path(os.environ.get("BENCHMARK_REPO_ROOT", Path(__file__).resolve().parents[1])).parent / "VMEX")
    path = Path(root) / "vmex" / "core" / "profiles.py"
    if not path.is_file():
        raise NotImplementedError(f"KIN6D's non-power-series profiles need VMEX's profile module at {path}")
    spec = importlib.util.spec_from_file_location("vmex_profiles", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _knots(extra) -> np.ndarray:
    """257 uniform knots plus the profile breakpoints inside (0, 1)."""
    knots = np.linspace(0.0, 1.0, _UNIFORM_KNOTS)
    inner = [float(k) for k in extra if 1e-9 < float(k) < 1.0 - 1e-9]
    knots = np.unique(np.concatenate([knots, inner]))
    knots = knots[np.concatenate([[True], np.diff(knots) > 1e-9])]
    knots[-1] = 1.0
    return knots


def _hermite(function, knots) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Knots, values and s-slopes of a profile function f(s) for KIN6D's Hermite input."""
    import jax

    jax.config.update("jax_enable_x64", True)
    scalar = function
    function = lambda x: jax.numpy.reshape(scalar(x), ())  # noqa: E731
    values = np.asarray(jax.vmap(function)(knots), dtype=float)
    slopes = np.asarray(jax.vmap(jax.grad(function))(knots), dtype=float)
    if not np.all(np.isfinite(values)):
        raise NotImplementedError("profile is not finite on [0, 1]")
    secant = np.diff(values)/np.diff(knots)
    for j in np.flatnonzero(~np.isfinite(slopes)):
        # one-sided at a singular end, e.g. sum_atan at s = 1
        slopes[j] = secant[min(j, len(secant) - 1)]
    return knots, values, slopes


def _aux(nml: dict, prefix: str) -> tuple[np.ndarray, np.ndarray]:
    s_knots = np.atleast_1d(np.asarray(nml.get(f"{prefix}_aux_s", []) or [], dtype=float))
    f_knots = np.atleast_1d(np.asarray(nml.get(f"{prefix}_aux_f", []) or [], dtype=float))
    # VMEC ends the knot list at the first non-increasing abscissa
    n = len(s_knots)
    for j in range(1, len(s_knots)):
        if s_knots[j] <= s_knots[j - 1]:
            n = j
            break
    n = min(n, len(f_knots))
    return s_knots[:n], f_knots[:n]


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


def _floats(values) -> str:
    return ", ".join(repr(float(v)) for v in values)


def convert(source: Path, destination: Path) -> None:
    try:
        nml = _dense_vmec_namelist(source)
    except ValueError as exc:
        _mark_unsupported(destination, str(exc))
    bloat = float(nml.get("bloat", 1.0))
    spres_ped = abs(float(nml.get("spres_ped", 1.0)))
    types = {kind: str(nml.get(f"{kind}_type", "power_series")).strip().lower() for kind in ("pmass", "piota", "pcurr")}
    lrfp = bool(nml.get("lrfp", False))
    ncurr = int(nml.get("ncurr", 0))
    scale = float(nml.get("pres_scale", 1.0))
    hermite = {}
    breaks = [spres_ped, 1.0/abs(bloat) if bloat else 1.0]
    for prefix in ("am", "ai", "ac"):
        breaks += list(_aux(nml, prefix)[0])
    knots = _knots(breaks)
    try:
        if types["pmass"] == "power_series" and bloat == 1.0 and spres_ped >= 1.0:
            pressure = scale*_monomials(nml, "pmass", "am") if scale else np.zeros(1)
        else:
            profiles = _vmex_profiles()
            am = np.atleast_1d(np.asarray(nml.get("am", [0.0]), dtype=float))
            aux_s, aux_f = _aux(nml, "am")
            hermite["pressure"] = _hermite(
                lambda x: profiles.pressure(types["pmass"], am, aux_s, aux_f, x, pres_scale=scale,
                                            bloat=bloat, spres_ped=spres_ped), knots)
            pressure = np.zeros(1)
        iota = np.zeros(1)
        if ncurr != 1:
            if types["piota"] == "power_series" and not lrfp:
                iota = _monomials(nml, "piota", "ai")
            else:
                profiles = _vmex_profiles()
                ai = np.atleast_1d(np.asarray(nml.get("ai", [0.0]), dtype=float))
                aux_s, aux_f = _aux(nml, "ai")
                hermite["iota"] = _hermite(
                    lambda x: profiles.iota(types["piota"], ai, aux_s, aux_f, x, lrfp=lrfp), knots)
    except NotImplementedError as exc:
        _mark_unsupported(destination, str(exc))
    boundary = _boundary(nml)
    if boundary["flipped"]:
        iota = -iota
        if "iota" in hermite:
            _, values, slopes = hermite["iota"]
            hermite["iota"] = (knots, -values, -slopes)
    current = None
    if ncurr == 1:
        curtor = float(nml.get("curtor", 0.0))
        # The current is physical and keeps its sign under the theta flip. With
        # positive flux KIN6D's has the opposite sign of VMEC's, which also flips
        # with PHIEDGE.
        sign = -np.sign(float(nml.get("phiedge", 1.0)))
        try:
            if types["pcurr"] == "power_series" and bloat == 1.0:
                # VMEC's AC is dI/ds; I(s) is scaled to CURTOR at the edge
                slope = _monomials(nml, "pcurr", "ac")
                enclosed = np.concatenate([[0.0], slope / np.arange(1, len(slope) + 1)])
                total = enclosed.sum()
                current = sign*curtor*enclosed/total if total else np.zeros(1)
            else:
                profiles = _vmex_profiles()
                ac = np.atleast_1d(np.asarray(nml.get("ac", [0.0]), dtype=float))
                aux_s, aux_f = _aux(nml, "ac")
                _, values, slopes = _hermite(
                    lambda x: profiles.current(types["pcurr"], ac, aux_s, aux_f, x, bloat=bloat), knots)
                factor = sign*curtor/values[-1] if values[-1] else 0.0
                hermite["current"] = (knots, factor*values, factor*slopes)
                current = np.zeros(1)
        except NotImplementedError as exc:
            _mark_unsupported(destination, str(exc))
        # VMEC ignores AI here; start with the sign of the total current
        iota = np.array([0.3*(np.sign(sign*curtor) or 1.0)])
    if current is None:
        if "iota" in hermite:
            _, values, _ = hermite["iota"]
            fine = np.linspace(0.0, 1.0, 1025)
            samples = np.interp(fine, knots, values)
        else:
            samples = np.polynomial.polynomial.polyval(np.linspace(0.0, 1.0, 201), iota)
        if np.any(samples == 0.0) or np.any(np.sign(samples) != np.sign(samples[0])):
            _mark_unsupported(destination, "KIN6D's frozen field needs an iota profile without zeros")
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
    if hermite:
        lines += [f"  n_knots = {len(knots)},", "  profile_knots = " + _floats(knots) + ","]
        for name, (_, values, slopes) in hermite.items():
            lines += [f"  {name}_type = 'hermite',", f"  {name}_values = " + _floats(values) + ",",
                      f"  {name}_slopes = " + _floats(slopes) + ","]
    lines += [f"  pressure({k}) = {float(c)!r}," for k, c in enumerate(pressure) if c]
    if current is not None:
        lines += ["  prescribe_current = .true.,"]
        lines += [f"  current({k}) = {float(c)!r}," for k, c in enumerate(current) if c]
    # VMEC's boundary angle is not a field-line angle, so the boundary field angle is free
    # KIN6D chooses its mesh and toroidal modes by its own truncation estimates
    lines += ["  angle_mpol = 4, tolerance = 1e-8, max_iterations = 400,", "/"]
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
