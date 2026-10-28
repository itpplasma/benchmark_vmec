# benchmark_vmec

Benchmark of magnetic equilibrium codes. It discovers test cases, runs every
available implementation on them, compares common output quantities and
records each run as successful, failed or unsupported. Derivative and
optimisation comparisons are kept in a separate differentiable benchmark.

[![CI](https://github.com/itpplasma/benchmark_vmec/actions/workflows/ci.yml/badge.svg)](https://github.com/itpplasma/benchmark_vmec/actions/workflows/ci.yml)

## Coverage

The corpus contains 344 analytical and numerical 1-D, 2-D and 3-D cases and
twelve implementations:

- VMEC-like: `educational_vmec`, `jVMEC`, `VMEC2000`, `VMEC++`, `VMEX`,
  `PARVMEC`
- Nested surfaces: `DESC`, `GVEC`
- MRxMHD: `SPEC`, `SPECTRE`
- 2-D Grad-Shafranov: `FreeGS`, `CHEASE` (2-D inputs only)

Most cases are the test inputs of the implementations' own repositories; the
cases under `cases/` belong to this benchmark. The implementations are cloned
as sibling repositories one directory above this checkout; missing ones are
recorded as unavailable.

## Building

Requirements: [fpm](https://fpm.fortran-lang.org), a Fortran compiler, NetCDF
and HDF5 (Fortran libraries), and [uv](https://docs.astral.sh/uv/) for the
Python tools.

    fpm build
    fpm test

## Usage

    fpm run --target vmec-benchmark -- setup --base-dir ..   # clone implementations
    fpm run --target vmec-build -- --base-dir ..             # build them
    fpm run --target vmec-benchmark -- run --base-dir ..     # run all cases

Focused runs and discovery:

    fpm run --target vmec-benchmark -- list-repos --base-dir ..
    fpm run --target vmec-benchmark -- list-cases --match tokamak
    fpm run --target vmec-benchmark -- run --match tokamak --limit 5
    fpm run --target vmec-benchmark -- run --impl parvmec
    fpm run --target vmec-benchmark -- --help

Results are written to `benchmark_results/`: CSV and Markdown summaries, the
native outputs of each code and adapter sidecar files.

## Results

The full run over all 344 cases and twelve implementations (4,128 rows) is in
[results/ordinary-0cf8e2c/](results/ordinary-0cf8e2c/), with plots of scalar
agreement, convergence quality, runtime and boundary shapes. See
[docs/results.md](docs/results.md) for what the table and plots contain and
how to interpret them.

## Layout

    app/       command-line entry points
    src/       benchmark runner and implementation wrappers
    cases/     benchmark-owned analytical and numerical cases
    tools/     format adapters, plotting and Slurm scripts
    test/      Fortran tests

## Documentation

- [docs/results.md](docs/results.md): archived results and plots
- [docs/tools.md](docs/tools.md): format adapters and plotting
- [docs/contributing.md](docs/contributing.md): adding implementations, pull
  requests and merging

## License

MIT, see the `license` field in `fpm.toml`. The benchmarked implementations
have their own licenses.
