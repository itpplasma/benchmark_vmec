# Benchmark continuation plan

This repository runs the ordinary, non-differentiable equilibrium benchmark.
The corpus covers analytical and numerical 1-D, 2-D, and 3-D cases. FreeGS and
CHEASE are restricted to the 2-D Grad--Shafranov lane; the differentiable-MHD
project is separate.

## Current status (2026-08-24)

- `main` is pushed through `aed9aa6`. Local `fo test test_runner_reporting`,
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
- Corrected exhaustive job `1791025` is submitted on `scluster` with one node,
  48 CPUs, 96 GB, a 7-day allocation, and a 600-second per-case timeout. It is
  currently pending scheduler priority. Monitor it with:

  ```bash
  ssh scluster 'squeue -j 1791025 -o "%.18i %.12T %.10M %.20R"'
  ssh scluster 'sacct -j 1791025 --format=JobID,State,Elapsed,ExitCode'
  ssh scluster 'tail -f /home/ert/benchmark_vmec-slurm-233aa21/benchmark_vmec-corrected/slurm-vmec-benchmark-1791025.out'
  ```

- PARVMEC is discovered as a repository but is not installed on the cluster;
  it remains an explicit unavailable implementation until its Python package
  or executable is staged. No other expected VMEC-like code is missing from
  the configured repository inventory.

## Handoff

After `1791025` starts, inspect its output for immediate adapter errors, then
wait for completion. Keep genuine solver failures/timeouts as explicit rows;
only retry environment or conversion defects. Regenerate plots from the final
`comparison_table.csv` with `tools/plot_benchmark_results.py` and record their
paths here.
