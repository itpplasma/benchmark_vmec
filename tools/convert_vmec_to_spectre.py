#!/usr/bin/env python3
"""Convert a VMEC ``input.*`` namelist into a SPECTRE TOML input.

The conversion is SPECTRE's own ``simsvmec2spectre``, which places the
interfaces at equal toroidal flux and discretises VMEC's profiles onto them.
It expects a simsopt ``Vmec`` object; the namelist is handed over in the same
shape (``indata`` and ``boundary``) without simsopt.
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path
from types import SimpleNamespace

import numpy as np

MAX_NFEV = 500
_PROFILE_LENGTH = 21
_AUX_LENGTH = 101


def _mark_unsupported(destination: Path, message: str) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    (destination.parent / "benchmark_unsupported.txt").write_text(f"Unsupported: {message}\n")
    raise SystemExit(f"Unsupported: {message}")


def _boundary(text: str, field: str) -> dict[tuple[int, int], float]:
    """VMEC ``FIELD(n, m)`` assignments as ``{(m, n): value}``."""
    pattern = re.compile(
        rf"(?im)\b{field}\s*\(\s*(-?\d+)\s*,\s*(-?\d+)\s*\)\s*=\s*([+\-0-9.eEdD]+)"
    )
    return {
        (int(m), int(n)): float(value.replace("D", "E").replace("d", "e"))
        for n, m, value in pattern.findall(text)
    }


class _Boundary:
    """The part of simsopt's ``SurfaceRZFourier`` that the converter reads."""

    def __init__(self, rbc, zbs, mpol, ntor):
        self._rbc, self._zbs = rbc, zbs
        self.mpol, self.ntor = mpol, ntor
        modes = [(m, n) for m in range(mpol + 1) for n in range(-ntor, ntor + 1)]
        self.m = np.array([m for m, _ in modes])
        self.n = np.array([n for _, n in modes])

    def get_rc(self, m, n):
        return self._rbc.get((m, n), 0.0)

    def get_zs(self, m, n):
        return self._zbs.get((m, n), 0.0)


def _vmec_oriented(rbc, zbs):
    """Flip theta -> -theta when the boundary runs clockwise in (R, Z), as VMEC does internally."""
    theta = np.linspace(0.0, 2.0 * np.pi, 256, endpoint=False)
    r = sum(c * np.cos(m * theta) for (m, _), c in rbc.items())
    dz = sum(c * m * np.cos(m * theta) for (m, _), c in zbs.items())
    if np.sum(r * dz) >= 0.0:
        return rbc, zbs
    return (
        {(m, -n if m else n): c for (m, n), c in rbc.items()},
        {(m, -n if m else n): -c if m else c for (m, n), c in zbs.items()},
    )


def _padded(value, length: int) -> np.ndarray:
    values = np.atleast_1d(np.asarray([] if value is None else value, dtype=float))
    out = np.zeros(length)
    out[: min(len(values), length)] = values[:length]
    return out


def convert(source: Path, destination: Path, nvol: int) -> None:
    try:
        import f90nml  # type: ignore
        from spectre.converters.simsvmec2spectre import simsvmec2spectre  # type: ignore
        from spectre.file_io.toml_io import write_input_parameters_to_toml  # type: ignore
    except ImportError as exc:
        raise SystemExit(
            "SPECTRE conversion needs f90nml and the selected SPECTRE Python environment"
        ) from exc

    text = source.read_text(errors="replace")
    # Older fixtures close the namelist with ``&END`` or carry dashed separators.
    parse_text = re.sub(r"(?m)^\s*-{3,}\s*$\n?", "", text)
    parse_text = re.sub(r"(?im)^\s*&END\s*$", "/", parse_text)
    parse_text = re.sub(r"(?m)/\s*/\s*$", "/", parse_text)
    nml = f90nml.reads(parse_text)["indata"].todict()
    if nml.get("lasym", False):
        _mark_unsupported(destination, "SPECTRE's VMEC converter handles stellarator-symmetric boundaries only")

    indata = SimpleNamespace(
        curtor=float(nml.get("curtor", 0.0)),
        phiedge=float(nml.get("phiedge", 1.0)),
        nfp=int(nml.get("nfp", 1)),
        ncurr=int(nml.get("ncurr", 0)),
        pres_scale=float(nml.get("pres_scale", 1.0)),
        bloat=float(nml.get("bloat", 1.0)),
        spres_ped=float(nml.get("spres_ped", 1.0)),
    )
    for prefix in ("am", "ai", "ac"):
        setattr(indata, prefix, _padded(nml.get(prefix), _PROFILE_LENGTH))
        for suffix in ("_aux_s", "_aux_f"):
            setattr(indata, prefix + suffix, _padded(nml.get(prefix + suffix), _AUX_LENGTH))
    for kind in ("pmass", "piota", "pcurr"):
        # simsopt exposes the type names as bytes
        setattr(indata, kind + "_type", str(nml.get(kind + "_type", "power_series")).encode())

    mpol = int(nml.get("mpol", 4))
    ntor = int(nml.get("ntor", 0))
    rbc, zbs = _vmec_oriented(_boundary(text, "RBC"), _boundary(text, "ZBS"))
    boundary = _Boundary(rbc, zbs, mpol - 1, ntor)
    try:
        inputs = simsvmec2spectre(SimpleNamespace(indata=indata, boundary=boundary), nvol=max(1, int(nvol)))
    except RuntimeError as exc:
        if "not supported" in str(exc) or "supported" in str(exc):
            _mark_unsupported(destination, f"SPECTRE's VMEC converter: {exc}")
        raise
    # SPECTRE stops only on relative changes; its force error stops improving long before
    inputs.minimization.max_nfev = MAX_NFEV
    write_input_parameters_to_toml(inputs, str(destination))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--nvol", type=int, default=8)
    args = parser.parse_args()
    convert(args.source, args.destination, args.nvol)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
