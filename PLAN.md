# Benchmark status and handoff

This repository runs the ordinary, non-differentiable equilibrium benchmark.
It covers analytical and numerical 1-D, 2-D, and 3-D cases. FreeGS and CHEASE
are restricted to the 2-D Grad--Shafranov/GEQDSK lane; the differentiable-MHD
benchmark is separate.

## Current implementation

- `main` is pushed and clean. The driver has explicit lanes for
  educational_VMEC, jVMEC, VMEC2000, VMEC++, VMEX, DESC, GVEC, PARVMEC, SPEC,
  SPECTRE, FreeGS, and CHEASE. The exhaustive stack has 11 lanes; PARVMEC is
  built and run separately with the pinned superbuild below.
- The final stack discovers 345 cases. The corpus includes 10 native SPEC
  inputs and the native SPECTRE `.sp`/`.toml` inventory. Native outputs are
  retained; VMEC, GVEC, SPECTRE, SPEC, JSON, NetCDF, and GEQDSK
  converters/sidecars are used where a code does not natively provide the
  common benchmark format.
- `tools/build_parvmec.sh` pins PARVMEC `eae0ff26` and LIBSTELL `8f0dbd7`,
  records a build manifest, and emits a stable `xvmec` path. The
  `tools/run_parvmec_slurm.sbatch` wrapper uses `--impl parvmec` and a private
  output tree, so it can run beside the exhaustive allocation without building
  or launching any other implementation.
- Input preparation strips unsupported diagnostics and legacy terminators,
  stages relative MGRID files (following checkout symlinks), and keeps
  prepared and cleaned inputs separate. FreeGS/CHEASE receive only their
  supported 2-D inputs, and SPEC only receives native SPEC namelists.
- Shell-bound paths are quoted as single arguments, including the spaces in
  educational_VMEC's `Free Boundary` fixtures. Focused Slurm refresh `1826653`
  completed the `JDHtest7` case across all available lanes after this fix;
  the remaining failures there are solver outcomes, not input-discovery
  failures.
- VMEC2000's Python adapter now mirrors the standalone PARVMEC output
  handshake: it requests cleanup and, after `more_iter_flag`, makes a final
  output call with the successful flag so a bounded non-converged state still
  has a comparable WOUT (`ab9b3ea`). The local `fo check`/`fo test --all`
  gates pass, and compute-node API smokes produced valid WOUT files.
- The SPECTRE VMEC converter probes the signed boundary area and selects
  `Lchangeangle` per input. This preserves the usual handedness for W7-X/NCSX
  while handling the opposite-handed HELIOTRON fixtures without MPI aborts;
  it also normalizes legacy `&END`/separator headers so historical VMEC
  namelists remain parseable. The `isaev1` conversion and limited SPECTRE
  smoke now produce a native result JSON. The SPECTRE runner propagates a
  native JSON `success=false` as a failed implementation status; the runtime
  plot applies the same filter.
- Cluster validation passed `fo check` (21 modules, 5 tests), shell syntax
  checks, and the converter/state focused tests (87 GVEC tests plus the
  selected long-path regression).

## Upstream work

- [jVMEC PR #3](https://github.com/jonathanschilling/jVMEC/pull/3) is merged
  upstream as `778e06c5`; it adds the local-MGRID registration fix. The sole
  inline review comment was handled in `03937ff0` by removing diagnostic debug
  printouts; Maven packaging and the SOLOVEV runner smoke pass.
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

At the 2026-08-26 07:21 CEST handoff it has 1,702 implementation starts,
989 completions, 685 explicit failures, 646 supported-case skips, and one
active implementation; the driver output
contains no `MPI_ABORT`. The result root currently has 86 native SPECTRE
result JSON files (47 native successes and 39 native unsuccessful
minimizations), including the refreshed HELIOTRON rows from the
orientation-aware converter. The remaining
hard SPECTRE failures are parser/timeout rows rather than MPI aborts. The original
HELIOTRON abort logs are retained outside the result root at
`/home/ert/benchmark_vmec-slurm-233aa21/spectre-refresh-audit-1791254/`.
Focused Slurm refresh `1820253` repaired seven legacy-header rows; `isaev1`
now reaches the solver but hits the ordinary 600-second timeout. A separate
nine-case Free Boundary path refresh (`1827777`) uses the quoted path fix and
the benchmark's full 600-second timeout; its rows are kept in a separate
refresh root until the job is verified and merged.
An attempted in-allocation overlap probe hit the cluster Open MPI/PMI
configuration and was terminated; its log and partial output are quarantined
under `spectre-refresh-audit-1791254/` and are not benchmark evidence.
Persistent progress is logged at
`/home/ert/benchmark_vmec-slurm-233aa21/benchmark-progress-1791254.log`.
The failures seen so far are honest solver/feature rows: GVEC
force-tolerance/non-convergence or unsupported VMEC profiles, VMEX and jVMEC
non-convergence on difficult educational inputs, and bounded SPECTRE timeouts
on difficult cases. The job remains running; do not cancel it.

PARVMEC-only Slurm job `1895605` runs independently with `node20` excluded;
its result root is
`/home/ert/benchmark_vmec-slurm-233aa21/benchmark_vmec-final/benchmark_results-parvmec-full/`.
It discovered and processed all 344 cases and wrote the complete comparison
report/CSV (`243` successes, `101` failed or unsupported rows). Slurm recorded
`FAILED 127:0` only after the report was written; the only diagnostic was
`tools/run_slurm_benchmark.sh: line 166: 2: command not found`. A one-case
timeout through the generic launcher (`1895657`), a one-case timeout through
the PARVMEC wrapper (`1895662`), and the normal timeout path all completed
with exit 0, so the old full-run status is retained as a wrapper-cleanup
anomaly rather than a solver failure. No PARVMEC rerun is required for the
already complete data tree unless a clean Slurm exit is specifically needed.
The one-case smoke job `1895604` passed on `node15`; its native WOUT and
timing files are retained under the corresponding smoke root.
The diagnostic-input preparation fix was verified independently: refresh job
`1895612` completed all five `educational_VMEC/test/coverage` cases (including
SOLOVEV and HELIOTRON) successfully in
`benchmark_results-parvmec-coverage-refresh`. Refresh job `1895616` ran the
14 `educational_VMEC/test/from_DESC` cases with the same isolated
PARVMEC-only wrapper/build and completed 12/14 (NCSX and W7X reached the
600-second solver bound). These refresh trees remain separate until the
exhaustive job is terminal, then their PARVMEC rows can replace the stale
pre-fix rows without touching other implementations.

The canonical-lane audit explains the apparent VMEC2000/PARVMEC failures:
`1791254` loaded its benchmark executable before the quoted-path fix, so its
nine `Free Boundary` VMEC2000 rows failed in input preparation even though
the solver wrote WOUT files. Fresh JDHtest7 compute-node runs (`1895675`,
`1895677`, `1895678`) exit 0. The 64 no-output rows in `1895605` are likewise
from its pre-refresh runner: 29 native GVEC files, two native DESC files, and
33 legacy/unprepared VMEC inputs; the current coverage/`from_DESC` refreshes
already recover the valid coverage rows. Only NCSX and W7X remain genuine canonical timeouts
at 600 seconds for both VMEC2000 and PARVMEC; PARVMEC completes the ITER
hybrid case in 564 seconds.

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
