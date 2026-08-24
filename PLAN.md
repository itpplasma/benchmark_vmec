# Benchmark continuation plan

This checkout is the ordinary, non-differentiable equilibrium benchmark. Keep
the analytical and numerical 1-D, 2-D, and 3-D cases, the VMEC-like matrix,
common-format adapters, and explicit failed/unsupported rows. FreeGS is the
2-D Grad--Shafranov comparison; CHEASE is included as a second 2-D code. The
differentiable MHD lane is intentionally not part of this repository.

## Current state (2026-08-24)

- `main` is pushed through commit `cc1f7ed`.
- Local verification passed: `fo check`, `fo test --all`, and `git diff --check`.
- Slurm smoke `1788012` completed with exit 0 in 3:11. It discovered 10
  implementations and ran the Solovev 2-D case. Educational VMEC, VMEC2000,
  VMEX, DESC, and FreeGS completed; VMEC++, GVEC, SPEC, SPECTRE, and CHEASE
  recorded case-level incompatibility/no-output rows. jVMEC and PARVMEC were
  reported unavailable without aborting the benchmark.
- Full Slurm job `1788019` is running on `sCluster` with 1 node, 48 CPUs, 96 GB,
  a 7-day limit, and 281 discovered cases. Its output is under
  `/home/ert/benchmark_vmec-slurm-233aa21/benchmark_vmec/benchmark_results-slurm-1788019/`;
  the live files are `slurm-vmec-benchmark-1788019.out` and `.err`.
- The full run has entered `numerical/1d_profile/profile_1d` after completing
  the first two cases; VMEC2000 completed all observed cases and the job is
  progressing. FortFront `fo check` emits known parser noise on the
  cluster gfortran and the launcher falls back to direct `fpm`; this has not
  caused a job failure.

## Cluster staging

The reproducible checkout is `/home/ert/benchmark_vmec-slurm-233aa21/benchmark_vmec`
with sibling repositories in `/home/ert/benchmark_vmec-slurm-233aa21/`. The
staged user-local runtime uses `~/.local/bin/uv`, `~/.local/bin/fpm`, OpenBLAS,
NetCDF-Fortran, and ScaLAPACK under `~/.local/`. VMEC2000 additionally has a
user-local `.venv` with its compiled extension and `mpi4py`; CHEASE is exposed
at `CHEASE/chease` from its native `src-f90/chease` executable. jVMEC remains
blocked by the absence of Java/Maven, and PARVMEC remains blocked by its
external `libstell` modules/library.

## Monitoring and hand-off

Use these commands from any host with the `scluster` SSH alias:

```bash
ssh scluster 'squeue -j 1788019'
ssh scluster 'sacct -j 1788019 --format=JobID,State,Elapsed,ExitCode'
ssh scluster 'tail -f /home/ert/benchmark_vmec-slurm-233aa21/benchmark_vmec/slurm-vmec-benchmark-1788019.out'
```

When the job reaches `COMPLETED`, inspect `comparison_report.md` and the CSV
files in its result directory. Retry only rows whose logs show an environment
or adapter defect; leave genuine code/input incompatibilities explicitly
reported. Pull `origin/main` before any follow-up change, run the local checks,
and update this file with the final Slurm state and report path.
