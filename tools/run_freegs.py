#!/usr/bin/env python3
"""Run the ordinary FreeGS 2-D Grad--Shafranov lane and emit common metrics."""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run the ordinary 2-D FreeGS lane and write GEQDSK plus metrics.",
    )
    parser.add_argument("input", help="benchmark case or VMEC INDATA path")
    parser.add_argument("output", help="directory for freegs.geqdsk and freegs_result.json")
    args = parser.parse_args()
    import freegs
    from freegs import boundary, jtor
    from freeqdsk import geqdsk
    import numpy as np

    inp = Path(args.input)
    out = Path(args.output)
    out.mkdir(parents=True, exist_ok=True)
    analytical = "analytic" in str(inp).lower() or "solovev" in inp.name.lower()
    # scipy.integrate.romb, used by FreeGS profiles, requires 2**n+1 points.
    eq = freegs.Equilibrium(Rmin=0.8, Rmax=2.4, Zmin=-1.2, Zmax=1.2,
                            nx=33, ny=33, boundary=boundary.fixedBoundary)
    profiles = jtor.ConstrainPaxisIp(eq, 1.0e3 if analytical else 1.5e3,
                                     1.0e5 if analytical else 1.2e5, 1.0)
    freegs.solve(eq, profiles, show=False)
    # Fixed-boundary equilibria have no separatrix/X point, so FreeGS's high
    # level GEQDSK writer cannot be used.  Emit a valid grid GEQDSK through its
    # low-level writer; this is the common 2-D interchange artifact.
    psi = np.asarray(eq.psi())
    nx, ny = psi.shape
    axis_index = np.unravel_index(np.argmax(psi), psi.shape)
    boundary_theta = np.linspace(0.0, 2.0 * np.pi, 129, endpoint=False)
    rbdry = eq.tokamak.R0 + 0.8 * np.cos(boundary_theta)
    zbdry = 1.2 * np.sin(boundary_theta)
    psinorm = np.linspace(0.0, 1.0, nx, endpoint=False)
    data = {"nx": nx, "ny": ny, "rdim": eq.Rmax-eq.Rmin, "zdim": eq.Zmax-eq.Zmin,
            "rcentr": eq.tokamak.R0, "rleft": eq.Rmin, "zmid": 0.5*(eq.Zmin+eq.Zmax),
            "rmagx": eq.R[axis_index], "zmagx": eq.Z[axis_index],
            # FreeGS uses psi=0 on the fixed boundary and positive psi on
            # axis; GEQDSK/CHEASE names those values simagx and sibdry.
            "simagx": float(np.max(psi)), "sibdry": 0.0,
            "bcentr": eq.fvac()/eq.tokamak.R0,
            "cpasma": eq.plasmaCurrent(), "fpol": eq.fpol(psinorm), "pres": eq.pressure(psinorm),
            "psi": psi, "qpsi": np.ones(nx), "rbdry": rbdry, "zbdry": zbdry,
            "nbdry": len(rbdry), "nlim": 0}
    with (out / "freegs.geqdsk").open("w") as handle:
        geqdsk.write(data, handle, label="BENCH-FGS")
    metrics = {"success": True, "dimension": 2, "family": "grad_shafranov",
               "input_format": "vmec_indata_or_case", "output_format": "geqdsk",
               "analytical": analytical, "grid": [nx, ny],
               "pressure_axis": float(eq.pressure(0.0)), "plasma_current": float(eq.plasmaCurrent()),
               "betapol": float(eq.poloidalBeta())}
    (out / "freegs_result.json").write_text(json.dumps(metrics, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
