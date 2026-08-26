#!/usr/bin/env python3
"""Plot completed benchmark outputs, quality diagnostics, and runtimes.

Usage::

    python tools/plot_benchmark_results.py benchmark_results-slurm-1788058

The input directory is a Slurm result directory.  Native NetCDF WOUT files
are used for the surfaces and scalar plots, so incomplete or unsupported rows
are skipped.  Solver-reported timing lines are used for ``runtime.png`` and
``runtime.csv``; codes without a machine-readable timing line are omitted from
that figure rather than silently mixing in a different measurement.  Quality
diagnostics are read from native output/logs when available and are never
inferred from scalar agreement.  All outputs are written to the selected
output folder.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import textwrap
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from netCDF4 import Dataset


IMPLEMENTATION_ORDER = (
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

SCALAR_METRICS = (
    "wb",
    "betatotal",
    "aspect",
    "raxis_cc",
    "volume_p",
    "iotaf_edge",
    "pressure_axis",
    "plasma_current",
)

METRIC_LABELS = {
    "wb": "wb (native units)",
    "betatotal": "betatotal (dimensionless)",
    "aspect": "aspect (dimensionless)",
    "raxis_cc": "raxis_cc (native length)",
    "volume_p": "volume_p (native volume)",
    "iotaf_edge": "iotaf_edge (dimensionless)",
    "pressure_axis": "pressure_axis (native pressure)",
    "plasma_current": "plasma_current (native current)",
    "runtime_seconds": "reported runtime (s)",
}

QUALITY_FIELDS = (
    "case",
    "implementation",
    "quality_status",
    "quality_metric",
    "residual",
    "tolerance",
    "residual_over_tolerance",
    "iterations",
    "solver_status",
    "quality_source",
)


def _implementation_label(name: str) -> str:
    return {
        "educational_vmec": "educ. VMEC",
        "jvmec": "jVMEC",
        "vmec2000": "VMEC2000",
        "vmecpp": "VMEC++",
        "vmex": "VMEX",
        "parvmec": "PARVMEC",
        "desc": "DESC",
        "gvec": "GVEC",
        "spec": "SPEC",
        "spectre": "SPECTRE",
        "freegs": "FreeGS",
        "chease": "CHEASE",
    }.get(name, name)


def _array(dataset: Dataset, name: str) -> np.ndarray | None:
    if name not in dataset.variables:
        return None
    value = np.ma.asarray(dataset.variables[name][:])
    return np.asarray(value.filled(np.nan), dtype=float)


def _scalar(dataset: Dataset, name: str) -> float | None:
    value = _array(dataset, name)
    if value is None:
        return None
    value = value.ravel()
    finite = value[np.isfinite(value)]
    return float(finite[0]) if finite.size else None


def _derived_scalars(dataset: Dataset) -> dict[str, float]:
    """Derive common scalars for WOUT-like files that omit them (notably jVMEC)."""
    rmnc = _array(dataset, "rmnc")
    zmns = _array(dataset, "zmns")
    xm = _array(dataset, "xm")
    xn = _array(dataset, "xn")
    if rmnc is None or zmns is None or xm is None or xn is None:
        return {}
    mode_count = xm.size
    if rmnc.ndim != 2 or rmnc.shape[1] != mode_count:
        rmnc = rmnc.T
    if zmns.ndim != 2 or zmns.shape[1] != mode_count:
        zmns = zmns.T
    rmns = _array(dataset, "rmns")
    zmnc = _array(dataset, "zmnc")
    if rmns is None:
        rmns = np.zeros_like(rmnc)
    elif rmns.shape != rmnc.shape:
        rmns = rmns.T
    if zmnc is None:
        zmnc = np.zeros_like(zmns)
    elif zmnc.shape != zmns.shape:
        zmnc = zmnc.T

    mode00 = int(np.argmin(np.abs(xm) + np.abs(xn)))
    theta = np.arange(256) * 2.0 * np.pi / 256.0
    phi = np.arange(64) * 2.0 * np.pi / 64.0
    phase = xm[:, None, None] * theta[None, :, None] - xn[:, None, None] * phi[None, None, :]
    row = -1
    radius = np.sum(
        rmnc[row, :, None, None] * np.cos(phase)
        + rmns[row, :, None, None] * np.sin(phase),
        axis=0,
    )
    height_theta = np.sum(
        -zmnc[row, :, None, None] * xm[:, None, None] * np.sin(phase)
        + zmns[row, :, None, None] * xm[:, None, None] * np.cos(phase),
        axis=0,
    )
    finite_radius = radius[np.isfinite(radius)]
    if not finite_radius.size:
        return {}
    rmax = float(finite_radius.max())
    rmin = float(finite_radius.min())
    rmajor = 0.5 * (rmax + rmin)
    aminor = 0.5 * (rmax - rmin)
    volume_integrand = radius**2 * height_theta
    finite_volume = volume_integrand[np.isfinite(volume_integrand)]
    volume = abs(0.5 * float(finite_volume.mean()) * (2.0 * np.pi) ** 2) if finite_volume.size else np.nan
    return {
        "raxis_cc": float(rmnc[0, mode00]),
        "aspect": rmajor / aminor if aminor > 0.0 else np.nan,
        "volume_p": volume,
    }


def _metric_values(dataset: Dataset, metrics: tuple[str, ...]) -> dict[str, float]:
    values = {metric: _scalar(dataset, metric) for metric in metrics}
    if "iotaf_edge" in metrics and values.get("iotaf_edge") is None:
        for name in ("iotaf", "iotas"):
            values["iotaf_edge"] = _edge_scalar(dataset, name)
            if values["iotaf_edge"] is not None:
                break
    if "pressure_axis" in metrics and values.get("pressure_axis") is None:
        values["pressure_axis"] = _scalar(dataset, "presf")
    if "plasma_current" in metrics and values.get("plasma_current") is None:
        values["plasma_current"] = _scalar(dataset, "ctor")
    derived = _derived_scalars(dataset)
    return {
        metric: values[metric] if values[metric] is not None else derived.get(metric)
        for metric in metrics
        if values[metric] is not None or metric in derived
    }


def _edge_scalar(dataset: Dataset, name: str) -> float | None:
    values = _array(dataset, name)
    if values is None:
        return None
    finite = values.ravel()
    finite = finite[np.isfinite(finite)]
    return float(finite[-1]) if finite.size else None


def _sidecar_metric_values(path: Path, metrics: tuple[str, ...]) -> dict[str, float]:
    """Read common scalar fields from a retained JSON sidecar.

    GVEC and the Grad--Shafranov adapters do not emit VMEC NetCDF.  Their
    sidecars are deliberately sparse; only fields that are present are
    returned, so a missing quantity remains an honest gap in the plot.
    """
    try:
        data = json.loads(path.read_text(errors="replace"))
    except (OSError, json.JSONDecodeError):
        return {}
    if not isinstance(data, dict) or data.get("success") is False:
        return {}
    values: dict[str, float] = {}
    for metric in metrics:
        value = data.get(metric)
        if isinstance(value, (int, float)) and np.isfinite(value):
            values[metric] = float(value)
    return values


def _spec_metric_values(path: Path, metrics: tuple[str, ...]) -> dict[str, float]:
    """Read common scalars emitted by SPEC's native HDF5 output."""
    files = sorted(path.glob("*.sp.h5"))
    if not files:
        return {}
    try:
        import h5py  # type: ignore
    except ImportError:
        return {}

    def scalar(handle, name: str, last: bool = False) -> float | None:
        if name not in handle:
            return None
        values = np.asarray(handle[name][()], dtype=float).ravel()
        finite = values[np.isfinite(values)]
        if not finite.size:
            return None
        return float(finite[-1] if last else finite[0])

    mapping = {
        "betatotal": ("output/BetaTotal", False),
        "volume_p": ("output/volume", False),
        "plasma_current": ("input/physics/curtor", False),
        "raxis_cc": ("input/physics/Rac", False),
        "iotaf_edge": ("input/physics/iota", True),
    }
    try:
        with h5py.File(files[-1], "r") as handle:
            return {
                metric: value
                for metric in metrics
                if metric in mapping
                for value in [scalar(handle, *mapping[metric])]
                if value is not None
            }
    except (OSError, ValueError):
        return {}


def _case_metric_outputs(case_dir: Path, metrics: tuple[str, ...]):
    """Yield implementation/metric pairs from WOUTs and common sidecars."""
    for implementation_dir in sorted(p for p in case_dir.iterdir() if p.is_dir()):
        if any((implementation_dir / marker).is_file()
               for marker in ("benchmark_failure.txt", "benchmark_unsupported.txt")):
            continue
        files = sorted(implementation_dir.glob("wout*.nc"))
        if files:
            try:
                with Dataset(files[-1]) as dataset:
                    values = _metric_values(dataset, metrics)
            except (OSError, ValueError):
                values = {}
            if values:
                yield implementation_dir.name, values
            continue

        for filename in ("gvec_result.json", "freegs_result.json", "chease_result.json"):
            sidecar = implementation_dir / filename
            if not sidecar.is_file():
                continue
            values = _sidecar_metric_values(sidecar, metrics)
            if values:
                yield implementation_dir.name, values
            break

        if implementation_dir.name == "spec":
            values = _spec_metric_values(implementation_dir, metrics)
            if values:
                yield implementation_dir.name, values


def _surface(dataset: Dataset, radius_index: int = -1, phi: float = 0.0):
    """Reconstruct a VMEC Fourier surface at fixed toroidal angle."""
    rmnc = _array(dataset, "rmnc")
    zmns = _array(dataset, "zmns")
    xm = _array(dataset, "xm")
    xn = _array(dataset, "xn")
    if rmnc is None or zmns is None or xm is None or xn is None:
        return None

    mode_count = xm.size
    if rmnc.ndim != 2 or rmnc.shape[1] != mode_count:
        rmnc = rmnc.T
    if zmns.ndim != 2 or zmns.shape[1] != mode_count:
        zmns = zmns.T
    rmns = _array(dataset, "rmns")
    zmnc = _array(dataset, "zmnc")
    if rmns is None:
        rmns = np.zeros_like(rmnc)
    elif rmns.shape != rmnc.shape:
        rmns = rmns.T
    if zmnc is None:
        zmnc = np.zeros_like(zmns)
    elif zmnc.shape != zmns.shape:
        zmnc = zmnc.T

    theta = np.linspace(0.0, 2.0 * np.pi, 500)
    phase = xm[:, None] * theta[None, :] - xn[:, None] * phi
    row = radius_index if radius_index >= 0 else rmnc.shape[0] + radius_index
    radius = np.sum(
        rmnc[row, :, None] * np.cos(phase)
        + rmns[row, :, None] * np.sin(phase),
        axis=0,
    )
    height = np.sum(
        zmnc[row, :, None] * np.cos(phase)
        + zmns[row, :, None] * np.sin(phase),
        axis=0,
    )
    return radius, height


def _case_outputs(result_root: Path):
    for case_dir in sorted(p for p in result_root.iterdir() if p.is_dir()):
        outputs = []
        for implementation_dir in sorted(p for p in case_dir.iterdir() if p.is_dir()):
            files = sorted(implementation_dir.glob("wout*.nc"))
            if files:
                outputs.append((implementation_dir.name, files[-1]))
        if outputs:
            yield case_dir, outputs


def _short_case_label(case: str) -> str:
    """Keep the x-axis readable without hiding the case identity entirely."""
    label = case.split("/")[-1].replace("_", " ")
    return label if len(label) <= 20 else label[:19] + "…"


_RUNTIME_PATTERNS = {
    "jvmec": (
        "jvmec.log",
        re.compile(r"total execution time:\s*([0-9]+(?:\.[0-9]*)?(?:[Ee][+-]?[0-9]+)?)\s*s", re.I),
        "total execution time (s)",
    ),
    "vmecpp": (
        "vmecpp.log",
        re.compile(r"^real\s+([0-9]+(?:\.[0-9]*)?(?:[Ee][+-]?[0-9]+)?)\s*$", re.I | re.M),
        "GNU time real (s)",
    ),
    "vmex": (
        "vmex.log",
        re.compile(r"TOTAL COMPUTATIONAL TIME \(SEC\)\s*([0-9]+(?:\.[0-9]*)?(?:[Ee][+-]?[0-9]+)?)", re.I),
        "total computational time (s)",
    ),
    "educational_vmec": (
        "educational_vmec.log",
        re.compile(r"^real\s+([0-9]+(?:\.[0-9]*)?(?:[Ee][+-]?[0-9]+)?)\s*$", re.I | re.M),
        "GNU time real (s)",
    ),
    "desc": (
        "desc.log",
        re.compile(r"^real\s+([0-9]+(?:\.[0-9]*)?(?:[Ee][+-]?[0-9]+)?)\s*$", re.I | re.M),
        "GNU time real (s)",
    ),
    "freegs": (
        "freegs.log",
        re.compile(r"^real\s+([0-9]+(?:\.[0-9]*)?(?:[Ee][+-]?[0-9]+)?)\s*$", re.I | re.M),
        "GNU time real (s)",
    ),
    "chease": (
        "chease.log",
        re.compile(r"^real\s+([0-9]+(?:\.[0-9]*)?(?:[Ee][+-]?[0-9]+)?)\s*$", re.I | re.M),
        "GNU time real (s)",
    ),
    "vmec2000": (
        "vmec2000.log",
        re.compile(r"TOTAL COMPUTATIONAL TIME \(SEC\)\s*([0-9]+(?:\.[0-9]*)?(?:[Ee][+-]?[0-9]+)?)", re.I),
        "total computational time (s)",
    ),
    "parvmec": (
        "parvmec.log",
        re.compile(r"TOTAL COMPUTATIONAL TIME \(SEC\)\s*([0-9]+(?:\.[0-9]*)?(?:[Ee][+-]?[0-9]+)?)", re.I),
        "total computational time (s)",
    ),
    "gvec": (
        "gvec.log",
        re.compile(r"GVEC finished after\s*([0-9]+(?:\.[0-9]*)?(?:[Ee][+-]?[0-9]+)?)\s*seconds", re.I),
        "GVEC finished after (s)",
    ),
    "spec": (
        "spec.log",
        re.compile(
            r"^ending :\s*([0-9]+(?:\.[0-9]*)?(?:[Ee][+-]?[0-9]+)?)\s+:"
            r"\s*myid=\s*0\s*;\s*completion ;\s*time=",
            re.I | re.M,
        ),
        "SPEC completion time (s)",
    ),
    "spectre": (
        "spectre.log",
        re.compile(
            r"Minimization done \(Time elapsed\s+(\d+):(\d+):([0-9]+(?:\.[0-9]*)?)\)",
            re.I,
        ),
        "SPECTRE minimization time (s)",
    ),
}


def _runtime_seconds(implementation: str, match) -> float:
    if implementation == "spectre" and isinstance(match, tuple):
        hours, minutes, seconds = match
        return 3600.0 * float(hours) + 60.0 * float(minutes) + float(seconds)
    return float(match)


def _successful_output(implementation_dir: Path) -> bool:
    """Return whether an implementation directory contains a successful result."""
    for filename in ("gvec_result.json", "freegs_result.json", "chease_result.json"):
        sidecar = implementation_dir / filename
        if not sidecar.is_file():
            continue
        try:
            data = json.loads(sidecar.read_text(errors="replace"))
        except (OSError, json.JSONDecodeError):
            return False
        return isinstance(data, dict) and data.get("success") is True

    if implementation_dir.name == "spectre":
        result_files = sorted(implementation_dir.glob("*_res.json"))
        if not result_files:
            return False
        try:
            data = json.loads(result_files[-1].read_text(errors="replace"))
        except (OSError, json.JSONDecodeError):
            return False
        return isinstance(data, dict) and data.get("success") is True

    if list(implementation_dir.glob("wout*.nc")):
        return True

    # SPEC retains its native HDF5 and completion files rather than a WOUT.
    if implementation_dir.name == "spec":
        return bool(list(implementation_dir.glob("*.sp.h5")) and
                    list(implementation_dir.glob("*.sp.end")))
    return False


def _quality_row(
    case: str,
    implementation: str,
    *,
    status: str = "unavailable",
    metric: str = "",
    residual: float | None = None,
    tolerance: float | None = None,
    iterations: float | None = None,
    solver_status: str | None = None,
    source: str = "",
) -> dict[str, object]:
    ratio = None
    if residual is not None and tolerance is not None and tolerance > 0.0:
        ratio = residual / tolerance
    return {
        "case": case,
        "implementation": implementation,
        "quality_status": status,
        "quality_metric": metric,
        "residual": residual,
        "tolerance": tolerance,
        "residual_over_tolerance": ratio,
        "iterations": iterations,
        "solver_status": solver_status,
        "quality_source": source,
    }


def _wout_quality(case: str, implementation_dir: Path) -> dict[str, object] | None:
    files = sorted(implementation_dir.glob("wout*.nc"))
    if not files:
        return None

    def scalar(dataset: Dataset, name: str) -> float | None:
        value = _scalar(dataset, name)
        return value if value is not None and np.isfinite(value) else None

    try:
        with Dataset(files[-1]) as dataset:
            components = [scalar(dataset, name) for name in ("fsqr", "fsqz", "fsql")]
            components = [abs(value) for value in components if value is not None]
            tolerance = scalar(dataset, "ftolv")
            ier_flag = scalar(dataset, "ier_flag")
            iterations = scalar(dataset, "niter")
            if not components:
                return None
            residual = max(components)
            ratio = residual / tolerance if tolerance is not None and tolerance > 0.0 else None
            converged = (ier_flag is None or ier_flag == 0.0) and (ratio is None or ratio <= 1.0)
            return _quality_row(
                case,
                implementation_dir.name,
                status="converged" if converged else "not_converged",
                metric="max(|fsqr|,|fsqz|,|fsql|)",
                residual=residual,
                tolerance=tolerance,
                iterations=iterations,
                solver_status=str(int(ier_flag)) if ier_flag is not None else None,
                source=files[-1].name,
            )
    except (OSError, ValueError, KeyError):
        return None


def _desc_quality(case: str, implementation_dir: Path) -> dict[str, object] | None:
    log_file = implementation_dir / "desc.log"
    if not log_file.is_file():
        return None
    text = log_file.read_text(errors="replace")
    matches = re.findall(
        r"Maximum absolute Force error:\s+[^\n]*?-->\s*"
        r"([0-9]+(?:\.[0-9]*)?(?:[Ee][+-]?[0-9]+)?)\s+\(normalized\)",
        text,
    )
    if not matches:
        return None
    iterations = re.findall(r"Iterations:\s*(\d+)", text)
    successful = bool(re.search(r"Optimization terminated successfully\.", text))
    return _quality_row(
        case,
        "desc",
        status="converged" if successful else "not_converged",
        metric="maximum normalized force error",
        residual=float(matches[-1]),
        iterations=float(iterations[-1]) if iterations else None,
        solver_status="success" if successful else "failure",
        source=log_file.name,
    )


def _gvec_quality(case: str, implementation_dir: Path) -> dict[str, object] | None:
    log_file = implementation_dir / "gvec.log"
    if not log_file.is_file():
        return None
    text = log_file.read_text(errors="replace")
    matches = re.findall(
        r"GVEC finished after\s+[^\n]*?using\s+(\d+)\s+iterations\s+"
        r"\(totalIter\s*=\s*(\d+)\)\s+with\s+\|force\|\s*=\s*"
        r"([0-9]+(?:\.[0-9]*)?(?:[Ee][+-]?[0-9]+)?)\s+"
        r"\(minimize_tol\s*=\s*([0-9]+(?:\.[0-9]*)?(?:[Ee][+-]?[0-9]+)?)\)",
        text,
        re.I,
    )
    if not matches:
        return None
    _, total_iterations, residual, tolerance = matches[-1]
    residual_value = float(residual)
    tolerance_value = float(tolerance)
    return _quality_row(
        case,
        "gvec",
        status="converged" if residual_value <= tolerance_value else "not_converged",
        metric="|force|",
        residual=residual_value,
        tolerance=tolerance_value,
        iterations=float(total_iterations),
        solver_status="finished",
        source=log_file.name,
    )


def _spec_quality(case: str, implementation_dir: Path) -> dict[str, object] | None:
    files = sorted(implementation_dir.glob("*.sp.h5"))
    if not files:
        return None
    try:
        import h5py  # type: ignore
    except ImportError:
        return None

    def scalar(handle, name: str) -> float | None:
        if name not in handle:
            return None
        values = np.asarray(handle[name][()], dtype=float).ravel()
        finite = values[np.isfinite(values)]
        return float(finite[0]) if finite.size else None

    try:
        with h5py.File(files[-1], "r") as handle:
            residual = scalar(handle, "output/ForceErr")
            tolerance = scalar(handle, "input/global/forcetol")
            if residual is None:
                return None
            iterations = float(handle["iterations"].shape[0]) if "iterations" in handle else None
            ratio = residual / tolerance if tolerance is not None and tolerance > 0.0 else None
            return _quality_row(
                case,
                "spec",
                status="converged" if ratio is None or ratio <= 1.0 else "not_converged",
                metric="ForceErr",
                residual=abs(residual),
                tolerance=tolerance,
                iterations=iterations,
                solver_status="finished",
                source=files[-1].name,
            )
    except (OSError, ValueError, KeyError):
        return None


def _spectre_quality(case: str, implementation_dir: Path) -> dict[str, object] | None:
    files = sorted(implementation_dir.glob("*_res.json"))
    if not files:
        return None
    try:
        data = json.loads(files[-1].read_text(errors="replace"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(data, dict) or data.get("success") is not True:
        return None
    optimality = data.get("optimality")
    if not isinstance(optimality, (int, float)) or not np.isfinite(optimality):
        return None
    nfev = data.get("nfev")
    return _quality_row(
        case,
        "spectre",
        status="converged",
        metric="least-squares optimality",
        residual=float(optimality),
        iterations=float(nfev) if isinstance(nfev, (int, float)) else None,
        solver_status=str(data.get("status", "")),
        source=files[-1].name,
    )


def _quality_for_output(case: str, implementation_dir: Path) -> dict[str, object]:
    implementation = implementation_dir.name
    quality = _wout_quality(case, implementation_dir)
    if quality is not None:
        return quality
    if implementation == "desc":
        quality = _desc_quality(case, implementation_dir)
    elif implementation == "gvec":
        quality = _gvec_quality(case, implementation_dir)
    elif implementation == "spec":
        quality = _spec_quality(case, implementation_dir)
    elif implementation == "spectre":
        quality = _spectre_quality(case, implementation_dir)
    if quality is not None:
        return quality
    source = ""
    for filename in ("gvec_result.json", "freegs_result.json", "chease_result.json"):
        if (implementation_dir / filename).is_file():
            source = filename
            break
    if implementation == "spectre" and list(implementation_dir.glob("*_res.json")):
        source = sorted(implementation_dir.glob("*_res.json"))[-1].name
    if implementation == "spec" and list(implementation_dir.glob("*.sp.h5")):
        source = sorted(implementation_dir.glob("*.sp.h5"))[-1].name
    return _quality_row(case, implementation, source=source)


def _quality_records(result_root: Path):
    for case_dir in sorted(p for p in result_root.iterdir() if p.is_dir()):
        case = case_dir.name.replace("__", "/")
        for implementation_dir in sorted(p for p in case_dir.iterdir() if p.is_dir()):
            if not _successful_output(implementation_dir):
                continue
            yield _quality_for_output(case, implementation_dir)


def plot_quality(result_root: Path, output_dir: Path) -> Path:
    """Plot native residual quality and binary convergence status."""
    records = list(_quality_records(result_root))
    if not records:
        raise SystemExit(f"No successful outputs found below {result_root}")
    with (output_dir / "quality.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=QUALITY_FIELDS)
        writer.writeheader()
        writer.writerows(records)

    ratio_records = [
        row for row in records
        if isinstance(row["residual_over_tolerance"], (int, float))
        and np.isfinite(row["residual_over_tolerance"])
        and row["residual_over_tolerance"] > 0.0
    ]
    status_records = [row for row in records if row["quality_status"] != "unavailable"]
    if not ratio_records and not status_records:
        raise SystemExit("Successful outputs contain no native quality diagnostics")

    codes = [
        code for code in IMPLEMENTATION_ORDER
        if any(row["implementation"] == code for row in records)
    ]
    markers = ("o", "s", "^", "D", "P", "X", "v", "<", ">", "*", "h", "8")
    colors = plt.get_cmap("cividis")(np.linspace(0.12, 0.88, max(1, len(codes))))
    offsets = np.linspace(-0.28, 0.28, max(1, len(codes)))

    all_cases = list(dict.fromkeys(str(row["case"]) for row in records))
    tick_stride = max(1, len(all_cases) // 12)
    tick_positions = np.arange(0, len(all_cases), tick_stride)
    tick_labels = [_short_case_label(all_cases[index]) for index in tick_positions]
    figure, axes = plt.subplots(2, 1, figsize=(14, 8), sharex=True)
    if ratio_records:
        cases = all_cases
        positions = np.arange(len(cases))
        for index, code in enumerate(codes):
            x_values = []
            y_values = []
            for position, case in zip(positions, cases):
                matches = [
                    row for row in ratio_records
                    if row["implementation"] == code and row["case"] == case
                ]
                if matches:
                    x_values.append(position + offsets[index])
                    y_values.append(float(matches[-1]["residual_over_tolerance"]))
            if x_values:
                axes[0].scatter(
                    x_values,
                    y_values,
                    color=colors[index],
                    marker=markers[index % len(markers)],
                    s=28,
                    linewidths=0.35,
                    edgecolors="#222222",
                    label=_implementation_label(code),
                )
        axes[0].set_yscale("log")
        axes[0].axhline(1.0, color="#555555", linewidth=0.8, linestyle="--")
        axes[0].set_ylabel("reported residual / tolerance", fontsize=9)
        axes[0].set_xticks(tick_positions, tick_labels, rotation=90, fontsize=6)
        axes[0].set_title("Native residual quality (dimensionless ratio; 1 = tolerance)", loc="left", fontsize=10)
        axes[0].grid(axis="y", which="both", alpha=0.2)
    else:
        axes[0].text(0.5, 0.5, "No residual/tolerance pair was emitted", ha="center", va="center")
        axes[0].set_axis_off()

    if status_records:
        cases = all_cases
        positions = np.arange(len(cases))
        status_values = {"converged": 1.0, "not_converged": 0.0}
        for index, code in enumerate(codes):
            x_values = []
            y_values = []
            for position, case in zip(positions, cases):
                matches = [
                    row for row in status_records
                    if row["implementation"] == code and row["case"] == case
                ]
                if matches and matches[-1]["quality_status"] in status_values:
                    x_values.append(position + offsets[index])
                    y_values.append(status_values[matches[-1]["quality_status"]])
            if x_values:
                axes[1].scatter(
                    x_values,
                    y_values,
                    color=colors[index],
                    marker=markers[index % len(markers)],
                    s=28,
                    linewidths=0.35,
                    edgecolors="#222222",
                    label=_implementation_label(code),
                )
        axes[1].set_yticks((0.0, 1.0), ("not converged", "converged"))
        axes[1].set_ylim(-0.25, 1.25)
        axes[1].set_xticks(tick_positions, tick_labels, rotation=90, fontsize=6)
        axes[1].set_title("Native convergence status (blank = no diagnostic)", loc="left", fontsize=10)
        axes[1].grid(axis="y", alpha=0.2)
    else:
        axes[1].text(0.5, 0.5, "No native convergence status was emitted", ha="center", va="center")
        axes[1].set_axis_off()

    handles = []
    labels = []
    for axis in axes:
        axis_handles, axis_labels = axis.get_legend_handles_labels()
        for handle, label in zip(axis_handles, axis_labels):
            if label not in labels:
                handles.append(handle)
                labels.append(label)
    if handles:
        figure.legend(handles, labels, loc="upper center", bbox_to_anchor=(0.5, 0.98),
                      ncol=min(6, len(handles)), frameon=False, fontsize=8)
    figure.text(
        0.01,
        0.01,
        "Residual definitions and units are code-native; compare ratios only where the same diagnostic is reported. "
        "FreeGS, CHEASE, and one output without a diagnostic remain explicit gaps.",
        fontsize=7,
        color="#555555",
    )
    figure.subplots_adjust(left=0.08, right=0.99, bottom=0.30, top=0.87, hspace=0.45)
    filename = output_dir / "quality.png"
    figure.savefig(filename, dpi=180)
    plt.close(figure)
    return filename


def _runtime_records(result_root: Path):
    """Yield ``(case, implementation, seconds, source)`` from native logs.

    Timing formats differ between codes.  Keep the patterns explicit so a
    progress counter or timestamp cannot accidentally be presented as runtime.
    """
    for case_dir in sorted(p for p in result_root.iterdir() if p.is_dir()):
        for implementation_dir in sorted(p for p in case_dir.iterdir() if p.is_dir()):
            pattern_info = _RUNTIME_PATTERNS.get(implementation_dir.name)
            if pattern_info is None:
                continue
            if not _successful_output(implementation_dir):
                continue
            log_name, pattern, source = pattern_info
            log_file = implementation_dir / log_name
            if not log_file.is_file():
                continue
            text = log_file.read_text(errors="replace")
            matches = pattern.findall(text)
            if not matches:
                matches = re.findall(
                    r"^real\s+([0-9]+(?:\.[0-9]*)?(?:[Ee][+-]?[0-9]+)?)\s*$",
                    text,
                    re.I | re.M,
                )
            if not matches:
                continue
            seconds = _runtime_seconds(implementation_dir.name, matches[-1])
            if np.isfinite(seconds) and seconds > 0.0:
                yield case_dir.name.replace("__", "/"), implementation_dir.name, seconds, source


def plot_runtime(result_root: Path, output_dir: Path) -> Path:
    """Plot one native, code-reported runtime marker per code and case."""
    records = list(_runtime_records(result_root))
    if not records:
        raise SystemExit(f"No recognized solver timing lines found below {result_root}")

    csv_filename = output_dir / "runtime.csv"
    with csv_filename.open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(("case", "implementation", "runtime_seconds", "timing_source"))
        writer.writerows(records)

    cases = list(dict.fromkeys(case for case, _, _, _ in records))
    reference_order = ("educational_vmec", "vmec2000", "vmex", "desc", "jvmec", "gvec")
    codes = []
    for code in (*reference_order, *sorted({implementation for _, implementation, _, _ in records})):
        if code not in codes and any(implementation == code for _, implementation, _, _ in records):
            codes.append(code)
    markers = ("o", "s", "^", "D", "P", "X", "v", "<", ">", "*", "h")
    colors = plt.get_cmap("cividis")(np.linspace(0.12, 0.88, max(1, len(codes))))
    offsets = np.linspace(-0.28, 0.28, max(1, len(codes)))
    values = {(case, implementation): seconds for case, implementation, seconds, _ in records}

    figure, axis = plt.subplots(figsize=(13, 5.5))
    positions = np.arange(len(cases))
    for code_index, code in enumerate(codes):
        x_values = []
        y_values = []
        for position, case in zip(positions, cases):
            seconds = values.get((case, code))
            if seconds is not None:
                x_values.append(position + offsets[code_index])
                y_values.append(seconds)
        if x_values:
            axis.scatter(
                x_values,
                y_values,
                color=colors[code_index],
                marker=markers[code_index % len(markers)],
                s=34,
                linewidths=0.35,
                edgecolors="#222222",
                label=code,
            )
    axis.set_yscale("log")
    axis.set_ylabel("reported solver runtime (s)", fontsize=9)
    axis.set_xticks(positions, [_short_case_label(case) for case in cases], rotation=90, ha="center", fontsize=5)
    axis.tick_params(axis="y", labelsize=8)
    axis.grid(axis="y", which="both", alpha=0.2)
    axis.legend(loc="upper center", bbox_to_anchor=(0.5, 1.15), ncol=min(5, len(codes)), frameon=False, fontsize=8)
    axis.set_title("Native solver-reported runtime by case", fontsize=12, pad=34)
    figure.text(
        0.01,
        0.01,
        "Only recognized timing lines are shown; values are not end-to-end benchmark wall time.",
        fontsize=7,
        color="#555555",
    )
    figure.subplots_adjust(left=0.08, right=0.99, bottom=0.31, top=0.80)
    filename = output_dir / "runtime.png"
    figure.savefig(filename, dpi=180)
    plt.close(figure)
    return filename


def plot_surfaces(result_root: Path, output_dir: Path) -> list[Path]:
    cases = list(_case_outputs(result_root))
    columns = 2
    page_size = 24
    filenames: list[Path] = []
    for page_start in range(0, len(cases), page_size):
        page_cases = cases[page_start : page_start + page_size]
        rows = max(1, (len(page_cases) + columns - 1) // columns)
        figure, axes = plt.subplots(rows, columns, squeeze=False, figsize=(12, 5 * rows))
        for axis, (case_dir, outputs) in zip(axes.flat, page_cases):
            for implementation, filename in outputs:
                try:
                    with Dataset(filename) as dataset:
                        curve = _surface(dataset)
                except OSError:
                    curve = None
                if curve is not None:
                    axis.plot(curve[0], curve[1], linewidth=1.5, label=implementation)
            title = textwrap.fill(case_dir.name.replace("__", "/"), width=34)
            axis.set_title(title, fontsize=8, pad=4)
            axis.set_aspect("equal", adjustable="datalim")
            axis.set_xlabel("R")
            axis.set_ylabel("Z")
            axis.grid(alpha=0.2)
            axis.legend(fontsize="small", loc="best")
        for axis in axes.flat[len(page_cases) :]:
            axis.set_visible(False)
        page_number = page_start // page_size + 1
        figure.suptitle(
            f"Completed benchmark WOUT boundaries (phi = 0), "
            f"cases {page_start + 1}–{page_start + len(page_cases)} of {len(cases)}"
        )
        figure.tight_layout(rect=(0, 0, 1, 0.97))
        filename = output_dir / ("surfaces.png" if page_number == 1 else f"surfaces-{page_number:02d}.png")
        figure.savefig(filename, dpi=180)
        plt.close(figure)
        filenames.append(filename)
    return filenames


def plot_metrics(result_root: Path, output_dir: Path) -> Path:
    metrics = ("volume_p", "aspect", "raxis_cc")
    records: dict[str, dict[str, dict[str, float]]] = {}
    for case_dir in sorted(p for p in result_root.iterdir() if p.is_dir()):
        case_records = records.setdefault(case_dir.name.replace("__", "/"), {})
        for implementation, values in _case_metric_outputs(case_dir, metrics):
            case_records[implementation] = values
        if not case_records:
            records.pop(case_dir.name.replace("__", "/"), None)

    cases = list(records)
    reference_order = ("educational_vmec", "vmec2000", "vmex", "desc")
    codes = []
    for code in (*reference_order, *sorted({name for data in records.values() for name in data})):
        if code not in codes and any(code in data for data in records.values()):
            codes.append(code)
    markers = ("o", "s", "^", "D", "P", "X", "v", "<", ">", "*", "h")
    colors = plt.get_cmap("cividis")(np.linspace(0.12, 0.88, max(1, len(codes))))
    offsets = np.linspace(-0.28, 0.28, max(1, len(codes)))
    figure, axes = plt.subplots(len(metrics), 1, figsize=(14, 8), sharex=True, squeeze=False)
    positions = np.arange(len(cases))
    labels = [_short_case_label(case) for case in cases]
    for axis, metric in zip(axes[:, 0], metrics):
        for code_index, code in enumerate(codes):
            x_values = []
            y_values = []
            for position, case in zip(positions, cases):
                data = records[case]
                reference_item = next(
                    (
                        (name, data[name][metric])
                        for name in reference_order
                        if name in data and metric in data[name]
                    ),
                    None,
                )
                if reference_item is None:
                    continue
                _, reference = reference_item
                if code not in data or metric not in data[code] or reference == 0.0:
                    continue
                x_values.append(position + offsets[code_index])
                y_values.append(100.0 * (data[code][metric] - reference) / abs(reference))
            if x_values:
                axis.scatter(
                    x_values,
                    y_values,
                    color=colors[code_index],
                    marker=markers[code_index % len(markers)],
                    s=28,
                    linewidths=0.35,
                    edgecolors="#222222",
                    label=code,
                )
        axis.axhline(0.0, color="#555555", linewidth=0.8)
        axis.set_title(metric, loc="left", fontsize=10)
        axis.set_ylabel("relative difference (%)", fontsize=9)
        axis.grid(axis="y", alpha=0.2)
        axis.tick_params(axis="y", labelsize=8)
    axes[-1, 0].set_xticks(positions, labels, rotation=90, ha="center", fontsize=5)
    handles, labels_for_legend = axes[0, 0].get_legend_handles_labels()
    figure.legend(
        handles,
        labels_for_legend,
        loc="upper center",
        bbox_to_anchor=(0.5, 0.94),
        ncol=min(4, max(1, len(handles))),
        frameon=False,
        fontsize=8,
    )
    figure.suptitle("Relative scalar difference by code", fontsize=13, y=0.985)
    figure.subplots_adjust(left=0.08, right=0.99, bottom=0.33, top=0.87, hspace=0.35)
    filename = output_dir / "metrics.png"
    figure.savefig(filename, dpi=180)
    plt.close(figure)
    return filename


def _metric_records(result_root: Path):
    """Yield emitted scalar values without treating missing fields as zero."""
    for case_dir in sorted(p for p in result_root.iterdir() if p.is_dir()):
        case = case_dir.name.replace("__", "/")
        for implementation, values in _case_metric_outputs(case_dir, SCALAR_METRICS):
            for metric, value in values.items():
                if metric in SCALAR_METRICS and np.isfinite(value):
                    yield case, implementation, metric, float(value)


def _boxplot_scale(values: list[float], metric: str) -> str:
    if not values:
        return "linear"
    minimum = min(values)
    maximum = max(values)
    if minimum <= 0.0:
        return "symlog"
    if metric == "runtime_seconds" or maximum / minimum > 1.0e3:
        return "log"
    return "linear"


def plot_boxplots(result_root: Path, output_dir: Path) -> Path:
    """Plot side-by-side solver distributions for every emitted scalar and runtime."""
    records = list(_metric_records(result_root))
    runtime = list(_runtime_records(result_root))
    if not records and not runtime:
        raise SystemExit(f"No scalar or runtime values found below {result_root}")

    box_rows = [
        (case, implementation, metric, value)
        for case, implementation, metric, value in records
    ]
    box_rows.extend(
        (case, implementation, "runtime_seconds", seconds)
        for case, implementation, seconds, _ in runtime
    )
    with (output_dir / "boxplots.csv").open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(("case", "implementation", "metric", "value"))
        writer.writerows(box_rows)

    metrics = [*SCALAR_METRICS, "runtime_seconds"]
    figure, axes = plt.subplots(3, 3, figsize=(16, 13), squeeze=False)
    axes_flat = axes.flat
    codes = [
        code for code in IMPLEMENTATION_ORDER
        if any(implementation == code for _, implementation, _, _ in box_rows)
    ]
    colors = plt.get_cmap("cividis")(np.linspace(0.12, 0.88, max(1, len(codes))))
    values_by_metric: dict[str, dict[str, list[float]]] = {
        metric: {code: [] for code in codes} for metric in metrics
    }
    for _, implementation, metric, value in box_rows:
        if implementation in values_by_metric.get(metric, {}):
            values_by_metric[metric][implementation].append(value)

    for axis, metric in zip(axes_flat, metrics):
        data = values_by_metric[metric]
        nonempty = [code for code in codes if data[code]]
        positions = [codes.index(code) + 1 for code in nonempty]
        if nonempty:
            box = axis.boxplot(
                [data[code] for code in nonempty],
                positions=positions,
                widths=0.62,
                patch_artist=True,
                showfliers=True,
                whis=1.5,
                flierprops={"marker": ".", "markersize": 2.2, "alpha": 0.35, "markeredgewidth": 0},
                medianprops={"color": "#222222", "linewidth": 1.1},
                whiskerprops={"color": "#444444", "linewidth": 0.8},
                capprops={"color": "#444444", "linewidth": 0.8},
            )
            for patch, code in zip(box["boxes"], nonempty):
                patch.set_facecolor(colors[codes.index(code)])
                patch.set_alpha(0.78)
                patch.set_edgecolor("#222222")
        axis.set_title(METRIC_LABELS[metric], loc="left", fontsize=10)
        axis.set_xticks(range(1, len(codes) + 1), [
            f"{_implementation_label(code)}\n(n={len(data[code])})" for code in codes
        ], rotation=60, ha="right", fontsize=6)
        all_values = [value for values in data.values() for value in values]
        scale = _boxplot_scale(all_values, metric)
        if scale == "log":
            axis.set_yscale("log")
        elif scale == "symlog":
            positive = [abs(value) for value in all_values if value != 0.0]
            linthresh = max(min(positive) if positive else 1.0, 1.0e-12)
            axis.set_yscale("symlog", linthresh=linthresh)
        axis.grid(axis="y", which="both", alpha=0.2)
        axis.tick_params(axis="y", labelsize=8)
        if not nonempty:
            axis.text(0.5, 0.5, "no emitted values", ha="center", va="center", transform=axis.transAxes)

    for axis in list(axes_flat)[len(metrics):]:
        axis.set_visible(False)
    handles = [
        plt.Line2D([0], [0], marker="s", color="none", markerfacecolor=colors[index],
                   markeredgecolor="#222222", markersize=7, label=_implementation_label(code))
        for index, code in enumerate(codes)
    ]
    if handles:
        figure.legend(handles=handles, loc="upper center", bbox_to_anchor=(0.5, 0.975),
                      ncol=min(6, len(handles)), frameon=False, fontsize=8)
    figure.suptitle("Successful-output distributions by implementation", fontsize=13, y=0.995)
    figure.text(
        0.01,
        0.01,
        "Boxes: median and IQR; whiskers: 1.5×IQR; points: fliers. Values are native, unnormalised outputs. "
        "Only emitted values from successful outputs are included; n is shown per box.",
        fontsize=7,
        color="#555555",
    )
    figure.subplots_adjust(left=0.06, right=0.995, bottom=0.18, top=0.88, wspace=0.18, hspace=0.55)
    filename = output_dir / "boxplots.png"
    figure.savefig(filename, dpi=180)
    plt.close(figure)
    return filename


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result_dir", type=Path)
    parser.add_argument("--output-dir", type=Path)
    args = parser.parse_args()
    result_root = args.result_dir.expanduser().resolve()
    output_dir = (args.output_dir or result_root / "plots").expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    if not any(_case_outputs(result_root)):
        raise SystemExit(f"No completed WOUT NetCDF files found below {result_root}")
    for filename in plot_surfaces(result_root, output_dir):
        print(filename)
    print(plot_metrics(result_root, output_dir))
    print(plot_runtime(result_root, output_dir))
    print(plot_quality(result_root, output_dir))
    print(plot_boxplots(result_root, output_dir))


if __name__ == "__main__":
    main()
