# Benchmark handoff

## Scope

This is the ordinary, non-differentiable equilibrium benchmark. The frozen
corpus contains 344 analytical and numerical 1-D, 2-D, and 3-D cases and
twelve implementations: `educational_vmec`, `jVMEC`, `VMEC2000`, `VMEC++`,
`VMEX`, `PARVMEC`, `DESC`, `GVEC`, `SPEC`, `SPECTRE`, `FreeGS`, and `CHEASE`.
FreeGS and CHEASE are restricted to their supported 2-D Grad--Shafranov
inputs. Adapters for common formats are in `tools/`.

## Reproducible result

- Historical case-list path: `/home/ert/benchmark_vmec-slurm-233aa21/case-suffixes-1859d3a.txt`; it is not present in the current checkout. The curated table retains the 344 case identifiers, not a complete source-pinned input manifest.
- VMEC-family array `1908611`: 516/516 tasks completed. Maximum task time
  00:33:12.
- Native array `1908612`: 516/516 tasks completed. Maximum task time
  01:00:57.
- Case-slug repair array `1933474`: 12/12 tasks completed. Maximum task time
  00:11:23. It repaired the distinct `jVMEC/Ns=2048.M=32` case that had
  collided with `jVMEC/Ns_2048.M_32` in older output directories. The
  high-resolution jVMEC run timed out at 588.55 s. This is retained as a true
  code result, not an infrastructure failure.
- Curated final evidence: `results/ordinary-0cf8e2c/`. The 4,128-row
  comparison table and final plots are retained here; regenerable per-run
  solver outputs and cluster build trees were removed on 2026-09-14.
  `comparison_table.csv` has exactly 4,128 unique rows (344 cases × 12
  implementations). The current committed archive retains scalar/quality CSVs
  and figures; native case directories, states and logs are not retained there.
- Status totals: 1,504 successes and 2,624 failures, of which 2,168 are
  explicit unsupported-scope rows. Remaining failures are solver failures or
  bounded timeouts. No task in the three arrays had a non-zero Slurm exit.
- Infrastructure audit of all array stdout/stderr found zero fpm build errors,
  missing commands/modules, MPI aborts, segmentation faults, or
  GVEC `STATEFILE` path errors.

## Plots and timings

The final plots are under `results/ordinary-0cf8e2c/plots/`:
`metrics.png` (relative scalar agreement, not quality), `quality.png` and
`quality.csv` (native residual/convergence diagnostics), `boxplots.png` and
`boxplots.csv` (one box-and-whisker panel per scalar and reported runtime),
`runtime.png` and `runtime.csv`, and paginated `surfaces*.png` boundary plots.
Runtime points are successful outputs only and are not end-to-end Slurm wall
times. Missing native diagnostics remain explicit gaps in `quality.csv`.
The quality export contains 1,504 successful outputs; 1,500 have a native
diagnostic and 1,203 expose a residual/tolerance ratio. FreeGS, CHEASE, and
one malformed educational-VMEC output are intentionally marked unavailable.

## Repository and gates

`main` is pushed and clean. The latest changes include collision-safe case
slugs, complete-array recovery, honest missing-value handling, native quality
and boxplot exports, nonfinite-output handling, compact plot labels, and
bounded child termination in solver wrappers. Local fpm build, tests, lint,
Python Ruff, shell syntax, and whitespace checks pass. The direct fpm pipeline
also passes (with only the repository's pre-existing formatter
warning in `benchmark_runner.f90`).

The protected legacy audit job `1791254` remains on `node20` using an old
checkout and is not evidence for the final table. The cluster is healthy
(`compute`: 20 nodes total, 19 usable, about 1,018 idle CPUs at handoff).

## Focused TC24 handoff

- Ordinary/all-variant wrapper authority stays here; the differentiable benchmark is complementary.
- Current matched cases and execution authority: [TC24 PLAN](https://gitlab.tugraz.at/plasma/proj/ntv/iter_tc24/-/blob/main/PLAN.md). Reuse exact source/input seals and physical fields from that campaign.
- Gate physical input matching before comparing outputs: the historical FreeGS wrapper ignores the supplied geometry/profiles, and its reported successes are operational probes.
- Record actual solver/package/binary revisions, original/generated inputs and adapter hashes for new runs. Moving sibling branches and the historical corpus identifier do not provide these pins.
- Preserve historical outcomes. Do not interpret status counts, native residuals or scalar agreement as independent physical-force validation. Existing [#1](https://github.com/itpplasma/benchmark_vmec/issues/1) owns the status/timing discussion.
- First follow-ups: honest FreeGS case admission; source/input provenance; export one admitted ordinary TC24 circular case. No full-corpus rerun or inverse-GS redesign is required for this handoff.
