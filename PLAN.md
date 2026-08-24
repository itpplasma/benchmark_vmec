# Benchmark status and handoff

This is the ordinary, non-differentiable equilibrium benchmark. It covers
analytical and numerical 1-D, 2-D, and 3-D cases. FreeGS and CHEASE are
restricted to the 2-D Grad--Shafranov/GEQDSK lane; the differentiable-MHD
project is separate.

## Implemented

- `main` is pushed at `b8774a2`. The driver has explicit lanes for
  educational_VMEC, jVMEC, VMEC2000, VMEC++, VMEX, DESC, GVEC, PARVMEC, SPEC,
  SPECTRE, FreeGS, and CHEASE. PARVMEC is discovered but is not buildable in
  the current cluster environment.
- The corpus contains 298 discovered cases, including analytical and
  numerical 1-D/2-D/3-D fixtures and the educational_VMEC inventory. Native
  outputs are retained; common JSON/NetCDF/GEQDSK/SPEC/SPECTRE/GVEC sidecars
  are emitted where needed. Unsupported lanes remain explicit rows.
- Input preparation strips unsupported diagnostics and legacy namelist
  terminators, stages relative MGRID files, and keeps prepared and cleaned
  inputs separate. FreeGS/CHEASE only receive their native 2-D inputs; SPEC
  only receives native SPEC namelists.
- jVMEC benchmark PR [#3](https://github.com/jonathanschilling/jVMEC/pull/3)
  contains the local-MGRID registration fix. DESC PR
  [#2300](https://github.com/PlasmaControl/DESC/pull/2300) contains the
  zero-Gershgorin fix and requested changelog entry (`d9b67ba`).
- GVEC is split by concern, with both MRs targeting upstream `develop`:
  [!175 sparse/inline VMEC boundaries](https://gitlab.mpcdf.mpg.de/gvec-group/gvec/-/merge_requests/175)
  (`8b0bec2f`) and
  [!176 long restart/state paths](https://gitlab.mpcdf.mpg.de/gvec-group/gvec/-/merge_requests/176)
  (`3e818219`). The fork branch `calbert/gvec:benchmark/gvec-combined`
  stacks both fixes for benchmark runs. The combined checkout passed 87
  converter/state tests and the >255-character restart regression.
- SPECTRE MR
  [!58](https://gitlab.com/spectre-eq/spectre/-/merge_requests/58) fixes the
  overlap Jacobian shape mismatch. The MR build runs the W7-X input that fails
  on the old checkout without the shape exception.

## Authoritative exhaustive run

Slurm job `1791220` runs the current `main` checkout on `node11`, with a
600-second per-implementation timeout. Its result root is:

`/home/ert/benchmark_vmec-slurm-233aa21/benchmark_vmec-longpath-f370c3d/benchmark_results-slurm-1791220/`

The job has completed the built-in analytical/numerical cases and is processing
the educational_VMEC inventory. At the last update it had 75 implementation
starts, 80 completions, 3 explicit failures, and no `MPI_ABORT`. The observed
failures are labelled solver/feature rows: VMEX non-convergence, GVEC's
unsupported `two_power` free-boundary profile, and the old SPECTRE overlap
Jacobian on educational W7-X. The patched SPECTRE and stacked GVEC builds have
already passed focused reruns; affected result directories will be refreshed
after the exhaustive job finishes.

The earlier pre-fix job `1791165` was canceled after its log/results were
preserved and is not final evidence. No plot job is queued yet; plots will be
generated only from the post-fix result root after focused refreshes.

Monitor the active run with:

```bash
ssh scluster 'squeue -j 1791220 -o "%.18i %.12T %.10M %.20R"'
ssh scluster 'tail -f /home/ert/benchmark_vmec-slurm-233aa21/benchmark_vmec-longpath-f370c3d/slurm-vmec-benchmark-latest-1791220.out'
```

## Finish checklist

1. Let `1791220` finish and classify every failure. Rerun only affected
   converter/upstream-bug cases with the stacked GVEC and SPECTRE checkouts;
   preserve genuine solver non-convergence/unsupported rows.
2. Generate scalar, surface, and native timing plots with
   `uv run --with netCDF4 --with matplotlib python
   tools/plot_benchmark_results.py <final-result-root>`, inspect all three,
   and record their paths here.
3. Run the final local gates, update this file with final counts and plot
   paths, stage explicit paths, commit, and push `main`.
