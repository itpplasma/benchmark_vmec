# VMEC Benchmark Design Index

This directory keeps durable analysis notes for the VMEC++ asymmetric and tokamak work. The goal is not to preserve every debug artifact. The goal is to preserve the reasoning, the comparison points, and the places where the implementation diverges or still needs attention.

## Current Working Picture

As of the 2026-04-15 cleanup pass:

- The benchmark harness can run `educational_VMEC`, `jVMEC`, `VMEC2000`, and `vmecpp` from sibling repositories.
- `educational_VMEC` input normalization is in place for newer namelist variants that previously broke cross-code runs.
- `jVMEC` now fails cleanly when it does not produce `wout`, instead of masking solver failure with a Java null-pointer during output writing.
- `VMEC2000` results now carry Fourier arrays into the benchmark report instead of looking artificially empty.
- The focused 6-case slice now completes in `vmecpp`, including:
  - `educational_VMEC/from_booz_xform/LandremanSenguptaPlunk_section5p3`
  - `educational_VMEC/from_booz_xform/up_down_asymmetric_tokamak`
  - `educational_VMEC/from_booz_xform/circular_tokamak`
- The remaining visible failures in that slice are `jVMEC` non-convergence on some stellarator cases such as:
  - `educational_VMEC/from_vmec_multiple_readin/li383_low_res`
  - `educational_VMEC/from_quasisymmetry/li383_vacuum`
  - `educational_VMEC/from_booz_xform/li383_1.4m`
- The remaining `vmecpp` work in that slice is now quantitative, not runtime:
  - edge-iota and axis drift on `li383_vacuum`
  - axis and edge-iota drift on `LandremanSenguptaPlunk_section5p3`
  - small axis drift on `up_down_asymmetric_tokamak`
- The general benchmark report now prefers Fortran references case-by-case:
  - `educational_VMEC`
  - then `VMEC2000`
  - then `jVMEC`
  - then `vmecpp`

## How To Read These Notes

Read them in this order if you need orientation first:

1. `guess_axis.md`
   The most grounded analysis of a specific asymmetric fix. This is the clearest validated comparison point today.
2. `fourier_asymmetric.md`
   The core note for the new asymmetric transform path in `vmecpp`.
3. `ideal_mhd_model.md`
   The top-level integration note for how asymmetric handling was threaded into the solver.
4. `vmec_indata.md` and `vmec_indata_pywrapper.md`
   Input-shape and Python-API notes. These matter for reproducing cases and for the tokamak branch.
5. `output_quantities.md`
   Important when the solver converges but reported quantities still disagree.

Use the remaining files as supporting detail, not as the first entry point.

## Document Groups

### 1. Core VMEC++ asymmetric implementation notes

- `fourier_asymmetric.md`
  Dedicated note for the asymmetric Fourier transforms and force terms.
- `ideal_mhd_model.md`
  Where the asymmetric pieces enter the main force-evaluation flow.
- `boundaries.md`
  Boundary handling and Jacobian sign logic.
- `guess_axis.md`
  Magnetic-axis recovery and BAD_JACOBIAN handling.
- `fourier_coefficients.md`
  Fourier-array ownership and initialization.
- `handover_storage.md`
  Storage layout for asymmetric arrays.
- `output_quantities.md`
  Post-processing and derived quantities.
- `vmec_main.md`
  High-level solver integration.

### 2. Input and interface notes

- `vmec_indata.md`
  Input semantics for asymmetric boundary and axis coefficients.
- `vmec_indata_pywrapper.md`
  Python wrapper behavior and array sizing.
- `VMEC_INPUT_OUTPUT_COMPARISON.md`
  Cross-code view of input and output formats. Useful when debugging benchmark ingestion or conversion logic.

### 3. jVMEC-specific comparison notes

- `jvmec_netcdf_comparison.md`
  What jVMEC does and does not write to NetCDF, and why direct comparisons used to fail.
- `jvmec_compatible_results.md`
  Notes from the phase where comparison was restricted to quantities jVMEC actually exposed.

### 4. Historical branch archaeology

These are still worth keeping, but they are not source-of-truth design docs:

- `PR.md`
  Comparison of earlier upstream PR states.
- `REVERT.md`
  Audit trail of questionable changes and temporary debugging edits.

Treat both as historical context. Re-check against the current code before acting on them.

## Status Markers For The Core Notes

Use this reading of the current status labels, regardless of what an older document may say internally:

- `Verified`
  Confirmed against current benchmark evidence or direct code comparison.
- `Useful but stale`
  The reasoning still helps, but implementation details need re-checking against the current branch.
- `Historical`
  Keep for context, not for direct decision-making.

Current rough classification:

- `guess_axis.md`: Verified
- `VMEC_INPUT_OUTPUT_COMPARISON.md`: Verified at the structural level, but refresh specific benchmark examples when used
- `jvmec_netcdf_comparison.md`: Verified for the original observation, now partly superseded by benchmark-side extraction fixes
- `jvmec_compatible_results.md`: Useful but stale
- `fourier_asymmetric.md`: Useful but stale
- `ideal_mhd_model.md`: Useful but stale
- `boundaries.md`: Useful but stale
- `fourier_coefficients.md`: Useful but stale
- `handover_storage.md`: Useful but stale
- `output_quantities.md`: Useful but stale
- `vmec_indata.md`: Useful but stale
- `vmec_indata_pywrapper.md`: Useful but stale
- `vmec_main.md`: Useful but stale
- `PR.md`: Historical
- `REVERT.md`: Historical

## About Debug Output

Some branches and notes refer to extensive debug output in `vmecpp`. That output was not random churn. It was added to localize:

- initial Jacobian sign changes
- magnetic-axis recovery behavior
- asymmetric real-space symmetrization
- early-iteration solver failure in tokamak and asymmetric cases

Until the remaining `vmecpp` failures above are understood, those debug traces still serve a purpose. They should only be removed once the specific failure modes they illuminate are either fixed or captured in cleaner diagnostics.

## What Still Needs Fresh Analysis

The highest-value follow-up analysis is now narrower than before:

1. Why `vmecpp` still lands on a different axis and edge iota on `li383_vacuum`.
2. Why `vmecpp` still shows axis and edge-iota drift on `LandremanSenguptaPlunk_section5p3` after the runtime fix.
3. Whether the disagreement between `jVMEC` and the Fortran/C++ codes on tokamak-derived scalar quantities is a physics difference, an output-definition mismatch, or a remaining extraction inconsistency.
4. Whether the non-convergent `jVMEC` stellarator cases can be improved with input cleaning alone, or whether they need solver-side work.

That is the shortest path back to productive development and benchmarking without drowning in old branch churn.
