# Benchmark continuation plan

This checkout is the ordinary, non-differentiable equilibrium benchmark. Keep
the analytical and numerical 1-D, 2-D, and 3-D cases, the VMEC-like matrix,
common-format adapters, and explicit failed/unsupported rows. FreeGS is the
2-D Grad--Shafranov comparison; CHEASE is included as a second 2-D code. The
differentiable MHD lane is intentionally not part of this repository.

## Current state (2026-08-24)

- `main` is pushed through commit `4801c88`.
- Local verification passed: `fo check`, `fo test --all`, and `git diff --check`.
- Slurm smoke `1788053` completed with exit 0 in 3:17. It discovered 11
  implementations and jVMEC completed the Solovev 2-D case. VMEC++, GVEC,
  SPEC, SPECTRE, and CHEASE still recorded case-level incompatibility/no-output
  rows; PARVMEC remained unavailable without aborting the benchmark.
- The pre-Java full job `1788019` was cancelled after 13:56 because jVMEC cannot
  be added after implementation setup. Replacement full job `1788058` is
  running on `sCluster` with 1 node, 48 CPUs, 96 GB, a 7-day limit, and 281
  discovered cases. Its output is under
  `/home/ert/benchmark_vmec-slurm-233aa21/benchmark_vmec/benchmark_results-slurm-1788058/`;
  the live files are `slurm-vmec-benchmark-1788058.out` and `.err`.
- At the latest check, replacement job `1788058` had started 4/281 cases,
  completed the first three, and was running VMEC2000 on
  `analytic/3d_quasisymmetric/qh_analytic`; jVMEC had completed all four
  observed cases. FortFront `fo check` emits known parser noise on the
  cluster gfortran and the launcher falls back to direct `fpm`; this has not
  caused a job failure.

## Cluster staging

The reproducible checkout is `/home/ert/benchmark_vmec-slurm-233aa21/benchmark_vmec`
with sibling repositories in `/home/ert/benchmark_vmec-slurm-233aa21/`. The
staged user-local runtime uses `~/.local/bin/uv`, `~/.local/bin/fpm`, OpenBLAS,
NetCDF-Fortran, and ScaLAPACK under `~/.local/`. Java is Temurin 17 under
`~/.local/jdk-temurin-17`, Maven 3.9.16 is under
`~/.local/apache-maven-3.9.16`, and jVMEC is built in
`jVMEC/target/`. VMEC2000 additionally has a user-local `.venv` with its
compiled extension and `mpi4py`; CHEASE is exposed at `CHEASE/chease` from its
native `src-f90/chease` executable. PARVMEC remains blocked by its external
`libstell` modules/library.

## Monitoring and hand-off

Use these commands from any host with the `scluster` SSH alias:

```bash
ssh scluster 'squeue -j 1788058'
ssh scluster 'sacct -j 1788058 --format=JobID,State,Elapsed,ExitCode'
ssh scluster 'tail -f /home/ert/benchmark_vmec-slurm-233aa21/benchmark_vmec/slurm-vmec-benchmark-1788058.out'
```

When the job reaches `COMPLETED`, inspect `comparison_report.md` and the CSV
files in its result directory. Retry only rows whose logs show an environment
or adapter defect; leave genuine code/input incompatibilities explicitly
reported. Pull `origin/main` before any follow-up change, run the local checks,
and update this file with the final Slurm state and report path.
