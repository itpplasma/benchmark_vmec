#!/usr/bin/env python3
"""Rebuild a complete comparison table from case-array output trees.

The array launcher keeps one output directory per case, but older launchers
overwrote the task-level CSV after each case.  This utility uses the frozen
case list, retained native outputs, and (when supplied) the Slurm stdout files
to recover one honest row for every case and implementation.  It is also
useful for auditing a partially merged array: a non-unsupported missing row
is an error rather than a fabricated failure.

Example::

    uv run --with netCDF4 --with h5py python tools/recover_array_results.py \
        --case-list case-suffixes.txt --log-dir checkout \
        --output benchmark_results/comparison_table.csv array-vmec array-native
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import shutil
from pathlib import Path
from typing import Any

import numpy as np
from netCDF4 import Dataset


IMPLEMENTATIONS = (
    "educational_vmec",
    "jvmec",
    "vmec2000",
    "vmecpp",
    "vmex",
    "parvmec",
    "desc",
    "gvec",
    "spec",
    "spectre",
    "freegs",
    "chease",
)
_VMEC_CODES = {"educational_vmec", "jvmec", "vmec2000", "vmecpp", "vmex", "parvmec", "desc"}
_SPECIAL_EXTENSIONS = {".json", ".vmec", ".txt", ".namelist", ".sp", ".toml", ".ini", ".yaml", ".geqdsk"}


def _case_name(path: str) -> str:
    """Mirror the benchmark runner's canonical name for a frozen path."""
    path = path.strip().replace("\\", "/")
    parts = path.split("/")
    if parts[0] == "cases":
        repo = "benchmark_vmec"
        relative = parts
    else:
        repo = parts[0]
        relative = parts[1:]
    for prefix in (
        ("src", "test", "resources"),
        ("tests",),
        ("test",),
        ("examples",),
        ("example",),
        ("test-CI", "examples"),
    ):
        if tuple(relative[: len(prefix)]) == prefix:
            relative = relative[len(prefix) :]
            break
    basename = relative[-1]
    if basename.startswith("input."):
        basename = basename[6:]
    else:
        basename = basename.rsplit(".", 1)[0] if "." in basename else basename
    if "." in basename and "." + basename.rsplit(".", 1)[1] in _SPECIAL_EXTENSIONS:
        basename = basename.rsplit(".", 1)[0]
    relative = [*relative[:-1], basename]
    return "/".join([repo, *relative])


def _case_slug(case: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]", "_", case.replace("/", "__"))


def _dimension(path: str) -> int:
    lowered = path.lower()
    if "/1d" in lowered:
        return 1
    if "/2d" in lowered:
        return 2
    return 3


def _suffix(path: str, suffix: str) -> bool:
    return path.lower().endswith(suffix)


def _support_error(path: str, implementation: str) -> str | None:
    """Return the runner's explicit skip reason, if this pair is unsupported."""
    lowered = path.lower()
    normalized = "/" + lowered.lstrip("/")
    basename = lowered.rsplit("/", 1)[-1]
    geqdsk = "/2d" in normalized and (_suffix(lowered, ".geqdsk") or _suffix(lowered, ".eqdsk"))
    native_gvec = "/gvec/" in normalized and (
        _suffix(lowered, "/parameter.ini")
        or _suffix(lowered, "/parameter.toml")
        or _suffix(lowered, "/parameter.yaml")
    )
    native_desc = "/desc/" in normalized and (basename.endswith("_desc") or "_desc." in basename)
    spec_case = _suffix(lowered, ".sp") and "/spectre/" not in normalized
    native_spectre = (_suffix(lowered, ".toml") or _suffix(lowered, ".sp")) and "/spectre/" in normalized

    if geqdsk and implementation != "chease":
        return "Unsupported: native GEQDSK fixture is reserved for CHEASE"
    if native_gvec and implementation != "gvec":
        return "Unsupported: native GVEC parameters are not VMEC inputs"
    if native_desc and implementation != "desc":
        return "Unsupported: native DESC fixtures are not VMEC inputs"
    if implementation == "freegs" and "/2d" not in lowered:
        return "Unsupported: FreeGS is restricted to 2-D Grad-Shafranov cases"
    if implementation == "gvec" and "/1d" in lowered:
        return "Unsupported: GVEC requires a 2-D or 3-D VMEC case"
    if implementation == "chease" and not geqdsk:
        return "Unsupported: CHEASE requires a 2-D GEQDSK input"
    if implementation == "spec" and not _suffix(lowered, ".sp"):
        return "Unsupported: SPEC requires a native .sp input"
    if implementation == "spectre" and not (
        _suffix(lowered, ".toml")
        or (_suffix(lowered, ".sp") and "/spectre/" in normalized)
        or "/input." in lowered
    ):
        return "Unsupported: SPECTRE requires VMEC input or native TOML"
    if spec_case and implementation != "spec":
        return "Unsupported: native SPEC cases are not VMEC inputs"
    if native_spectre and implementation != "spectre":
        return "Unsupported: native SPECTRE cases are not VMEC inputs"
    return None


def _metadata(path: str, implementation: str) -> dict[str, Any]:
    dimension = _dimension(path)
    if implementation == "freegs":
        return {"dimension": dimension, "family": "grad_shafranov", "input_format": "vmec_indata_or_case", "output_format": "geqdsk"}
    if implementation == "chease":
        return {"dimension": dimension, "family": "grad_shafranov", "input_format": "vmec_indata_via_geqdsk", "output_format": "geqdsk"}
    if implementation == "spec":
        return {"dimension": dimension, "family": "spec_mhd", "input_format": "spec_namelist", "output_format": "spec_hdf5"}
    if implementation == "spectre":
        return {"dimension": dimension, "family": "spectre_mhd", "input_format": "vmec_indata_or_spectre_toml", "output_format": "spectre_json"}
    if implementation == "gvec":
        return {"dimension": dimension, "family": "vmec_family", "input_format": "vmec_indata", "output_format": "gvec_state"}
    return {"dimension": dimension, "family": "vmec_family", "input_format": "vmec_indata", "output_format": "wout_netcdf"}


def _scalar(dataset: Dataset, name: str) -> float | None:
    if name not in dataset.variables:
        return None
    values = np.asarray(dataset.variables[name][:], dtype=float).ravel()
    finite = values[np.isfinite(values)]
    return float(finite[0]) if finite.size else None


def _values(dataset: Dataset, name: str) -> np.ndarray | None:
    if name not in dataset.variables:
        return None
    values = np.asarray(dataset.variables[name][:], dtype=float).ravel()
    finite = values[np.isfinite(values)]
    return finite if finite.size else None


def _wout_values(path: Path) -> dict[str, float]:
    files = sorted(path.glob("wout*.nc"))
    if not files:
        return {}
    with Dataset(files[-1]) as dataset:
        values: dict[str, float] = {}
        for name in ("wb", "betatotal", "aspect", "volume_p"):
            value = _scalar(dataset, name)
            if value is not None:
                values[name] = value
        raxis = _values(dataset, "raxis_cc")
        if raxis is not None:
            values["raxis_cc"] = float(raxis[0])
        iota = _values(dataset, "iotaf")
        if iota is None:
            iota = _values(dataset, "iotas")
        if iota is not None:
            values["iotaf_edge"] = float(iota[-1])
        # jVMEC and older VMEC++ files can omit these scalar fields.  Match
        # the benchmark plotter's geometry fallback for those files.
        if {"aspect", "volume_p", "raxis_cc"} - values.keys():
            arrays = {
                name: np.asarray(dataset.variables[name][:], dtype=float)
                for name in ("rmnc", "rmns", "zmnc", "zmns", "xm", "xn")
                if name in dataset.variables
            }
            rmnc = arrays.get("rmnc")
            zmns = arrays.get("zmns")
            xm = arrays.get("xm")
            xn = arrays.get("xn")
            if rmnc is not None and zmns is not None and xm is not None and xn is not None:
                if rmnc.ndim == 2 and rmnc.shape[0] == xm.size:
                    rmnc = rmnc.T
                if zmns.ndim == 2 and zmns.shape[0] == xm.size:
                    zmns = zmns.T
                rmns = arrays.get("rmns")
                zmnc = arrays.get("zmnc")
                if rmns is None:
                    rmns = np.zeros_like(rmnc)
                elif rmns.ndim == 2 and rmns.shape[0] == xm.size:
                    rmns = rmns.T
                if zmnc is None:
                    zmnc = np.zeros_like(zmns)
                elif zmnc.ndim == 2 and zmnc.shape[0] == xm.size:
                    zmnc = zmnc.T
                mode00 = int(np.argmin(np.abs(xm) + np.abs(xn)))
                if "raxis_cc" not in values:
                    values["raxis_cc"] = float(rmnc[0, mode00])
                theta = np.arange(256) * 2.0 * np.pi / 256.0
                phi = np.arange(64) * 2.0 * np.pi / 64.0
                phase = xm[:, None, None] * theta[None, :, None] - xn[:, None, None] * phi[None, None, :]
                radius = np.sum(
                    rmnc[-1, :, None, None] * np.cos(phase)
                    + rmns[-1, :, None, None] * np.sin(phase),
                    axis=0,
                )
                height = np.sum(
                    -zmnc[-1, :, None, None] * xm[:, None, None] * np.sin(phase)
                    + zmns[-1, :, None, None] * xm[:, None, None] * np.cos(phase),
                    axis=0,
                )
                rmajor = 0.5 * (float(np.nanmax(radius)) + float(np.nanmin(radius)))
                aminor = 0.5 * (float(np.nanmax(radius)) - float(np.nanmin(radius)))
                if "aspect" not in values and aminor > 0.0:
                    values["aspect"] = rmajor / aminor
                if "volume_p" not in values:
                    values["volume_p"] = abs(0.5 * float(np.nanmean(radius**2 * height)) * (2.0 * np.pi) ** 2)
    return values


def _json_values(path: Path, filename: str) -> tuple[bool, dict[str, float]]:
    try:
        data = json.loads((path / filename).read_text(errors="replace"))
    except (OSError, json.JSONDecodeError):
        return False, {}
    if not isinstance(data, dict):
        return False, {}
    success = data.get("success") is True
    values = {name: float(data[name]) for name in ("aspect", "raxis_cc", "volume_p", "iotaf_edge", "pressure_axis", "plasma_current") if isinstance(data.get(name), (int, float))}
    return success, values


def _native_values(path: Path, implementation: str) -> tuple[bool, dict[str, float]]:
    if implementation == "gvec":
        return _json_values(path, "gvec_result.json")
    if implementation == "freegs":
        return _json_values(path, "freegs_result.json")
    if implementation == "chease":
        return _json_values(path, "chease_result.json")
    if implementation == "spectre":
        return bool(sorted(path.glob("*_res.json"))), {}
    if implementation == "spec":
        files = sorted(path.glob("*.sp.h5"))
        if not files:
            return False, {}
        try:
            import h5py  # type: ignore

            with h5py.File(files[-1], "r") as handle:
                def endpoint(name: str, last: bool) -> float | None:
                    if name not in handle:
                        return None
                    values = np.asarray(handle[name][()], dtype=float).ravel()
                    return float(values[-1] if last else values[0]) if values.size else None

                values = {}
                for key, dataset in (("volume_p", "/output/volume"), ("plasma_current", "/input/physics/curtor")):
                    if dataset in handle:
                        value = float(np.asarray(handle[dataset][()], dtype=float).ravel()[0])
                        values[key] = value
                for key, dataset, last in (("raxis_cc", "/input/physics/Rac", False), ("iotaf_edge", "/input/physics/iota", True)):
                    value = endpoint(dataset, last)
                    if value is not None:
                        values[key] = value
                return "/output/volume" in handle, values
        except (OSError, ImportError, ValueError):
            return False, {}
    try:
        values = _wout_values(path)
    except (OSError, ValueError, KeyError):
        return False, {}
    return bool(values), values


def _load_csv_rows(sources: list[Path]) -> dict[tuple[str, str], dict[str, str]]:
    rows: dict[tuple[str, str], dict[str, str]] = {}
    for source in sources:
        for filename in sorted(source.rglob("comparison_table*.csv")):
            with filename.open(newline="") as stream:
                for row in csv.DictReader(stream):
                    key = (row.get("case", ""), row.get("implementation", ""))
                    if key[0] and key[1]:
                        rows[key] = row
    return rows


def _load_log_statuses(sources: list[Path], log_dir: Path | None) -> dict[tuple[str, str], tuple[str, str]]:
    if log_dir is None:
        return {}
    task_names = {
        task_root.name
        for source in sources
        for implementation_root in source.iterdir()
        if implementation_root.is_dir()
        for task_root in implementation_root.iterdir()
        if task_root.is_dir()
    }
    statuses: dict[tuple[str, str], tuple[str, str]] = {}
    for filename in sorted(log_dir.glob("slurm-vmec-case-array-*.out")):
        if filename.name.removeprefix("slurm-vmec-case-array-").removesuffix(".out") not in task_names:
            continue
        current_case = ""
        for line in filename.read_text(errors="replace").splitlines():
            if line.startswith("Running test case: "):
                current_case = line.removeprefix("Running test case: ").strip()
            match = re.search(r"✓ ([A-Za-z0-9_]+) completed", line)
            if match and current_case:
                statuses[(current_case, match.group(1).lower())] = ("success", "")
            match = re.search(r"✗ ([A-Za-z0-9_]+) produced no comparable result: (.*)$", line)
            if match and current_case:
                statuses[(current_case, match.group(1).lower())] = ("failed", match.group(2).strip())
            match = re.search(r"✗ ([A-Za-z0-9_]+) failed$", line)
            if match and current_case:
                statuses[(current_case, match.group(1).lower())] = ("failed", "Run failed")
    return statuses


def _row(case: str, path: str, implementation: str, status: str, error: str, values: dict[str, float]) -> dict[str, Any]:
    metadata = _metadata(path, implementation)
    result: dict[str, Any] = {"case": case, "implementation": implementation, "status": status, "error": error, **metadata}
    for name in ("wb", "betatotal", "aspect", "raxis_cc", "volume_p", "iotaf_edge", "pressure_axis", "plasma_current"):
        result[name] = values.get(name, 0.0) if status == "success" else ""
    return result


def rebuild(case_list: Path, sources: list[Path], output: Path, log_dir: Path | None) -> None:
    frozen: dict[str, tuple[str, str]] = {}
    for line in case_list.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        path = line.strip()
        case = _case_name(path)
        frozen[_case_slug(case)] = (case, path)
    csv_rows = _load_csv_rows(sources)
    log_statuses = _load_log_statuses(sources, log_dir)
    records: dict[tuple[str, str], dict[str, Any]] = {}

    for source in sources:
        for implementation_root in sorted(source.iterdir()):
            implementation = implementation_root.name
            if implementation not in IMPLEMENTATIONS:
                continue
            for task_root in sorted(implementation_root.iterdir()):
                if not task_root.is_dir():
                    continue
                for case_dir in sorted(task_root.iterdir()):
                    if not case_dir.is_dir() or case_dir.name == "jvmec_reports":
                        continue
                    if case_dir.name not in frozen:
                        raise SystemExit(f"unknown case slug in {case_dir}: {case_dir.name}")
                    case, path = frozen[case_dir.name]
                    key = (case, implementation)
                    status, error = log_statuses.get(key, ("", ""))
                    implementation_dir = case_dir / implementation
                    if not implementation_dir.is_dir():
                        continue
                    unsupported = implementation_dir / "benchmark_unsupported.txt"
                    failure = implementation_dir / "benchmark_failure.txt"
                    if unsupported.is_file():
                        status, error = "failed", unsupported.read_text(errors="replace").splitlines()[0].strip()
                    elif failure.is_file():
                        status, error = "failed", failure.read_text(errors="replace").splitlines()[0].strip()
                    if not status:
                        fallback = csv_rows.get(key)
                        if fallback:
                            status, error = fallback.get("status", ""), fallback.get("error", "")
                    native_success, values = _native_values(implementation_dir, implementation)
                    if not status:
                        status = "success" if native_success else "failed"
                        error = "" if native_success else "Run failed"
                    if status == "success" and not native_success:
                        status, error = "failed", "Result extraction failed"
                    records[key] = _row(case, path, implementation, status, error, values)

    for case, path in frozen.values():
        for implementation in IMPLEMENTATIONS:
            key = (case, implementation)
            if key in records:
                continue
            unsupported = _support_error(path, implementation)
            if unsupported:
                records[key] = _row(case, path, implementation, "failed", unsupported, {})
                continue
            fallback = csv_rows.get(key)
            if fallback:
                records[key] = fallback
                continue
            raise SystemExit(f"missing non-unsupported result row: {case},{implementation}")

    fields = ("case", "implementation", "status", "error", "dimension", "family", "input_format", "output_format", "wb", "betatotal", "aspect", "raxis_cc", "volume_p", "iotaf_edge", "pressure_axis", "plasma_current")
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for key in sorted(records):
            writer.writerow(records[key])

    # Unsupported branches have no native output directory.  Materialize an
    # exact marker in the generated result tree so the CSV and tree retain the
    # same complete case/implementation inventory.  Existing failed output
    # directories are preserved; only their missing marker is added.
    result_root = output.parent
    for row in records.values():
        if row["status"] != "failed":
            continue
        implementation_dir = result_root / _case_slug(str(row["case"])) / str(row["implementation"])
        error = str(row["error"])
        if error.startswith("Unsupported:"):
            if implementation_dir.exists():
                for child in implementation_dir.iterdir():
                    if child.is_dir():
                        shutil.rmtree(child)
                    else:
                        child.unlink()
            implementation_dir.mkdir(parents=True, exist_ok=True)
            marker = implementation_dir / "benchmark_unsupported.txt"
        else:
            implementation_dir.mkdir(parents=True, exist_ok=True)
            marker = implementation_dir / "benchmark_failure.txt"
        if not marker.exists():
            marker.write_text(error + "\n")
    print(f"wrote {len(records)} rows for {len(frozen)} cases and {len(IMPLEMENTATIONS)} implementations to {output}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case-list", type=Path, required=True)
    parser.add_argument("--log-dir", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("sources", type=Path, nargs="+")
    args = parser.parse_args()
    rebuild(args.case_list, args.sources, args.output, args.log_dir)


if __name__ == "__main__":
    main()
