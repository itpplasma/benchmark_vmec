#!/usr/bin/env python3
"""Plot completed benchmark WOUT outputs and reported runtimes.

Usage::

    python tools/plot_benchmark_results.py benchmark_results-slurm-1788058

The input directory is a Slurm result directory.  Native NetCDF WOUT files
are used for the surfaces and scalar plots, so incomplete or unsupported rows
are skipped.  Solver-reported timing lines are used for ``runtime.png`` and
``runtime.csv``; codes without a machine-readable timing line are omitted from
that figure rather than silently mixing in a different measurement.  All
outputs are written to the selected output folder.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from netCDF4 import Dataset


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
    height = np.sum(
        zmnc[row, :, None, None] * np.cos(phase)
        + zmns[row, :, None, None] * np.sin(phase),
        axis=0,
    )
    height_theta = np.sum(
        -zmnc[row, :, None, None] * xm[:, None, None] * np.sin(phase)
        + zmns[row, :, None, None] * xm[:, None, None] * np.cos(phase),
        axis=0,
    )
    rmax = float(np.nanmax(radius))
    rmin = float(np.nanmin(radius))
    rmajor = 0.5 * (rmax + rmin)
    aminor = 0.5 * (rmax - rmin)
    volume = abs(0.5 * float(np.nanmean(radius**2 * height_theta)) * (2.0 * np.pi) ** 2)
    return {
        "raxis_cc": float(rmnc[0, mode00]),
        "aspect": rmajor / aminor if aminor > 0.0 else np.nan,
        "volume_p": volume,
    }


def _metric_values(dataset: Dataset, metrics: tuple[str, ...]) -> dict[str, float]:
    values = {metric: _scalar(dataset, metric) for metric in metrics}
    derived = _derived_scalars(dataset)
    return {
        metric: values[metric] if values[metric] is not None else derived.get(metric)
        for metric in metrics
        if values[metric] is not None or metric in derived
    }


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


def _case_metric_outputs(case_dir: Path, metrics: tuple[str, ...]):
    """Yield implementation/metric pairs from WOUTs and common sidecars."""
    for implementation_dir in sorted(p for p in case_dir.iterdir() if p.is_dir()):
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
    "vmec2000": (
        "vmec2000.log",
        re.compile(r"TOTAL COMPUTATIONAL TIME \(SEC\)\s*([0-9]+(?:\.[0-9]*)?(?:[Ee][+-]?[0-9]+)?)", re.I),
        "total computational time (s)",
    ),
    "gvec": (
        "gvec.log",
        re.compile(r"GVEC finished after\s*([0-9]+(?:\.[0-9]*)?(?:[Ee][+-]?[0-9]+)?)\s*seconds", re.I),
        "GVEC finished after (s)",
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
    if implementation == "spectre":
        hours, minutes, seconds = match
        return 3600.0 * float(hours) + 60.0 * float(minutes) + float(seconds)
    return float(match)


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
            log_name, pattern, source = pattern_info
            log_file = implementation_dir / log_name
            if not log_file.is_file():
                continue
            matches = pattern.findall(log_file.read_text(errors="replace"))
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
    axis.set_xticks(positions, [_short_case_label(case) for case in cases], rotation=35, ha="right", fontsize=7)
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
    figure.subplots_adjust(left=0.08, right=0.99, bottom=0.28, top=0.80)
    filename = output_dir / "runtime.png"
    figure.savefig(filename, dpi=180)
    plt.close(figure)
    return filename


def plot_surfaces(result_root: Path, output_dir: Path) -> Path:
    cases = list(_case_outputs(result_root))
    columns = 2
    rows = max(1, (len(cases) + columns - 1) // columns)
    figure, axes = plt.subplots(rows, columns, squeeze=False, figsize=(12, 5 * rows))
    for axis, (case_dir, outputs) in zip(axes.flat, cases):
        for implementation, filename in outputs:
            try:
                with Dataset(filename) as dataset:
                    curve = _surface(dataset)
            except OSError:
                curve = None
            if curve is not None:
                axis.plot(curve[0], curve[1], linewidth=1.5, label=implementation)
        axis.set_title(case_dir.name.replace("__", "/"))
        axis.set_aspect("equal", adjustable="datalim")
        axis.set_xlabel("R")
        axis.set_ylabel("Z")
        axis.grid(alpha=0.2)
        axis.legend(fontsize="small", loc="best")
    for axis in axes.flat[len(cases) :]:
        axis.set_visible(False)
    figure.suptitle("Completed benchmark WOUT boundaries (phi = 0)")
    figure.tight_layout()
    filename = output_dir / "surfaces.png"
    figure.savefig(filename, dpi=180)
    plt.close(figure)
    return filename


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
    axes[-1, 0].set_xticks(positions, labels, rotation=35, ha="right", fontsize=7)
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
    figure.subplots_adjust(left=0.08, right=0.99, bottom=0.30, top=0.87, hspace=0.35)
    filename = output_dir / "metrics.png"
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
    print(plot_surfaces(result_root, output_dir))
    print(plot_metrics(result_root, output_dir))
    print(plot_runtime(result_root, output_dir))


if __name__ == "__main__":
    main()
