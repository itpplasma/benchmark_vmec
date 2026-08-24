# Benchmark continuation plan

This is the ordinary, non-differentiable equilibrium benchmark. The canonical
corpus contains analytical and numerical 1-D, 2-D, and 3-D cases; FreeGS and
CHEASE are the 2-D Grad--Shafranov comparisons. The differentiable-MHD lane is
outside this repository.

## Current status (2026-08-24)

- `main` is pushed through `a03498d`. Local `fo check`, `fo test --all`, and
  `git diff --check` pass.
- jVMEC’s private fork is pushed through `c75fb72e`. Its NetCDF writer now
  emits the complete WOUT schema and derives `aspect`, `volume_p`,
  `Rmajor_p`, and `Aminor_p` from the LCFS Fourier surface when the legacy
  diagnostic stages are disabled. Maven builds the jar on the cluster.
- The cluster has current `fo` `2e956e2` and FortFront `59fc28e` installed in
  `~/.local/bin`; the previous `fo` binary is retained as
  `~/.local/bin/fo-pre-fix-0.3.2`. With the launcher’s NetCDF/HDF5 runtime
  paths, `fo check` and all five tests pass remotely.
- Corrected smoke job `1790311` completed successfully. jVMEC reports
  `aspect=3.628662` and `volume_p=94.156026` for analytic 2-D Solovev, and
  the Fourier coefficients match the educational_VMEC reference. The smoke
  report is under
  `/home/ert/benchmark_vmec-slurm-233aa21/benchmark_vmec/benchmark_results-slurm-1790311/`.
- Exhaustive job `1790415` is running on `scluster` (1 node, 48 CPUs, 96 GB,
  7-day limit). It discovered 297 cases, including the six canonical cases;
  the first numerical 3-D W7-X case completed in educational_VMEC, jVMEC,
  VMEC2000, and VMEX, with jVMEC geometry scalars present. Monitor:

  ```bash
  ssh scluster 'squeue -j 1790415'
  ssh scluster 'sacct -j 1790415 --format=JobID,State,Elapsed,ExitCode'
  ssh scluster 'tail -f /home/ert/benchmark_vmec-slurm-233aa21/benchmark_vmec/slurm-vmec-benchmark-1790415.out'
  ```

  Results will be in
  `/home/ert/benchmark_vmec-slurm-233aa21/benchmark_vmec/benchmark_results-slurm-1790415/`.

## Handoff

Wait for `1790415` to finish, inspect `comparison_report.md` and the CSV
files, and regenerate plots with `tools/plot_benchmark_results.py`. Retry only
rows whose logs show an environment or adapter defect; retain genuine
implementation incompatibilities as explicit failed/unsupported rows. Keep
this file updated with the final Slurm state and plot paths.
