# Benchmark status and handoff

This repository is the ordinary, non-differentiable equilibrium benchmark.
It covers analytical and numerical 1-D, 2-D, and 3-D cases. FreeGS and CHEASE
are admitted only to the 2-D Grad--Shafranov lane; the differentiable-MHD
project is separate.

## Implemented

- `main` is pushed at `821d7d5`. `fo check`, the Fortran tests (5/5), Python
  byte-compilation, shell syntax checks, and `git diff --check` pass.
- VMEC-like lanes: educational_VMEC, jVMEC, VMEC2000, VMEC++, VMEX, DESC,
  and GVEC. The wider inventory also includes SPEC, SPECTRE, FreeGS, and
  CHEASE. PARVMEC is detected but not installed on the cluster; no expected
  VMEC-like code is missing.
- Bridges retain native outputs and provide common JSON/NetCDF/GEQDSK/SPEC/
  SPECTRE/GVEC sidecars where a code does not emit the common format.
- Input preparation removes unsupported diagnostic switches and legacy
  namelist terminators, stages relative MGRID files, and keeps prepared and
  cleaned files separate. FreeGS/CHEASE receive only their native 2-D inputs;
  SPEC receives only native `.sp` inputs.
- Upstream reviews are filed after auditing all fetched refs: jVMEC benchmark
  PR [#3](https://github.com/jonathanschilling/jVMEC/pull/3) now includes the
  local-MGRID registration fix, and GVEC MPCDF MR
  [!175](https://gitlab.mpcdf.mpg.de/gvec-group/gvec/-/merge_requests/175)
  fixes ragged sparse VMEC boundary conversion with a regression test.

## Active exhaustive run

Corrected full run `1791165` is running on `node20` with a 600-second
per-case timeout. It discovered 298 cases and writes to:

`/home/ert/benchmark_vmec-slurm-233aa21/benchmark_vmec-corrected/benchmark_results-slurm-1791165/`

Monitor it with:

```bash
ssh scluster 'squeue -j 1791165 -o "%.18i %.12T %.10M %.20R"'
ssh scluster 'sacct -j 1791165 --format=JobID,State,Elapsed,ExitCode'
ssh scluster 'tail -f /home/ert/benchmark_vmec-slurm-233aa21/benchmark_vmec-corrected/slurm-vmec-benchmark-final-1791165.out'
```

The older diagnostic run `1791036` is pre-fix history only and must not be
used for final plots. Focused corrected tokamak, W7-X, GVEC, and CHEASE smokes
already pass their format and dimensionality contracts; genuine solver
non-convergence or timeout rows remain explicit rather than being hidden.

## Finish checklist

1. Let `1791165` finish. If a new converter, staging, or MPI failure appears,
   fix it, run a focused smoke, and rerun the affected exhaustive job. Keep
   genuine solver failures as labelled rows.
2. Run `tools/plot_benchmark_results.py` on the final result directory with
   `uv run --with netCDF4 --with matplotlib`; inspect scalar, surface, and
   runtime plots and record their paths here.
3. Re-run the local gates, update this file with the final Slurm/plot evidence,
   commit explicit paths, and push `main`.
