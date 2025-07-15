# VMEC Benchmark Suite (Fortran Version)

A comprehensive benchmarking framework for comparing different VMEC (Variational Moments Equilibrium Code) implementations, written in modern Fortran.

## Features

- **Modular Architecture**: Clean separation of concerns with dedicated modules
- **Automatic Repository Management**: Clone and update VMEC repositories
- **Multiple Implementation Support**:
  - Educational VMEC
  - VMEC2000 (SIMSOPT style)
  - VMEC++
  - jVMEC (if available)
- **Flexible Test Case Discovery**: Automatically finds test cases
- **Comprehensive Comparison**: Generates detailed reports
- **Modern Fortran**: Uses Fortran 2008+ features

## Building

This project uses the Fortran Package Manager (fpm). To build:

```bash
fpm build --profile release
```

## Installation

```bash
fpm install --prefix ~/.local
```

This will install the `vmec-benchmark` executable to `~/.local/bin`.

## Usage

### Setup Repositories

Clone all configured VMEC repositories:
```bash
vmec-benchmark setup --base-dir ./vmec_repos
```

Force re-clone:
```bash
vmec-benchmark setup --force
```

### Run Benchmarks

Run all test cases:
```bash
vmec-benchmark run
```

With options:
```bash
vmec-benchmark run --limit 5 --timeout 600
```

### List Available Resources

List repositories:
```bash
vmec-benchmark list-repos
```

List test cases:
```bash
vmec-benchmark list-cases
```

### Update Repositories

```bash
vmec-benchmark update
```

## Architecture

### Core Modules

- **`vmec_benchmark_types`**: Common type definitions
- **`repository_manager`**: Git repository management
- **`vmec_implementation_base`**: Abstract base class for implementations
- **`educational_vmec_implementation`**: Educational VMEC wrapper
- **`benchmark_runner`**: Orchestrates benchmark execution
- **`results_comparator`**: Analyzes and compares results

### Directory Structure

```
.
├── fpm.toml                 # Package configuration
├── app/
│   └── main.f90            # CLI application
├── src/
│   ├── vmec_benchmark_types.f90
│   ├── repository_manager.f90
│   ├── vmec_implementation_base.f90
│   ├── educational_vmec_implementation.f90
│   ├── benchmark_runner.f90
│   └── results_comparator.f90
├── test/
│   ├── test_vmec_types.f90
│   └── test_repository_manager.f90
└── doc/
    └── README.md
```

## Testing

Run tests with:
```bash
fpm test
```

## Dependencies

- Fortran compiler (gfortran, ifort, etc.)
- Fortran Package Manager (fpm)
- CMake (for building Educational VMEC)
- Git
- JSON-Fortran (automatically handled by fpm)
- M_CLI2 (automatically handled by fpm)

## Output

Results are saved to the specified output directory:
- `comparison_report.md`: Markdown report
- `comparison_table.csv`: CSV data
- Individual case results in subdirectories

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests
5. Submit a pull request

## License

MIT License