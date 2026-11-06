#!/usr/bin/env python3
"""Write VMEC ``input.*`` namelists for GVEC's native test cases.

GVEC parameters are read with GVEC's own reader and mapped back through the
inverse of ``pygvec convert-params --vmec``: the toroidal direction is flipped
with ``flip_parameters_zeta`` (its own inverse) and the (m, n) modes are copied.
Cases initialised from a VMEC wout take boundary and profiles from that wout.
Only GVEC's (R, Z, phi) map (``which_hmap = 1``) has a VMEC equivalent.

usage: convert_gvec_to_vmec.py GVEC_ROOT CASES_DIR
"""
from __future__ import annotations

import argparse
from copy import deepcopy
from pathlib import Path

import numpy as np

# VMEC2000 holds 101 knots (ndatafmax) and finds the end of the list at the first zero after it
_KNOTS = 0.5 * (1.0 - np.cos(np.pi * np.arange(100) / 99))
_RESOLUTION = """  NS_ARRAY = 16 51
  NITER_ARRAY = 5000 40000
  FTOL_ARRAY = 1.0E-10 1.0E-14
  NSTEP = 200
  DELT = 0.5
"""


def _array(name: str, values) -> str:
    return f"  {name} = " + " ".join(f"{float(v):.16E}" for v in np.atleast_1d(values)) + "\n"


def _modes(name: str, coefficients: dict) -> str:
    return "".join(
        f"  {name}({n},{m}) = {float(v):.16E}\n" for (m, n), v in sorted(coefficients.items()) if v != 0.0
    )


def _profile(prefix: str, kind: str, profile: dict, gvec) -> tuple[str, float]:
    """VMEC profile lines for a GVEC profile and the scale VMEC applies to them."""
    if profile.get("type", "polynomial") == "polynomial":
        return f"  {kind}_TYPE = 'power_series'\n" + _array(prefix, profile["coefs"]), profile.get("scale", 1.0)
    values = gvec.util.profile_from_parameters(profile)(_KNOTS)
    return (
        f"  {kind}_TYPE = 'cubic_spline'\n" + _array(prefix + "_AUX_S", _KNOTS) + _array(prefix + "_AUX_F", values),
        1.0,
    )


def _current(profile: dict, gvec) -> str:
    """VMEC current lines for GVEC's enclosed toroidal current I(s)."""
    current = gvec.util.profile_from_parameters(profile)
    curtor = float(current(1.0))
    text = f"  NCURR = 1\n  CURTOR = {curtor:.16E}\n"
    if profile.get("type", "polynomial") == "polynomial":
        # VMEC's power series gives dI/ds
        coefs = np.asarray(profile["coefs"], dtype=float)
        return text + "  PCURR_TYPE = 'power_series'\n" + _array("AC", np.arange(1, len(coefs)) * coefs[1:])
    return text + "  PCURR_TYPE = 'cubic_spline_i'\n" + _array("AC_AUX_S", _KNOTS) + _array("AC_AUX_F", current(_KNOTS))


def _boundary_from_file(params, path: Path) -> None:
    """Project a gridded boundary file onto the parameters' Fourier basis, as GVEC does."""
    import netCDF4

    with netCDF4.Dataset(path) as data:
        grid = data["boundary"]
        nfp = int(data["NFP"][()])
        theta, zeta = (np.asarray(grid[k][()]) for k in ("theta(:)", "zeta(:)"))
        values = {"X1": np.asarray(grid["X(::)"][()]), "X2": np.asarray(grid["Y(::)"][()])}
    params["nfp"] = nfp
    for x, default in (("X1", "_cos_"), ("X2", "_sin_")):
        mmax, nmax = params.get(f"{x}_mn_max", (1, 0))
        modes = [(m, n) for m in range(mmax + 1) for n in range(-nmax, nmax + 1) if m > 0 or n >= 0]
        phase = [np.outer(m * theta, np.ones_like(zeta)) - n * nfp * zeta[None, :] for m, n in modes]
        kinds = {"_cos_": ["cos"], "_sin_": ["sin"], "_sincos_": ["sin", "cos"]}[params.get(f"{x}_sin_cos", default)]
        columns = [(kind, mode, getattr(np, kind)(p)) for kind in kinds for mode, p in zip(modes, phase)]
        columns = [c for c in columns if not (c[0] == "sin" and c[1] == (0, 0))]
        fit = np.linalg.lstsq(np.stack([c[2].ravel() for c in columns], axis=1), values[x].ravel(), rcond=None)[0]
        for kind in kinds:
            params[f"{x}_b_{kind}"] = {mode: v for (k, mode, _), v in zip(columns, fit) if k == kind and abs(v) > 1e-14}


def from_parameters(params, gvec, folder: Path) -> str:
    if int(params.get("which_hmap", 1)) != 1:
        raise ValueError(f"which_hmap = {params['which_hmap']} has no VMEC equivalent")
    params = deepcopy(params)
    if int(params.get("getBoundaryFromFile", -1)) == 1:
        _boundary_from_file(params, folder / str(params["boundary_filename"]).strip())
    # GVEC's default flux, set before the flip so that it changes sign like a given one
    params.setdefault("phiedge", 1.0)
    params = gvec.util.flip_parameters_zeta(params)
    mpol = max(int(params.get(f"{x}_mn_max", (1, 0))[0]) for x in ("X1", "X2")) + 1
    ntor = max(int(params.get(f"{x}_mn_max", (1, 0))[1]) for x in ("X1", "X2"))
    lasym = "X1_b_sin" in params or "X2_b_cos" in params
    text = (
        f"  LASYM = {'T' if lasym else 'F'}\n  NFP = {int(params.get('nfp', 1))}\n"
        f"  MPOL = {mpol}\n  NTOR = {ntor}\n  PHIEDGE = {float(params.get('phiedge', 1.0)):.16E}\n"
    )
    pres, pres_scale = _profile("AM", "PMASS", params["pres"], gvec)
    text += pres + f"  PRES_SCALE = {pres_scale:.16E}\n  GAMMA = 0.0\n"
    if "I_tor" in params:
        text += _current(params["I_tor"], gvec)
    else:
        iota = dict(params["iota"])
        if iota.get("type", "polynomial") == "polynomial":
            iota["coefs"] = np.asarray(iota["coefs"], dtype=float) * iota.pop("scale", 1.0)
        text += "  NCURR = 0\n" + _profile("AI", "PIOTA", iota, gvec)[0]
    boundary = {key: params.get(key, {}) for key in ("X1_b_cos", "X2_b_sin", "X1_b_sin", "X2_b_cos")}
    axis = {key: params.get(key) for key in ("X1_a_cos", "X2_a_sin", "X1_a_sin", "X2_a_cos")}
    for a, b in (("X1_a_cos", "X1_b_cos"), ("X2_a_sin", "X2_b_sin"), ("X1_a_sin", "X1_b_sin"), ("X2_a_cos", "X2_b_cos")):
        if axis[a] is None:
            axis[a] = {(0, n): v for (m, n), v in boundary[b].items() if m == 0}
    for name, key in (("RAXIS_CC", "X1_a_cos"), ("ZAXIS_CS", "X2_a_sin"), ("RAXIS_CS", "X1_a_sin"), ("ZAXIS_CC", "X2_a_cos")):
        if axis[key] and (lasym or name in ("RAXIS_CC", "ZAXIS_CS")):
            text += _array(name, [axis[key].get((0, n), 0.0) for n in range(ntor + 1)])
    for name, key in (("RBC", "X1_b_cos"), ("ZBS", "X2_b_sin"), ("RBS", "X1_b_sin"), ("ZBC", "X2_b_cos")):
        text += _modes(name, boundary[key])
    return text


def from_wout(path: Path) -> str:
    import netCDF4

    with netCDF4.Dataset(path) as wout:
        def var(name, default=None):
            return wout[name][()] if name in wout.variables else default

        lasym = bool(var("lasym__logical__", 0))
        # the converged profiles, since older wouts keep neither NCURR nor the input coefficients
        s_full = np.linspace(0.0, 1.0, len(var("presf")))
        text = (
            f"  LASYM = {'T' if lasym else 'F'}\n  NFP = {int(var('nfp'))}\n"
            f"  MPOL = {int(var('mpol'))}\n  NTOR = {int(var('ntor'))}\n"
            f"  PHIEDGE = {float(var('phi')[-1]):.16E}\n  NCURR = 0\n  GAMMA = 0.0\n  PRES_SCALE = 1.0\n"
            "  PMASS_TYPE = 'cubic_spline'\n" + _array("AM_AUX_S", _KNOTS)
            + _array("AM_AUX_F", np.interp(_KNOTS, s_full, var("presf")))
            + "  PIOTA_TYPE = 'cubic_spline'\n" + _array("AI_AUX_S", _KNOTS)
            + _array("AI_AUX_F", np.interp(_KNOTS, s_full, var("iotaf")))
        )
        xm, xn = np.asarray(var("xm"), int), np.asarray(var("xn"), int) // int(var("nfp"))
        fields = [("RBC", "rmnc"), ("ZBS", "zmns")] + ([("RBS", "rmns"), ("ZBC", "zmnc")] if lasym else [])
        for name, key in fields:
            edge = np.asarray(var(key))[-1]
            text += _modes(name, {(m, n): v for m, n, v in zip(xm, xn, edge)})
        for name, key in (("RAXIS_CC", "raxis_cc"), ("ZAXIS_CS", "zaxis_cs"), ("RAXIS_CS", "raxis_cs"), ("ZAXIS_CC", "zaxis_cc")):
            if var(key) is not None and (lasym or name in ("RAXIS_CC", "ZAXIS_CS")):
                text += _array(name, var(key))
    return text


def convert(parameter: Path, gvec) -> str:
    params = gvec.util.read_parameters(parameter)
    if int(params.get("whichInitEquilibrium", 0)) == 1:
        return from_wout(parameter.parent / str(params["vmecwoutfile"]).strip())
    return from_parameters(params, gvec, parameter.parent)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("gvec_root", type=Path)
    parser.add_argument("cases", type=Path)
    args = parser.parse_args()
    import gvec  # type: ignore

    folders = sorted({p.parent for p in args.gvec_root.glob("test-CI/*/*/parameter.*")})
    folders += sorted({p.parent for p in args.gvec_root.glob("python/examples/**/parameter.*")})
    sources: dict[str, list[str]] = {}
    for folder in folders:
        # the harness runs the first of these that exists
        parameter = next((folder / f"parameter.{x}" for x in ("ini", "toml", "yaml") if (folder / f"parameter.{x}").exists()), None)
        if parameter is None:
            continue
        source = parameter.relative_to(args.gvec_root).as_posix()
        try:
            body = convert(parameter, gvec)
        except (ValueError, KeyError) as exc:
            print(f"skip {source}: {exc}")
            continue
        # GVEC variants that differ only in numerics share one VMEC case
        sources.setdefault(body, []).append(source)
    for body, names in sources.items():
        folder = Path(names[0]).parent
        name = folder.name if folder.parent.name == "examples" and folder.parts[0] == "test-CI" else f"{folder.parent.name}_{folder.name}"
        header = "".join(f"! converted from GVEC {n}\n" for n in names)
        out = args.cases / name / f"input.{name}"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text("&INDATA\n" + header + "  LFREEB = F\n" + _RESOLUTION + body + "/\n")
        print(f"wrote {out} for {len(names)} GVEC case(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
