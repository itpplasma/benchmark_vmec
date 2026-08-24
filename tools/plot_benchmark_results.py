#!/usr/bin/env python3
"""Plot completed benchmark WOUT outputs.

Usage::

    python tools/plot_benchmark_results.py benchmark_results-slurm-1788058

The input directory is a Slurm result directory.  The script only uses native
NetCDF WOUT files that are already present, so incomplete or unsupported rows
are skipped.  It writes ``surfaces.png`` (phi=0 boundary overlays) and
``metrics.png`` (relative differences from the reference) to the selected
output folder.
"""

from __future__ import annotations

import argparse
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
    for case_dir, outputs in _case_outputs(result_root):
        case_records = records.setdefault(case_dir.name.replace("__", "/"), {})
        for implementation, filename in outputs:
            with Dataset(filename) as dataset:
                values = {metric: _scalar(dataset, metric) for metric in metrics}
            if any(value is not None for value in values.values()):
                case_records[implementation] = {
                    key: value for key, value in values.items() if value is not None
                }

    cases = list(records)
    reference_order = ("educational_vmec", "vmec2000", "vmex", "desc")
    figure, axes = plt.subplots(len(metrics), 1, figsize=(14, 8), sharex=True, squeeze=False)
    positions = np.arange(len(cases))
    labels = [_short_case_label(case) for case in cases]
    for axis, metric in zip(axes[:, 0], metrics):
        lower_errors = []
        upper_errors = []
        valid_positions = []
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
            reference_name, reference = reference_item
            relative_values = [
                100.0 * (values[metric] - reference) / abs(reference)
                for name, values in data.items()
                if name != reference_name and metric in values and reference != 0.0
            ]
            all_values = [0.0, *relative_values]
            valid_positions.append(position)
            lower_errors.append(-min(all_values))
            upper_errors.append(max(all_values))
        if valid_positions:
            axis.errorbar(
                valid_positions,
                np.zeros(len(valid_positions)),
                yerr=[lower_errors, upper_errors],
                fmt="o",
                color="#111111",
                ecolor="#3b528b",
                markersize=4,
                capsize=3,
                linewidth=1,
            )
        axis.axhline(0.0, color="#555555", linewidth=0.8)
        axis.set_ylabel("relative difference (%)", fontsize=9)
        axis.grid(axis="y", alpha=0.2)
        axis.tick_params(axis="y", labelsize=8)
    axes[-1, 0].set_xticks(positions, labels, rotation=35, ha="right", fontsize=7)
    figure.legend(
        [plt.Line2D([], [], color="#111111", marker="o", linestyle="none", markersize=4),
         plt.Line2D([], [], color="#3b528b", linewidth=1)],
        ["reference (0%)", "range of available codes"],
        loc="upper center",
        bbox_to_anchor=(0.5, 0.94),
        ncol=2,
        frameon=False,
        fontsize=8,
    )
    figure.suptitle("Relative scalar difference from reference", fontsize=13, y=0.985)
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


if __name__ == "__main__":
    main()
