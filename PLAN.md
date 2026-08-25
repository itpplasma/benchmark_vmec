# Benchmark status and handoff

This repository runs the ordinary, non-differentiable equilibrium benchmark.
It covers analytical and numerical 1-D, 2-D, and 3-D cases. FreeGS and CHEASE
are restricted to the 2-D Grad--Shafranov/GEQDSK lane; the differentiable-MHD
benchmark is separate.

## Current implementation

- `main` is pushed at `182198c`. The driver has explicit lanes for
  educational_VMEC, jVMEC, VMEC2000, VMEC++, VMEX, DESC, GVEC, PARVMEC, SPEC,
  SPECTRE, FreeGS, and CHEASE. PARVMEC is discovered but is not buildable in
  the current cluster environment.
- The final stack discovers 345 cases and 11 implementation lanes, including
  10 native SPEC inputs and the native SPECTRE `.sp`/`.toml` inventory. Native
  outputs are retained; VMEC, GVEC, SPECTRE, SPEC, JSON, NetCDF, and GEQDSK
  converters/sidecars are used where a code does not natively provide the
  common benchmark format.
- Input preparation strips unsupported diagnostics and legacy terminators,
  stages relative MGRID files (following checkout symlinks), and keeps
  prepared and cleaned inputs separate. FreeGS/CHEASE receive only their
  supported 2-D inputs, and SPEC only receives native SPEC namelists.
- Cluster validation passed `fo check` (21 modules, 5 tests), shell syntax
  checks, and the converter/state focused tests (87 GVEC tests plus the
  selected long-path regression).

## Upstream work

- [jVMEC PR #3](https://github.com/jonathanschilling/jVMEC/pull/3) is merged
  upstream as `778e06c5`; it adds the local-MGRID registration fix.
- [DESC PR #2300](https://github.com/PlasmaControl/DESC/pull/2300):
  zero-Gershgorin fix and requested changelog entry (`d9b67ba`).
- GVEC MRs target upstream `develop` and are split by concern:
  [!175 sparse/inline VMEC boundaries](https://gitlab.mpcdf.mpg.de/gvec-group/gvec/-/merge_requests/175)
  (`8b0bec2f`) and
  [!176 long restart/state paths](https://gitlab.mpcdf.mpg.de/gvec-group/gvec/-/merge_requests/176)
  (`3e818219`). The benchmark uses fork branch
  `calbert/gvec:benchmark/gvec-combined`.
- [SPECTRE MR !58](https://gitlab.com/spectre-eq/spectre/-/merge_requests/58)
  fixes the overlap Jacobian shape mismatch; the benchmark uses its stacked
  checkout.
- Educational VMEC's optional `LFULL3D1OUT` work is pushed to the private fork
  branch [`benchmark/lfull3d1out`](https://github.com/itpplasma/educational_VMEC/tree/benchmark/lfull3d1out).

## Authoritative exhaustive run

Slurm job `1791254` is the source of truth. It runs the fixed stack from
`benchmark-stack-final` on `node20`, with a 600-second per-implementation
timeout and jVMEC enabled. Result root:

`/home/ert/benchmark_vmec-slurm-233aa21/benchmark_vmec-final/benchmark_results-slurm-final-mgrid/`

At the latest handoff snapshot it had 118 implementation starts, 117
completions, 19 explicit failures, one no-result row, and no `MPI_ABORT` in the
driver output. The failures seen so far are honest solver/feature rows:
GVEC force-tolerance/non-convergence or unsupported VMEC profiles, VMEX and
jVMEC non-convergence on one difficult educational input, and bounded SPECTRE
timeouts on difficult cases. The patched SPECTRE W7-X case and the fixed GVEC
converter have passed focused runs. The job remains running; do not cancel it.

Earlier exploratory jobs `1791244`, `1791245`, and `1791248` stopped after
specific checkout/converter/MGRID defects and are not evidence. The older
`1791220` run is preserved but predates the final native-inventory and MGRID
fixes and is not authoritative.

## Finish checklist

1. Let `1791254` finish; search both the driver and child logs for MPI aborts
   and classify every failure.
2. Verify FreeGS/CHEASE rows and native SPEC/SPECTRE inventories, then generate
   and visually inspect scalar, surface, and runtime plots with:

   ```bash
   uv run --with netCDF4 --with matplotlib python \
     tools/plot_benchmark_results.py <final-result-root> \
     --output-dir <final-result-root>/plots
   ```

3. Refresh `PLAN.md` with final counts, failure classes, plot paths, and
   completion time; run the local gates, stage explicit paths, commit, and
   push `main`.
