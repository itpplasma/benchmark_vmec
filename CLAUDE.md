# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Reference Implementation Decision for Asymmetric VMEC

- **Primary Reference**: jVMEC - most up-to-date with bugfixes and optimizations
- **Secondary Reference**: educational_VMEC - for additional insight, not strict matching required
- **Target**: VMEC++ asymmetric implementation should match jVMEC exactly

jVMEC has been identified as the most reliable reference for asymmetric VMEC implementation due to:
- More recent development and bug fixes
- Better maintained and optimized code
- More robust handling of edge cases
- educational_VMEC serves as supplementary information only

## Essential Commands

### Build and Development
```bash
# Build the project
fpm build

# Build in debug mode
fpm build --profile debug

# Run tests
fpm test

# Run specific test
fpm test test_vmec_types
fpm test test_repository_manager
```

### VMEC Operations
```bash
# Build all VMEC implementations (separated command)
fpm run vmec-build

# Run benchmarks on all implementations
fpm run vmec-benchmark

# Run with limited test cases
fpm run vmec-benchmark -- run --limit 5

# List available test cases
fpm run vmec-benchmark -- list-cases

# Include jVMEC test cases (excluded by default)
BENCHMARK_INCLUDE_JVMEC=1 fpm run vmec-benchmark -- run

# Show help
fpm run vmec-benchmark -- --help
```

## Architecture Overview

This is a Fortran package that benchmarks multiple VMEC (Variational Moments Equilibrium Code) implementations by comparing their outputs on identical physics problems. The architecture follows a plugin-based design where each VMEC implementation has its own handler module.

### Core Architecture

**Two-Phase Design**: The system is built around cleanly separated build and execution phases:
- `vmec-build`: Clones and builds VMEC implementations 
- `vmec-benchmark`: Runs benchmarks on built implementations

**Plugin Pattern**: Each VMEC implementation extends `vmec_implementation_base` with three required methods:
- `build()`: Build the implementation from source
- `run_case()`: Execute a single test case
- `extract_results()`: Parse output files into standardized format

**Repository Management**: The `repository_manager` automatically clones and manages external VMEC repositories in `vmec_repos/` directory.

### Key Modules

- **`vmec_implementation_base`**: Abstract base class defining the interface all implementations must follow
- **`benchmark_runner`**: Orchestrates test execution across all implementations
- **`repository_manager`**: Handles cloning and path management of external repositories
- **Implementation modules**: `educational_vmec_implementation.f90`, `vmecpp_implementation.f90`, `vmec2000_implementation.f90`, `jvmec_implementation.f90`

### VMEC Implementation Specifics

Each VMEC implementation has unique build/run requirements:

**Educational VMEC**: 
- Builds with CMake/Make
- Requires submodule initialization (json-fortran, abscab-fortran)
- Expects INDATA format input files
- Produces NetCDF output files (wout_*.nc)

**VMEC++**:
- Builds standalone C++ executable via CMake
- Requires JSON format input files (automatically detected)
- Produces HDF5 output files (*.out.h5)

**VMEC2000**:
- Python package with Fortran backend
- Installs via pip with numpy/mpi4py dependencies
- Expects INDATA format input files
- Produces NetCDF output files

**jVMEC**:
- Java implementation built with Maven
- Test framework designed for regression testing, not a standalone executable
- Cannot process arbitrary input files like other implementations
- Test cases from jVMEC are excluded by default to reduce noise
- Private repository, manual setup required

### Input Format Handling

The system handles format conversion automatically:
- VMEC++ expects JSON files, looks for corresponding `.json` files when given INDATA input
- Other implementations use standard VMEC INDATA format
- Test cases are discovered from repository test data directories

### Data Flow

1. **Discovery**: `benchmark_runner` discovers test cases from implementation repositories
2. **Setup**: Each implementation's `build()` method is called to ensure it's ready
3. **Execution**: For each test case, `run_case()` is called on each implementation
4. **Extraction**: `extract_results()` parses output files into standardized format
5. **Reporting**: Results are compared and formatted into reports

### Output Structure

Results are saved to `benchmark_results/` with per-implementation subdirectories containing logs and output files. The system generates comparison reports and CSV data for analysis.

## Adding New VMEC Implementations

1. Create new module extending `vmec_implementation_base`
2. Implement the three required methods (`build`, `run_case`, `extract_results`)
3. Add to `benchmark_runner` imports and implementation setup
4. Add to `vmec-build.f90` for build support
5. Write unit tests in `test/` directory

## Important Notes

- The system manages external repositories automatically - avoid manual modification of `vmec_repos/`
- Build and run phases are intentionally separated for reliability
- Each implementation handles its own input format requirements
- Output comparison focuses on physics quantities (MHD energy, beta values, etc.)
- The system is designed for cross-platform compatibility (Linux/macOS)