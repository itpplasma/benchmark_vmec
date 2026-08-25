#!/usr/bin/env python3
"""Run one SPECTRE TOML input and retain its native JSON result."""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    args = parser.parse_args()
    from spectre import Force_Minimizer  # type: ignore

    result_path = args.input.with_name(f"{args.input.stem}_res.json")
    if result_path.exists():
        result_path.unlink()
    minimizer = Force_Minimizer(str(args.input))
    minimizer.minimize()
    # The standard SPECTRE example disables JSON output.  The benchmark keeps
    # it because it is the native, auditable result artifact for extraction.
    minimizer.postprocess(save_pkl=False, save_json=True, run_spec=False)
    try:
        result = json.loads(result_path.read_text(errors="replace"))
    except (OSError, json.JSONDecodeError):
        return 0
    if isinstance(result, dict) and result.get("success") is False:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
