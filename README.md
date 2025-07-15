# VMEC Implementation Benchmark Suite

[![CI](https://github.com/itpplasma/benchmark_vmec/actions/workflows/ci.yml/badge.svg)](https://github.com/itpplasma/benchmark_vmec/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/itpplasma/benchmark_vmec/branch/main/graph/badge.svg)](https://codecov.io/gh/itpplasma/benchmark_vmec)

Automated comparison system for multiple VMEC implementations.

## Overview

This benchmark suite automatically clones, builds, and compares multiple VMEC implementations:

- **VMEC++** (https://github.com/itpplasma/vmecpp.git) - Modern C++ implementation with enhanced algorithms
- **Educational VMEC** (https://github.com/hiddenSymmetries/educational_VMEC.git) - Reference Fortran implementation
- **VMEC2000** (https://github.com/hiddenSymmetries/VMEC2000.git) - SIMSOPT-style Python interface to VMEC
- **jVMEC** - Java implementation (not publicly available)

## Quick Start

```bash
# Basic run with auto-cloning
python3 compare_vmec_implementations.py

# Custom paths
python3 compare_vmec_implementations.py \
    --vmecpp-path ./my_vmecpp \
    --educational-path ./my_educational_vmec \
    --vmec2000-path ./my_vmec2000 \
    --output-path ./benchmark_results
```

## Features

- **Automatic Setup**: Auto-clones and builds missing repositories
- **Cross-Platform**: Works on Linux/macOS with standard build tools
- **Comprehensive Testing**: Runs all available test cases from implementations
- **Detailed Analysis**: Compares global quantities, force calculations, and convergence
- **Professional Output**: Markdown reports, CSV data, visualization plots

## Requirements

### System Dependencies
- Python 3.8+
- Git
- CMake (for educational_VMEC)
- Make/GCC (for educational_VMEC)
- Maven + Java 8+ (for jVMEC, optional)

### Python Dependencies
```bash
pip install numpy matplotlib pandas netcdf4
```

## Usage Examples

### Default behavior (auto-clone everything):
```bash
python3 compare_vmec_implementations.py
```

### Disable auto-cloning:
```bash
python3 compare_vmec_implementations.py --no-auto-clone
```

### Custom repository locations:
```bash
python3 compare_vmec_implementations.py \
    --vmecpp-path /path/to/vmecpp \
    --educational-path /path/to/educational_VMEC \
    --vmec2000-path /path/to/VMEC2000 \
    --jvmec-path /path/to/jVMEC \
    --output-path ./results
```

## Output Structure

```
vmec_comparison_results/
├── comparison_report.md           # Main summary report
├── comparison_table.csv           # Numerical comparison data
├── raw_results.json              # Complete raw results
└── {test_case}/                  # Per-case detailed results
    ├── vmecpp/
    │   ├── vmecpp_results.json
    │   └── vmecpp.log
    ├── educational/
    │   ├── wout_*.nc
    │   ├── jxbout_*.nc
    │   └── educational_vmec.log
    ├── vmec2000/
    │   ├── wout_*.nc
    │   └── vmec2000.log
    └── jvmec/
        └── jvmec.log
```

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

### Auto-cloning Strategy
The system checks for repository existence and auto-clones if enabled:

- **VMEC++**: `git clone https://github.com/itpplasma/vmecpp.git`
- **Educational VMEC**: `git clone https://github.com/hiddenSymmetries/educational_VMEC.git`
- **VMEC2000**: `git clone https://github.com/hiddenSymmetries/VMEC2000.git`
- **jVMEC**: No auto-clone (not public), must exist locally

### Build Process
- **VMEC++**: `pip install -e .` (builds C++ automatically)
- **Educational VMEC**: CMake + Make
- **VMEC2000**: `pip install -e .` (installs Fortran VMEC)
- **jVMEC**: Maven compile

### Input Format Handling
The system automatically converts VMEC++ JSON inputs to INDATA format for Fortran-based implementations, handling:
- Basic parameters (LASYM, NFP, MPOL, NTOR)
- Arrays (NS_ARRAY, FTOL_ARRAY, NITER_ARRAY)
- Profiles (pressure, current, iota)
- Boundary coefficients (RBC, ZBS, RBS, ZBC)

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

## Contributing

To add support for new VMEC implementations:

1. Create a new class inheriting from `VMECImplementation`
2. Implement `build()`, `run_case()`, and `extract_results()` methods
3. Add to the `implementations` dictionary in `VMECComparator`
4. Test with existing test cases

## License

This benchmark suite is provided under the same license terms as the individual VMEC implementations being compared.