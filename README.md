# VMEC Implementation Benchmark Suite

[![CI](https://github.com/itpplasma/benchmark_vmec/actions/workflows/ci.yml/badge.svg)](https://github.com/itpplasma/benchmark_vmec/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/itpplasma/benchmark_vmec/branch/main/graph/badge.svg)](https://codecov.io/gh/itpplasma/benchmark_vmec)

A Fortran package built with `fpm` for comparing VMEC implementations from sibling repositories.

## Overview

The active purpose of this repository is narrow:

- run the same stellarator and tokamak inputs across `vmecpp`, `educational_VMEC`, `VMEC2000`, and `jVMEC`
- collect a comparable subset of outputs
- provide focused tooling for regression checks and cross-code investigation

The suite expects the repositories to live one directory above `benchmark_vmec`:

- `../vmecpp`
- `../educational_VMEC`
- `../VMEC2000`
- `../jVMEC`

`jVMEC` is optional but strongly recommended when working on asymmetric or tokamak behavior because it is the current reference implementation for those cases in this workspace.

## Quick Start

```bash
# Build the tool
fpm build

# Build the sibling repositories that the benchmark can manage directly
fpm run vmec-build

# Run the benchmark driver
fpm run vmec-benchmark -- run

# Run only symmetric cases
fpm run vmec-benchmark -- run --symmetric-only

# Run the unit tests for this repo
fpm test
```

## Main Commands

- `vmec-benchmark setup`
  Clones `educational_VMEC`, `VMEC2000`, and `vmecpp` into the sibling directory if they are missing.
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
- Python 3 with an importable `vmecpp` package for the VMEC++ runner

### Installation
```bash
fpm build
```

## Typical Workflows

### 1. Check repository wiring
```bash
fpm run vmec-benchmark -- list-repos
fpm run vmec-benchmark -- list-cases --limit 20
```

### 2. Run a focused comparison pass
```bash
fpm run vmec-benchmark -- run --limit 5
fpm run vmec-benchmark -- run --symmetric-only --limit 10
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
test/                unit tests for repo management and comparison logic
design/              persistent implementation-analysis notes
compare_*.sh         manual symmetric and asymmetric debug workflows
create_inputs_dir.sh regenerate the input inventory in inputs.md
```

## Generated Output

Generated benchmark results are written under `benchmark_results/`. Manual debug runs create `symmetric_debug_*` or `asymmetric_debug_*` directories in the repo root. None of those outputs should be committed.

## Documentation

- [`design/index.md`](design/index.md) maps the asymmetric-implementation analysis notes.
- [`doc/README.md`](doc/README.md) gives a short documentation index for the repo itself.
- `inputs.md` is a generated inventory of benchmark inputs from the sibling repositories.

## Current Boundaries

- This repo is for orchestration, comparison, and investigation support.
- The implementation-specific fixes belong in the sibling repositories.
- The design notes are worth keeping, but generated run output and mock summaries are not.
├── jvmec_implementation.f90
├── repository_manager.f90         # Repository management
├── benchmark_runner.f90           # Benchmark execution
└── results_comparator.f90         # Result analysis

test/             # Test sources
├── test_vmec_types.f90
└── test_repository_manager.f90
```

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
