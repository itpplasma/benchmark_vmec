# Results

`results/ordinary-0cf8e2c/` holds the archived run of all 344 cases with all
twelve implementations.

## Comparison table

`comparison_table.csv` has one row per case and implementation (4,128 rows).
Each row records the status (`success` or `failed`), an error message, the case
dimension and family, the input and output formats and the common scalar
outputs: `wb`, `betatotal`, `aspect`, `raxis_cc`, `volume_p`, `iotaf_edge`,
`pressure_axis` and `plasma_current`.

Of the 4,128 rows, 1,504 are successful. Of the 2,624 failures, 2,168 are
cases outside an implementation's scope (for example 3-D inputs for FreeGS or
CHEASE); the rest are solver failures or runs that hit the time limit.

The archive keeps the table and the plots, not the native output files or logs
of the individual runs, and no complete manifest of solver revisions and
inputs.

## Plots

`plots/` contains:

- `metrics.png`: relative agreement of the scalar outputs between codes
- `quality.png`, `quality.csv`: native residual and convergence diagnostics
- `boxplots.png`, `boxplots.csv`: one box-and-whisker panel per scalar and for
  runtime
- `runtime.png`, `runtime.csv`: runtimes reported by the codes
- `surfaces*.png`: boundary overlays

Box plots show median, interquartile range, whiskers at 1.5 times the
interquartile range and outliers, computed from successful outputs only.
Missing diagnostics are left blank. Runtimes are those reported by the codes,
not wall-clock times of the batch jobs. FreeGS, CHEASE and one malformed
educational VMEC output have no quality diagnostic.

## Interpretation

- Agreement of scalar outputs, a successful exit or a small native residual
  does not by itself show that two codes solved the same physical problem.
  Compare outputs only after checking that boundary, profiles, flux and
  conventions of the inputs match.
- `tools/run_freegs.py` chooses geometry and profiles from hard-coded presets
  selected by file name and does not read the supplied physical input. The
  FreeGS rows therefore show that the code runs, not that it matches the VMEC
  results.
- [Issue #1](https://github.com/itpplasma/benchmark_vmec/issues/1) discusses
  the distinction between status and timing in the table.

## Plotting new results

    uv run --with netCDF4 --with h5py --with matplotlib \
      python tools/plot_benchmark_results.py <results-directory>
