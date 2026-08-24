# VMEC Implementation Benchmark Suite

[![CI](https://github.com/itpplasma/benchmark_vmec/actions/workflows/ci.yml/badge.svg)](https://github.com/itpplasma/benchmark_vmec/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/itpplasma/benchmark_vmec/branch/main/graph/badge.svg)](https://codecov.io/gh/itpplasma/benchmark_vmec)

An ordinary (non-differentiable) benchmark for magnetic-equilibrium codes. The
Fortran driver discovers cases, runs every available implementation, compares a
common set of quantities, and preserves successful, failed, and unsupported
rows in the report.

## Scope

The matrix covers VMEC-like codes (`vmecpp`, `educational_VMEC`, `VMEC2000`,
`jVMEC`, `VMEX`, `PARVMEC`), nested-surface codes (`DESC`, `GVEC`), MRxMHD
codes (`SPEC`, `SPECTRE`), and Grad--Shafranov codes (`FreeGS`, `CHEASE`).
FreeGS is the 2-D comparison; the repository-owned corpus still exercises both
analytical and numerical fixtures in 1-D, 2-D, and 3-D. The differentiable
benchmark lane is intentionally out of scope here.

Sibling repositories are expected one directory above this checkout. Missing
optional repositories are reported as unavailable rather than silently omitted.

## Quick start

```bash
# Build and test this repository
fo check
fo test --all

# Build available sibling implementations, then run the ordinary benchmark
fo run vmec-build -- --base-dir ..
fo run vmec-benchmark -- run --base-dir ..

# Inspect wiring or run a focused subset
fo run vmec-benchmark -- list-repos --base-dir ..
fo run vmec-benchmark -- list-cases --match tokamak
fo run vmec-benchmark -- run --match tokamak --limit 5
```

Results are written to `benchmark_results/`, including Markdown and CSV
reports plus native output sidecars.

## Common-format adapters

`tools/convert_equilibrium.py` converts VMEC INDATA/JSON to the benchmark's
canonical JSON metadata and emits documented native templates or summaries for
GVEC, GEQDSK, and SPEC. `tools/run_freegs.py` runs a 2-D FreeGS case and
writes GEQDSK plus a JSON sidecar. Use `uv run` for these Python tools, for
example:

```bash
uv run --project ../FreeGS python tools/run_freegs.py cases/analytic/2d_solovev/input.solovev out
uv run python tools/convert_equilibrium.py --help
```

These adapters are deliberately ordinary-format utilities; they do not expose
automatic differentiation or Jacobian data.

## Repository layout

```
app/       command-line entry points
src/       benchmark runner, comparisons, and implementation wrappers
cases/     analytical and numerical 1-D, 2-D, and 3-D fixtures
tools/     self-contained common-format and FreeGS adapters
test/      independent Fortran tests
```

See [AGENTS.md](AGENTS.md) for the short contributor and automation contract.

## Adding an implementation

Add a wrapper in `src/` derived from `vmec_implementation_base`, register it in
the runner/build command, and add an independent test. Keep native outputs and
explicit failure/unsupported records; do not invent a WOUT conversion for a
code whose physical model cannot provide one.

## License

MIT. Individual sibling implementations may use different licenses.
