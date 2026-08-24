# VMEC Implementation Benchmark Suite

[![CI](https://github.com/itpplasma/benchmark_vmec/actions/workflows/ci.yml/badge.svg)](https://github.com/itpplasma/benchmark_vmec/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/itpplasma/benchmark_vmec/branch/main/graph/badge.svg)](https://codecov.io/gh/itpplasma/benchmark_vmec)

A Fortran package built with `fpm` for comparing equilibrium implementations from
sibling repositories.  The benchmark driver remains Fortran; Python is used only
inside the wrappers for codes whose public API is Python.

## Overview

The active purpose of this repository is an exhaustive, ordinary (non-
differentiable) equilibrium comparison:

- run the same inputs across the VMEC family (`vmecpp`, `educational_VMEC`,
  `VMEC2000`, `jVMEC`, `VMEX`, `PARVMEC`), nested-surface alternatives
  (`DESC`, `GVEC`), MRxMHD alternatives (`SPEC`, `SPECTRE`), and the requested
  2-D Grad--Shafranov comparison (`FreeGS`, with `CHEASE` wired when built)
- collect a comparable subset of outputs
- retain failed/unsupported rows and native output sidecars instead of hiding
  them, and provide focused tooling for regression checks and cross-code
  investigation

The suite expects the repositories to live one directory above `benchmark_vmec`:

- `../vmecpp`
- `../educational_VMEC`
- `../VMEC2000`
- `../jVMEC`
- `../VMEX`
- `../DESC`
- `../gvec`
- `../PARVMEC`, `../SPEC`, `../SPECTRE`, `../freegs`, and `../CHEASE` (optional
  native participants)

The repository-owned corpus in `cases/` is always included. It has analytical
and numerical fixtures for each of 1-D, 2-D, and 3-D. FreeGS is deliberately
limited to the 2-D fixtures; other rows remain explicit unsupported results so
the matrix is exhaustive.

`jVMEC` is optional but strongly recommended when working on asymmetric or tokamak behavior because it is a useful independent cross-check for geometry and coefficient handling in this workspace.

STELLOPT and SIMSOPT orchestrate or optimise other solvers rather than being
standalone equilibrium solvers, so they are documented as out of scope.

Free-boundary and asymmetric cases are included by default.  Use
`--symmetric-only` only when a fixed symmetric subset is wanted.  DESC and GVEC
retain their native input formats (`input.*` and `parameter.{ini,toml,yaml}`),
while VMEC-family cases use standard INDATA/JSON files.

## Quick Start

```bash
# Build the tool
fo check

# Build the sibling repositories that the benchmark can manage directly
fo run vmec-build -- --base-dir ..

# Run the benchmark driver
fo run vmec-benchmark -- run

# Run only symmetric cases
fo run vmec-benchmark -- run --symmetric-only

# Run one named family of cases
fo run vmec-benchmark -- run --match tokamak

# Run the unit tests for this repo
fo test --all
```

## Main Commands

- `vmec-benchmark setup`
  Clones the configured repositories into the sibling directory if they are
  missing. `jVMEC` remains a manually provisioned optional checkout.
- `vmec-benchmark run`
  Discovers input files from sibling repos, runs available implementations, and writes results under `benchmark_results/`.
- `vmec-benchmark list-repos`
  Shows which sibling repos are available.
- `vmec-benchmark list-cases`
  Shows discovered benchmark inputs.
- `vmec-build`
  Builds the implementations that this repo knows how to build directly.

## Requirements

### System Dependencies
- Modern Fortran compiler (GFortran 9+, Intel Fortran, etc.)
- Fortran Package Manager (fpm) - https://fpm.fortran-lang.org/
- Git
- CMake (for building VMEC implementations)
- Make/GCC (for building VMEC implementations)
- Maven + Java 8+ (for jVMEC, optional)
- Python 3 with the package required by each Python-backed wrapper (`vmecpp`, `vmex`, `desc`, or `gvec`)

### Common formats

`tools/convert_equilibrium.py` provides VMEC INDATA/JSON ↔ canonical JSON,
VMEC → GVEC `parameter.ini`, GEQDSK summaries, and SPEC HDF5 dataset
inventories. DESC writes a VMEC-compatible NetCDF WOUT when its `VMECIO`
export is available. SPEC/SPECTRE are different physical models, so their
native outputs are reported without claiming a lossless WOUT conversion.
FreeGS writes GEQDSK plus a JSON sidecar with pressure, current, grid, and
analytical/numerical labels.

### Installation
```bash
fo check
```

## Typical Workflows

### 1. Check repository wiring
```bash
fo run vmec-benchmark -- list-repos
fo run vmec-benchmark -- list-cases --limit 20
```

### 2. Run a focused comparison pass
```bash
fo run vmec-benchmark -- run --limit 5
fo run vmec-benchmark -- run --symmetric-only --limit 10
fo run vmec-benchmark -- run --match up_down_asymmetric_tokamak
fo run vmec-benchmark -- list-cases --match tokamak
```

### 3. Manual debug comparisons
```bash
./compare_symmetric_debug.sh
./compare_asymmetric_debug.sh
```

These scripts create timestamped debug directories locally. They are intentionally ignored by git.

## Repository Layout

```
app/                 CLI entry points
src/                 benchmark runner and implementation wrappers
cases/               analytical/numerical 1-D, 2-D, and 3-D fixtures
tools/               common-format and FreeGS adapters
test/                unit tests for repo management and comparison logic
design/              persistent implementation-analysis notes
compare_*.sh         manual symmetric and asymmetric debug workflows
create_inputs_dir.sh regenerate the input inventory in inputs.md
```

## Generated Output

Generated benchmark results are written under `benchmark_results/`. Manual debug runs create `symmetric_debug_*` or `asymmetric_debug_*` directories in the repo root. None of those outputs should be committed.

## Documentation

- [`design/solver_inventory.md`](design/solver_inventory.md) records the
  solver-coverage audit and intentional out-of-scope tools.
- [`design/ordinary_benchmark_contract.md`](design/ordinary_benchmark_contract.md)
  records the ordinary-comparison lessons adopted from the parallel audit.
- [`design/index.md`](design/index.md) maps the asymmetric-implementation analysis notes.
- [`doc/README.md`](doc/README.md) gives a short documentation index for the repo itself.
- `inputs.md` is a generated inventory of benchmark inputs from the sibling repositories.

## Current Boundaries

- This repo is for orchestration, comparison, and investigation support.
- The implementation-specific fixes belong in the sibling repositories.
- The design notes are worth keeping, but generated run output and mock summaries are not.

### Adding New VMEC Implementations

1. Create a new implementation module inheriting from `vmec_implementation_base`
2. Implement required procedures: `build()`, `run_case()`, `extract_results()`
3. Add to the benchmark runner configuration
4. Write unit tests for the new implementation
5. Update documentation

## Dependencies

This package uses the following Fortran dependencies managed by fpm:
- `json-fortran`: JSON parsing and generation
- `M_CLI2`: Command-line interface
- `fortran_test_helper`: Testing framework (dev dependency)

## License

MIT License - This benchmark suite is provided under the MIT license. Individual VMEC implementations may have different licenses.
