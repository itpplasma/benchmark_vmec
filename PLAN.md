# Benchmark continuation plan

This repository runs the ordinary, non-differentiable equilibrium benchmark.
The corpus covers analytical and numerical 1-D, 2-D, and 3-D cases. FreeGS and
CHEASE are restricted to the 2-D Grad--Shafranov lane; the differentiable-MHD
project is separate.

## Current status (2026-08-24)

- `main` is pushed through `74bf514`. Local `fo test` (5/5), Python
  byte-compilation of all bridge scripts, Slurm shell syntax checks, and
  `git diff --check` pass.
- VMEC-family lanes are wired for educational_VMEC, jVMEC, VMEC2000, VMEC++,
  VMEX, DESC, and GVEC. GVEC's native `*_State_final.dat` is retained and
  converted to `gvec_result.json` for the common scalar comparison.
- Ordinary bridges are present for VMEC↔SPECTRE TOML/JSON, GVEC state,
  FreeGS GEQDSK/JSON, and common metadata↔VMEC/GEQDSK/SPEC/SPECTRE templates.
  SPEC is invoked only for native `.sp`; CHEASE only for native 2-D
  `.geqdsk`/`.eqdsk`. VMEC INDATA is explicitly skipped for both contracts.
- `LFULL3D1OUT` is dropped by the educational-VMEC input adapter because that
  fork does not implement the VMEC2000 output-policy flag; converted W7-X/NCSX
  inputs therefore reach solver iterations instead of failing at parse time.
- Corrected smoke job `1791021` completed with exit 0. The Solovev case passed
  educational_VMEC, jVMEC, VMEC2000, VMEC++, VMEX, DESC, GVEC, SPECTRE, and
  FreeGS; SPEC and CHEASE were recorded as contract-appropriate skips. Results:
  `/home/ert/benchmark_vmec-slurm-233aa21/benchmark_vmec-corrected/benchmark_results-slurm-1791021/`.
- Targeted CHEASE smoke job `1791034` completed with exit 0 in 2:39. The
  runtime-staged D3D `GEQDSK` fixture was discovered, all non-CHEASE
  implementations were skipped by the native-format contract, CHEASE exited
  successfully, and its `chease_result.json` sidecar was written. Results:
  `/home/ert/benchmark_vmec-slurm-233aa21/benchmark_vmec-corrected/benchmark_results-slurm-1791034/`.
- GVEC is now explicitly skipped for 1-D profile fixtures: its VMEC converter
  requires nested-surface `iota` data that the 1-D contract intentionally does
  not provide. The filter is covered by the runner tests and will be used for
  the corrected focused rerun after the exhaustive job.
- The GVEC bridge additionally normalizes sparse VMEC `(n,m)` boundary
  assignments into dense `(m,n)` arrays and seeds the ordinary zero-iota
  initialization required by GVEC's stage builder. The exhaustive job was
  already running with the pre-bridge executable when this was diagnosed; its
  early GVEC conversion failures are retained as diagnostic evidence.
- The SPECTRE bridge accepts legacy VMEC files that contain both `/` and a
  trailing `&END`; corrected conversion smoke reaches SPECTRE initialization
  for W7X, `input.test.vmec`, and `Ns_2048.M_32` instead of failing in f90nml.
- The previous exhaustive job `1791025` was canceled before the CHEASE staging
  and test-isolation fixes landed. Fresh exhaustive job `1791036` is now
  submitted with one node, 48 CPUs, 96 GB, a 7-day allocation, and a
  600-second per-case timeout. It started on `node11` and is currently
  progressing through the 298-case corpus.
- Corrected-checkout numerical tokamak smoke `1791060` was submitted with an
  8-CPU/16-GB one-hour allocation to exercise the new GVEC and SPECTRE
  bridges; it completed in 4:18 with exit 0. Educational_VMEC, jVMEC,
  VMEC2000, VMEC++, VMEX, DESC, SPECTRE, and FreeGS passed. GVEC reached its
  solver and reported the physical `detJ<0` minimization failure; SPEC and
  CHEASE were contract-appropriate skips. Results:
  `/home/ert/benchmark_vmec-slurm-233aa21/benchmark_vmec-corrected/benchmark_results-slurm-1791060/`.
  Monitor it with:

  ```bash
  ssh scluster 'squeue -j 1791036 -o "%.18i %.12T %.10M %.20R"'
  ssh scluster 'sacct -j 1791036 --format=JobID,State,Elapsed,ExitCode'
  ssh scluster 'tail -f /home/ert/benchmark_vmec-slurm-233aa21/benchmark_vmec-corrected/slurm-vmec-benchmark-1791036.out'
  ```

- Corrected-checkout numerical W7-X smoke `1791068` completed with exit 0 in
  5:36. Educational_VMEC, jVMEC, VMEC2000, VMEC++, VMEX, DESC, GVEC, and
  SPECTRE all completed; SPEC, FreeGS, and CHEASE were excluded by their
  input-format/dimensionality contracts. The corrected GVEC `(n,m)` bridge
  therefore passes a non-axisymmetric 3-D case end to end. Results:
  `/home/ert/benchmark_vmec-slurm-233aa21/benchmark_vmec-corrected/benchmark_results-slurm-1791068/`.

- Plots were regenerated and visually checked for the corrected tokamak and
  W7-X runs. Each scalar panel has one marker per available code with a shared
  code legend; runtime plots contain only native solver-reported timings.
  They are under each result directory's `plots/` folder (`metrics.png`,
  `surfaces.png`, `runtime.png`, and `runtime.csv`).

- Exhaustive job `1791036` remains stable on `node11`. At the latest check it
  had started 209 of the 298 discovered cases (166 completion messages) after
  1:30:41, with no MPI abort; stderr contains only the expected unavailable
  PARVMEC notice and diagnostic failures from the pre-bridge executable that
  was already running before the latest converter fixes.

- Corrected exhaustive rerun `1791080` is submitted with an `afterany:1791036`
  dependency. It uses the pushed converter fixes and will become the final
  corpus run after the diagnostic allocation releases its node.

- Obsolete pre-fix exhaustive job `1790415` was cancelled after its output was
  preserved; it must not be used as the final benchmark result.

- Canceled pre-CHEASE-staging exhaustive job `1791025` is retained only as
  diagnostic history; it must not be used as the final benchmark result.

- PARVMEC is discovered as a repository but is not installed on the cluster;
  it remains an explicit unavailable implementation until its Python package
  or executable is staged. No other expected VMEC-like code is missing from
  the configured repository inventory.

## Remaining work

- Let diagnostic job `1791036` finish; keep its pre-bridge failures as history,
  not as the final benchmark.
- Verify corrected exhaustive job `1791080` after its dependency releases,
  fixing only environment or converter defects and preserving genuine solver
  failures/timeouts as explicit rows.
- After `1791080` completes, regenerate scalar, surface, and timing plots from
  its final `comparison_table.csv`, inspect them, and record their paths here.
- Decide whether the corrected tokamak GVEC `detJ<0` solver failure remains an
  accepted physical non-convergence or merits a separately tuned case; the
  corrected non-axisymmetric W7-X GVEC run already passes end to end.
