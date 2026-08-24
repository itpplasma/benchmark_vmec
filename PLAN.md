# Benchmark continuation plan

This repository runs the ordinary, non-differentiable equilibrium benchmark.
The corpus covers analytical and numerical 1-D, 2-D, and 3-D cases. FreeGS and
CHEASE are restricted to the 2-D Grad--Shafranov lane; the differentiable-MHD
project is separate.

## Current status (2026-08-24)

- `main` is pushed through `25d115c`. Local `fo test test_runner_reporting`,
  Python byte-compilation of all bridge scripts, and `git diff --check` pass.
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
- The previous exhaustive job `1791025` was canceled before the CHEASE staging
  and test-isolation fixes landed. A fresh exhaustive submission is the next
  action after this commit is pulled to the corrected checkout. It uses one
  node, 48 CPUs, 96 GB, a 7-day allocation, and a 600-second per-case timeout.
  Monitor the new job with:

  ```bash
  ssh scluster 'squeue -j <JOBID> -o "%.18i %.12T %.10M %.20R"'
  ssh scluster 'sacct -j <JOBID> --format=JobID,State,Elapsed,ExitCode'
  ssh scluster 'tail -f /home/ert/benchmark_vmec-slurm-233aa21/benchmark_vmec-corrected/slurm-vmec-benchmark-<JOBID>.out'
  ```

- Obsolete pre-fix exhaustive job `1790415` was cancelled after its output was
  preserved; it must not be used as the final benchmark result.

- Canceled pre-CHEASE-staging exhaustive job `1791025` is retained only as
  diagnostic history; it must not be used as the final benchmark result.

- PARVMEC is discovered as a repository but is not installed on the cluster;
  it remains an explicit unavailable implementation until its Python package
  or executable is staged. No other expected VMEC-like code is missing from
  the configured repository inventory.

## Handoff

After the fresh exhaustive job starts, inspect its output for immediate
adapter/converter errors, then wait for completion. Keep genuine solver
failures/timeouts as explicit rows; only retry environment or conversion
defects. Regenerate plots from the final `comparison_table.csv` with
`tools/plot_benchmark_results.py` and record their paths here.
