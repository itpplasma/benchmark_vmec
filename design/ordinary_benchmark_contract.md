# Ordinary benchmark contract

The parallel differentiable-MHD audit was used only as a process lesson. This
repository intentionally contains no derivative/Jacobian lane. It adopts the
parts that improve an ordinary comparison:

1. Freeze the input path, code revision, generated common-format input, native
   command, and output artifact in each case directory.
2. Separate “process completed” from “result is comparable”. A timeout, failed
   conversion, unsupported dimension, or missing WOUT is a retained failed row.
3. Compare only a common physical family and dimensionality. VMEC WOUT scalars
   are not compared against a FreeGS GEQDSK or a SPEC MRxMHD HDF5 file.
4. Keep native outputs and sidecars so an independent physical check can be
   performed later; do not replace a code's objective with a convenient one.
5. Treat cold-start/JIT time and warm-solve results as separate measurements
   for Python-backed codes.

These rules make the benchmark exhaustive without turning it into the
differentiable experiment that motivated the audit.
