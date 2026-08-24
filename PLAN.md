# Benchmark continuation plan

This is the ordinary, non-differentiable equilibrium benchmark. The canonical
corpus contains analytical and numerical 1-D, 2-D, and 3-D cases; FreeGS and
CHEASE are the 2-D Grad--Shafranov comparisons. The differentiable-MHD lane is
outside this repository.

## Current status (2026-08-24)

- `main` is pushed through `b6bc561`. Local `fo`, `fo test test_runner_reporting`,
  and `git diff --check` pass. The full pipeline reports only the existing
  array-temporary warning in `app/main.f90`.
  `git diff --check` pass.
- jVMEC’s private fork is pushed through `c75fb72e`. Its NetCDF writer now
  emits the complete WOUT schema and derives `aspect`, `volume_p`,
  `Rmajor_p`, and `Aminor_p` from the LCFS Fourier surface when the legacy
  diagnostic stages are disabled. Maven builds the jar on the cluster.
- The cluster has current `fo` `2e956e2` and FortFront `59fc28e` installed in
  `~/.local/bin`; the previous `fo` binary is retained as
  `~/.local/bin/fo-pre-fix-0.3.2`. With the launcher’s NetCDF/HDF5 runtime
  paths, `fo check` and all five tests pass remotely.
- The staged VMEC++ checkout also now has a non-editable `uv` installation
  with valid package metadata and its `indata2json` converter; a direct
  Solovev post-install run produced `wout_input.nc` successfully. Early rows
  of job `1790415` predate that repair and retain their explicit failures.
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
- A dedicated VMEC++ canonical rerun (`1790673`) completed all six cases after
  the repaired package metadata was installed. Its WOUT files were collected
  into the local canonical snapshot and the regenerated plots are under
  `benchmark_vmec_plots/1790415-runtime/`; `runtime.png` and `runtime.csv` now
  include VMEC++ with GNU `time` wall-clock values. The other native solver
  timings remain code-reported and are not an apples-to-apples end-to-end
  wall-clock benchmark.
- The exhaustive job's converted `from_DESC/NCSX` lane currently times out in
  educational_VMEC, jVMEC, VMEC2000, VMEC++, and VMEX at 300 s; DESC completes,
  while GVEC/SPEC/SPECTRE/CHEASE fail on their native input/solver contracts.
  Converted `from_DESC/W7X` has the same VMEC-family timeouts and an
  educational_VMEC `LFULL3D1OUT` input incompatibility. FreeGS is now guarded
  in the runner and is skipped outside path-qualified 2-D cases; job `1790415`
  was built before that guard and therefore still prints the old unsupported
  FreeGS attempts.
- The input-contract repair is implemented locally: SPEC is invoked only for
  native `.sp` files (a native SPEC smoke case completed without MPI_ABORT),
  SPECTRE VMEC inputs are converted to retained TOML through
  `tools/convert_vmec_to_spectre.py` and run through `tools/run_spectre.py`, and
  CHEASE is admitted only for 2-D `.geqdsk`/`.eqdsk` inputs. The VMEC boundary
  index order is transposed correctly in the SPECTRE bridge; a four-volume
  Solovev conversion and SPECTRE solve produced `spectre_input_res.json` on
  `scluster`. The educational-VMEC adapter now drops unsupported
  `LFULL3D1OUT`; a W7-X run reached VMEC iterations rather than failing
  namelist parsing. Canonical VMEC INDATA is intentionally not passed to
  CHEASE because its required EQDSK profile/boundary contract is not losslessly
  reconstructible from that namelist.

## Handoff

Wait for `1790415` to finish, inspect `comparison_report.md` and the CSV
files, and regenerate plots with `tools/plot_benchmark_results.py`. Retry only
rows whose logs show an environment or adapter defect; retain genuine
implementation incompatibilities as explicit failed/unsupported rows. Keep
this file updated with the final Slurm state and plot paths.
