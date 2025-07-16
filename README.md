# VMEC Implementation Benchmark Suite

[![CI](https://github.com/itpplasma/benchmark_vmec/actions/workflows/ci.yml/badge.svg)](https://github.com/itpplasma/benchmark_vmec/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/itpplasma/benchmark_vmec/branch/main/graph/badge.svg)](https://codecov.io/gh/itpplasma/benchmark_vmec)

A Fortran package built with fpm for automated comparison of multiple VMEC implementations.

## Overview

This benchmark suite automatically clones, builds, and compares multiple VMEC implementations:

- **VMEC++** (https://github.com/itpplasma/vmecpp.git) - Modern C++ implementation with enhanced algorithms
- **Educational VMEC** (https://github.com/hiddenSymmetries/educational_VMEC.git) - Reference Fortran implementation
- **VMEC2000** (https://github.com/hiddenSymmetries/VMEC2000.git) - SIMSOPT-style Python interface to VMEC
- **jVMEC** - Java implementation (not publicly available)

## Quick Start

```bash
# Build the package
fpm build

# Run benchmarks
fpm run vmec-benchmark

# Build VMEC repositories
fpm run vmec-build

# Run tests
fpm test
```

## Features

- **Modern Fortran**: Built with modern Fortran standards and fpm
- **Automatic Setup**: Auto-clones and builds missing VMEC repositories
- **Cross-Platform**: Works on Linux/macOS with standard Fortran build tools
- **Comprehensive Testing**: Runs all available test cases from implementations
- **Detailed Analysis**: Compares global quantities, force calculations, and convergence
- **Structured Output**: JSON results, comparison reports, and analysis data
- **Type Safety**: Strongly typed Fortran implementation with proper error handling

## Requirements

### System Dependencies
- Modern Fortran compiler (GFortran 9+, Intel Fortran, etc.)
- Fortran Package Manager (fpm) - https://fpm.fortran-lang.org/
- Git
- CMake (for building VMEC implementations)
- Make/GCC (for building VMEC implementations)
- Maven + Java 8+ (for jVMEC, optional)

### Installation
```bash
# Install fpm (if not already installed)
# See https://fpm.fortran-lang.org/install/index.html

# Build the benchmark suite
fpm build
```

## Usage Examples

### Build and run benchmarks:
```bash
# Build the package
fpm build

# Run the benchmark suite
fpm run vmec-benchmark

# Build VMEC repositories
fpm run vmec-build
```

### Run tests:
```bash
# Run all tests
fpm test

# Run specific test
fpm test test_vmec_types
fpm test test_repository_manager
```

### Development workflow:
```bash
# Build in debug mode
fpm build --profile debug

# Run with custom arguments (if supported)
fpm run vmec-benchmark -- --help
```

## Output Structure

```
benchmark_results/
├── comparison_report.md           # Main summary report
├── comparison_table.csv           # Numerical comparison data
├── raw_results.json              # Complete raw results
└── {test_case}/                  # Per-case detailed results
    ├── vmecpp/
    │   ├── vmecpp_results.json
    │   └── vmecpp.log
    ├── educational_vmec/
    │   ├── wout_*.nc
    │   ├── jxbout_*.nc
    │   └── educational_vmec.log
    ├── vmec2000/
    │   ├── wout_*.nc
    │   └── vmec2000.log
    └── jvmec/
        └── jvmec.log
```

Output files are generated in structured formats compatible with the Fortran benchmark suite.

## What Gets Compared

### Global Equilibrium Quantities
- MHD Energy (wb)
- Beta values (betatotal)
- Aspect ratio
- Magnetic axis position (raxis_cc)
- Plasma volume (volume_p)
- Edge rotational transform (iotaf_edge)

### Force-Related Quantities
- Average force (avforce)
- J·B current-field alignment (jdotb)
- B·∇v field-velocity coupling (bdotgradv)

### Geometric Properties
- Flux surface shapes via Fourier coefficients (rmnc, zmns)
- Mode numbers (xm, xn)
- Toroidal flux profile (phi)

## Implementation Details

### Repository Management
The Fortran benchmark suite includes a repository manager that handles:

- **VMEC++**: `git clone https://github.com/itpplasma/vmecpp.git`
- **Educational VMEC**: `git clone https://github.com/hiddenSymmetries/educational_VMEC.git`
- **VMEC2000**: `git clone https://github.com/hiddenSymmetries/VMEC2000.git`
- **jVMEC**: Manual setup required (private repository)

Repository management is handled through the `repository_manager` module with proper error handling and status reporting.

### Build Process
The Fortran benchmark suite automatically manages the build process for different VMEC implementations:
- **VMEC++**: Python package with C++ backend
- **Educational VMEC**: CMake + Make (Fortran)
- **VMEC2000**: Python package with Fortran backend
- **jVMEC**: Maven compile (Java)

Use `fpm run vmec-build` to automatically clone and build all available implementations.

### Input Format Handling
The Fortran benchmark suite handles input format conversion between different VMEC implementations:
- JSON format (VMEC++)
- INDATA format (Educational VMEC, VMEC2000)
- Input parameter conversion and validation
- Boundary coefficient handling (RBC, ZBS, RBS, ZBC)
- Profile data management (pressure, current, iota)

## Error Handling

- **Missing Dependencies**: Clear error messages with installation instructions
- **Build Failures**: Detailed build logs saved to output directory
- **Runtime Errors**: 5-minute timeout per test case with graceful continuation
- **Missing Repositories**: Auto-clone if enabled, skip if disabled

## Validation Use Cases

### Algorithm Development
Compare enhanced algorithms against reference implementations to verify:
- Physics accuracy (global quantities should match)
- Numerical improvements (better convergence, robustness)
- Force calculation consistency

### Regression Testing
Ensure code changes don't break core functionality:
- Run before/after major changes
- Automated CI/CD integration possible
- Cross-implementation verification

### Research Validation
Verify new physics models or numerical methods:
- Compare against established implementations
- Quantify improvements in accuracy/stability
- Generate publication-ready comparison data

## Example Results

The system generates tables like:

| case | implementation | wb | aspect | raxis_cc |
|------|---------------|----|---------|---------| 
| solovev | vmecpp | 1.234e-03 | 6.107 | 9.997e-01 |
| solovev | educational | 1.234e-03 | 6.107 | 9.997e-01 |
| solovev | vmec2000 | 1.234e-03 | 6.107 | 9.997e-01 |

And detailed analysis of relative differences, convergence properties, and error conditions.

## Development

### Package Structure
```
app/              # Executable sources
├── main.f90      # Main benchmark application
└── vmec-build.f90 # VMEC repository builder

src/              # Library sources
├── vmec_benchmark_types.f90       # Core data types
├── vmec_implementation_base.f90   # Base class for implementations
├── educational_vmec_implementation.f90
├── vmec2000_implementation.f90
├── vmecpp_implementation.f90
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