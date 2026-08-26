# Benchmark handoff

## Scope

This is the ordinary, non-differentiable equilibrium benchmark. The corpus has
345 analytical and numerical 1-D, 2-D, and 3-D cases and twelve implementations:
`educational_vmec`, `jVMEC`, `VMEC2000`, `VMEC++`, `VMEX`, `PARVMEC`,
`DESC`, `GVEC`, `SPEC`, `SPECTRE`, `FreeGS`, and `CHEASE`. FreeGS
and CHEASE are restricted to their supported 2-D Grad--Shafranov/GEQDSK inputs.
Common-format adapters live in `tools/`. Native output is retained whenever a
code provides it.

## Repository state

- `main` is clean and pushed at `9d5ad5d` (`Track corrected benchmark
  reruns`).
- Local gates pass: `uv run fo check`, `uv run fo test --all`, Python `ruff`,
  shell syntax checks, and `git diff --check`.
- The latest input adapters strip legacy separators/comments, normalize DESC
  and educational-VMEC controls, stage MGRID fixtures, and write explicit
  `benchmark_unsupported.txt` markers for missing fixtures, malformed VMEC
  namelists, and unsupported GVEC profiles. These markers classify unsupported
  cases. Generic infrastructure failures remain separate.
- Slurm lanes archive the exact checkout commit into a per-job temporary
  source/build tree (`BENCHMARK_ISOLATE_BUILD`, enabled by default), so
  parallel Fo invocations cannot share generated modules.
- Fo fix PR [#128](https://github.com/lazy-fortran/fo/pull/128) is pushed and
  green. Patched Fo `a024790` is installed on `scluster`.

## Slurm runs

- Protected legacy exhaustive job `1791254` is still running on `node20` from
  `/home/ert/benchmark_vmec-slurm-233aa21/benchmark_vmec-final`. It is useful
  for progress comparison, but its checkout predates the final adapter markers.
  Do not cancel it or use its failures as final classifications. At
  2026-08-26 11:41 CEST: 1,995 starts, 1,184 done, 781 failures, and zero child
  `MPI_ABORT`s. Progress:
  `/home/ert/benchmark_vmec-slurm-233aa21/benchmark-progress-1791254.log`.
- Old pre-fix clean64 and legacy repair jobs were canceled after their partial
  trees were retained. GVEC audit `1895960` is also canceled and is not final
  evidence.
- Authoritative replacements were submitted from the latest checkout
  `/home/ert/benchmark_vmec-slurm-233aa21/benchmark_vmec-latest-e887277`
  (verify it is `2615761`). Node-pinned isolated replacements are running or
  queued: `1896104` educational (STELLOPT subset), `1896105` DESC (Free
  Boundary subset), `1896106` GVEC (STELLOPT subset), `1896103` VMEC++ (bean,
  complete), and full lanes `1896113` jVMEC, `1896114` VMEC2000, `1896115`
  VMEX, `1896116` SPECTRE, and `1896117` PARVMEC. They use 600-second
  implementation timeouts. Targeted lanes use 2--6 hour allocations and full
  lanes use one day. Check `squeue`, `sacct`, and each `comparison_table.csv`
  before promotion.
- Completed authoritative side runs: SPEC `1895954` (10/10 native cases),
  FreeGS `1895836` (2-D cases only), and CHEASE `1895837` (2-D case only).
  Earlier VMEC2000/PARVMEC/VMEC++/educational counts are diagnostics from
  pre-fix checkouts, not final pass rates.

## Finish

1. Wait for jobs `1896104`--`1896111`; rerun only reproducible adapter or
   infrastructure defects. Keep solver timeouts and code limitations as
   genuine failures/unsupported rows.
2. Confirm no final logs contain fallback builds, `fo check` failures,
   missing commands, segmentation faults, or MPI aborts. Generate and inspect
   scalar-relative-difference, surface, and runtime plots with:

   ```bash
   uv run --with netCDF4 --with matplotlib python tools/plot_benchmark_results.py \
     <combined-result-root> --output-dir <combined-result-root>/plots
   ```

3. Update this file with terminal counts and plot paths, rerun all local gates,
   then stage explicit paths, commit, and `git push origin main`.
