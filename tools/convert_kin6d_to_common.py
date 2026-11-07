#!/usr/bin/env python3
"""Write the benchmark result sidecar from KIN6D's nested_equilibrium result file.

usage: convert_kin6d_to_common.py RESULT.nc SIDECAR.json
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

_QUANTITIES = (
    "volume_p", "aspect", "rmajor_p", "aminor_p", "raxis_cc", "iotaf_edge",
    "pressure_axis", "betatotal", "wb", "force_residual",
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("result", type=Path)
    parser.add_argument("sidecar", type=Path)
    args = parser.parse_args()
    import netCDF4  # type: ignore

    with netCDF4.Dataset(args.result) as data:
        summary = {"success": str(data.getncattr("converged")).strip() == "true"}
        summary.update({key: float(data[key][()]) for key in _QUANTITIES if key in data.variables})
    args.sidecar.write_text(json.dumps(summary, indent=1) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
