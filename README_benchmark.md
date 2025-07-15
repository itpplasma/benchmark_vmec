# VMEC Benchmark Suite

A comprehensive benchmarking framework for comparing different VMEC (Variational Moments Equilibrium Code) implementations.

## Features

- **Modular Architecture**: Clean separation of concerns with dedicated modules for repository management, implementation wrappers, benchmark execution, and results comparison
- **Automatic Repository Management**: Clone and update VMEC repositories with a single command
- **Multiple Implementation Support**:
  - Educational VMEC
  - VMEC2000 (SIMSOPT style)
  - VMEC++
  - jVMEC (if available)
- **Flexible Test Case Discovery**: Automatically finds test cases from cloned repositories
- **Comprehensive Comparison**: Generates detailed reports comparing key physics quantities
- **CLI Interface**: Easy-to-use command-line interface for all operations

## Installation

```bash
# Clone this repository
git clone https://github.com/yourusername/vmec-benchmark.git
cd vmec-benchmark

# Install in development mode
pip install -e .

# Or install with development dependencies
pip install -e ".[dev]"
```

## Quick Start

1. **Setup repositories** (clone all VMEC implementations):
   ```bash
   vmec-benchmark setup
   ```

2. **Run benchmarks**:
   ```bash
   vmec-benchmark run
   ```

3. **View results**:
   - Check `benchmark_results/comparison_report.md` for the full report
   - CSV files are also generated for further analysis

## Usage

### Setup Repositories

Clone all configured VMEC repositories:
```bash
vmec-benchmark setup --base-dir ./vmec_repos
```

Force re-clone (useful if repositories are corrupted):
```bash
vmec-benchmark setup --force
```

### Run Benchmarks

Run all test cases on all implementations:
```bash
vmec-benchmark run
```

Run specific implementations:
```bash
vmec-benchmark run -i educational_vmec -i vmec2000
```

Run specific test cases:
```bash
vmec-benchmark run -c input.circular_tokamak -c input.stellarator
```

Limit number of test cases:
```bash
vmec-benchmark run --limit 5
```

Set custom timeout:
```bash
vmec-benchmark run --timeout 600  # 10 minutes per case
```

### List Available Resources

List repository status:
```bash
vmec-benchmark list-repos
```

List available test cases:
```bash
vmec-benchmark list-cases
```

### Update Repositories

Update all cloned repositories to latest version:
```bash
vmec-benchmark update
```

## Output Structure

After running benchmarks, the output directory contains:

```
benchmark_results/
├── comparison_report.md       # Comprehensive comparison report
├── comparison_table.csv       # Key quantities comparison
├── convergence_summary.csv    # Which cases converged
├── raw_results.json          # Complete results data
└── <test_case>/              # Per-case results
    ├── educational_vmec/     # Implementation-specific outputs
    │   ├── wout_*.nc
    │   └── educational_vmec.log
    ├── vmec2000/
    └── ...
```

## Architecture

The package is organized into several modules:

- **`repository.py`**: Manages cloning and updating Git repositories
- **`implementations/`**: Wrappers for each VMEC implementation
  - `base.py`: Abstract base class
  - `educational.py`: Educational VMEC wrapper
  - `vmec2000.py`: VMEC2000 wrapper
  - `vmecpp.py`: VMEC++ wrapper
  - `jvmec.py`: jVMEC wrapper
- **`runner.py`**: Orchestrates benchmark execution
- **`comparator.py`**: Analyzes and compares results
- **`cli.py`**: Command-line interface

## Development

### Running Tests

```bash
pytest tests/
```

### Code Formatting

```bash
black src/
flake8 src/
```

### Type Checking

```bash
mypy src/
```

## Requirements

- Python 3.8+
- CMake (for building Educational VMEC)
- Maven (for building jVMEC, optional)
- Git

## License

MIT License - see LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.