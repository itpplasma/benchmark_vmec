#!/usr/bin/env python3
"""Run one SPECTRE TOML input and write the benchmark's ``spectre_result.json``."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np

FORCE_TOL = 1e-8


def _geometry(path: Path) -> dict[str, float]:
    """VMEC-style volume and aspect ratio from SPECTRE's HDF5 output.

    The innermost Fourier row is SPECTRE's coordinate axis, not the magnetic axis, so no
    ``raxis_cc`` is reported.
    """
    import h5py  # type: ignore

    with h5py.File(path, "r") as h5:
        out = h5["output"]
        im = np.asarray(out["im"][()])
        in_ = np.asarray(out["in"][()])
        rbc = np.asarray(out["Rbc"][()])
        zbs = np.asarray(out["Zbs"][()])
        rbs = np.asarray(out["Rbs"][()])
        zbc = np.asarray(out["Zbc"][()])

    theta = np.linspace(0.0, 2.0 * np.pi, 128, endpoint=False)
    zeta = np.linspace(0.0, 2.0 * np.pi, 64, endpoint=False)
    angle = np.outer(im, theta)[:, :, None] - np.outer(in_, zeta)[:, None, :]
    cos, sin = np.cos(angle), np.sin(angle)

    def surface(row):
        r = np.tensordot(rbc[row], cos, 1) + np.tensordot(rbs[row], sin, 1)
        dz = np.tensordot(-zbc[row] * im, sin, 1) + np.tensordot(zbs[row] * im, cos, 1)
        return r, dz

    r, dz = surface(-1)
    dtheta = 2.0 * np.pi / theta.size
    # Green's theorem in each poloidal plane, averaged over zeta (in_ carries NFP)
    area = abs(np.mean(np.sum(r * dz, axis=0) * dtheta))
    volume = abs(np.mean(np.sum(0.5 * r**2 * dz, axis=0) * dtheta)) * 2.0 * np.pi
    aminor = np.sqrt(area / np.pi)
    rmajor = volume / (2.0 * np.pi * area)
    return {
        "volume_p": volume,
        "aspect": rmajor / aminor,
        "rmajor_p": rmajor,
        "aminor_p": aminor,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    args = parser.parse_args()
    from spectre import Force_Minimizer  # type: ignore

    result_path = args.input.with_name(f"{args.input.stem}_res.json")
    summary_path = args.input.with_name("spectre_result.json")
    for stale in (result_path, summary_path):
        if stale.exists():
            stale.unlink()
    minimizer = Force_Minimizer(str(args.input))
    minimizer.minimize()
    minimizer.postprocess(save_pkl=False, save_json=True, run_spec=False)
    try:
        result = json.loads(result_path.read_text(errors="replace"))
    except (OSError, json.JSONDecodeError):
        result = {}
    success = bool(result.get("success", False)) if isinstance(result, dict) else False
    summary = {"message": str(result.get("message", ""))}
    if isinstance(result, dict) and result.get("fun"):
        summary["force_residual"] = float(np.sqrt(np.mean(np.square(result["fun"]))))
    h5_path = args.input.with_suffix(".h5")
    if h5_path.exists():
        summary.update(_geometry(h5_path))
    # SPECTRE has no absolute force tolerance of its own
    summary["success"] = success or summary.get("force_residual", np.inf) <= FORCE_TOL
    summary_path.write_text(json.dumps(summary, indent=2) + "\n")
    return 0 if summary["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
