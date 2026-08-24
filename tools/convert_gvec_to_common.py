#!/usr/bin/env python3
"""Convert a GVEC ``*_State_final.dat`` file to benchmark metrics.

GVEC deliberately writes its native state text rather than VMEC NetCDF.  This
small bridge keeps that native artifact and emits the scalar fields used by the
ordinary benchmark; it does not pretend to reconstruct a lossless VMEC WOUT.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


FLOAT = r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[EeDd][+-]?\d+)?"


def number(value: str) -> float:
    return float(value.replace("D", "E").replace("d", "e"))


def convert(source: Path) -> dict[str, object]:
    text = source.read_text(errors="replace")
    metrics: dict[str, object] = {
        "success": True,
        "dimension": 3,
        "family": "vmec_family",
        "input_format": "vmec_indata",
        "output_format": "gvec_state",
        "source": str(source),
    }

    volume = re.search(
        rf"^\s*{FLOAT},\s*{FLOAT},\s*({FLOAT})\s*$",
        text[text.find("## a_minor,r_major,volume"):],
        re.MULTILINE,
    )
    if volume:
        # The preceding two columns are a_minor and r_major.
        fields = [number(item) for item in volume.group(0).split(",")]
        metrics["aminor_p"], metrics["rmajor_p"], metrics["volume_p"] = fields

    # The (0,0) X1 mode contains the magnetic-axis major radius at its first
    # radial knot.  It is the closest native equivalent to VMEC raxis_cc.
    x1 = re.search(
        rf"^\s*0,\s*0,\s*({FLOAT})",
        text[text.find("## X1:"):],
        re.MULTILINE,
    )
    if x1:
        metrics["raxis_cc"] = number(x1.group(1))

    # GVEC writes one profile row per radial knot: spos, phi, chi, iota,
    # pressure.  The first row is the magnetic axis.
    profile_start = text.find("## at X1_base IP point positions")
    profile_end = text.find("## a_minor,r_major,volume", profile_start)
    profile = text[profile_start:profile_end if profile_end >= 0 else None]
    rows = re.findall(
        rf"^\s*({FLOAT}),\s*({FLOAT}),\s*({FLOAT}),\s*({FLOAT}),\s*({FLOAT})\s*$",
        profile,
        re.MULTILINE,
    )
    if rows:
        metrics["iotaf_edge"] = number(rows[-1][3])
        metrics["pressure_axis"] = number(rows[0][4])

    # ``gvec.log`` is optional input to this converter; the native state file
    # itself remains sufficient for all scalar geometry/profile quantities.
    if "volume_p" in metrics and "rmajor_p" in metrics and "aminor_p" in metrics:
        metrics["aspect"] = float(metrics["rmajor_p"]) / float(metrics["aminor_p"])
    return metrics


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    result = convert(args.source)
    args.destination.write_text(json.dumps(result, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
