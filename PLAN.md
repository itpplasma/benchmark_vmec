# Benchmark handoff

## Scope

This is the ordinary, non-differentiable equilibrium benchmark. The corpus has
344 unique analytical and numerical 1-D, 2-D, and 3-D cases and twelve
implementations: `educational_vmec`, `jVMEC`, `VMEC2000`, `VMEC++`, `VMEX`,
`PARVMEC`, `DESC`, `GVEC`, `SPEC`, `SPECTRE`, `FreeGS`, and `CHEASE`.
FreeGS and CHEASE are restricted to supported 2-D Grad--Shafranov/GEQDSK
inputs. Common-format adapters live in `tools/`.

## Repository state

- `main` is clean and pushed at `a889f89`.
- Local gates pass: `uv run fo check`, `uv run fo test --all`, Python `ruff`,
  shell syntax checks, and `git diff --check`.
- The adapters normalize legacy VMEC inputs, strip inline comments, stage MGRID
  fixtures, and retain explicit unsupported markers. The GVEC runner uses a
  short job-local path before copying artifacts back, avoiding its fixed-length
  restart-path truncation.
- Every solver wrapper uses `timeout --kill-after=5s`, so a child that ignores
  the first timeout signal cannot hold an allocation indefinitely.
- `tools/run_slurm_case_array.sbatch` and
  `tools/submit_slurm_case_arrays.sh` provide reproducible bounded arrays.
  `tools/merge_benchmark_results.sh` merges per-task reports with later sources
  taking precedence.
- Fo fix PR [#128](https://github.com/lazy-fortran/fo/pull/128) is pushed and
  green. Patched Fo `a024790` is installed on `scluster`.

## Slurm status

- Protected legacy audit job `1791254` remains running on `node20`. It uses an
  older checkout and is not final evidence.
- Earlier serial and array attempts (`1897318`, `1897321`, `1897367`,
  `1897370`, `1907490`, `1908322`, and `1908329`) were canceled after their
  partial trees were retained for audit. Their old timeout behavior is not
  final evidence.
- Fixed-checkout exhaustive arrays `1908611` (VMEC-family participants) and
  `1908612` (the remaining six native and nested-surface participants) cover
  all 344 frozen cases. Per-task reports are under
  `/home/ert/benchmark_vmec-slurm-233aa21/benchmark_results-array-vmec-a889f89`
  and `/home/ert/benchmark_vmec-slurm-233aa21/benchmark_results-array-native-a889f89`.
- The frozen case list is
  `/home/ert/benchmark_vmec-slurm-233aa21/case-suffixes-1859d3a.txt`.
- Corrected `input.AXISYM` reruns succeeded for educational VMEC (`1897572`),
  VMEC++ (`1897588`), DESC (`1897589`), GVEC (`1897590`), jVMEC (`1897594`),
  VMEC2000 (`1897595`), VMEX (`1897596`), SPECTRE (`1897597`), and PARVMEC
  (`1897631`). SPEC, FreeGS, and CHEASE correctly report unsupported for that
  VMEC input. The long-path GVEC probe `1898244` succeeded.
- Superseded pending fallbacks `1896113`--`1896117` and earlier harness-only
  attempts were canceled. No current replacement log has a Fo/fpm build error,
  missing command, MPI abort, segmentation fault, or GVEC `STATEFILE` path
  error.

## Finish

1. Wait for arrays `1908611` and `1908612` to become terminal. Rerun only a
   task with a reproducible infrastructure defect. Keep solver failures,
   timeouts, and explicit code limitations as genuine result rows.
2. Merge in precedence order with `tools/merge_benchmark_results.sh`, putting
   corrected array outputs and targeted reruns after the serial roots. Audit
   that all 344 case slugs have the expected implementation rows.
3. Generate and inspect scalar-relative-difference, boundary-surface, and
   runtime plots with `tools/plot_benchmark_results.py`. Runtime points are
   native solver timings from successful outputs only.
4. Record terminal counts, final merge/plot paths, and the infrastructure audit
   in this file. Rerun local gates, stage explicit paths, commit, and push
   `origin/main`.
