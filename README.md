# VMEC Implementation Benchmark Suite

[![CI](https://github.com/itpplasma/benchmark_vmec/actions/workflows/ci.yml/badge.svg)](https://github.com/itpplasma/benchmark_vmec/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/itpplasma/benchmark_vmec/branch/main/graph/badge.svg)](https://codecov.io/gh/itpplasma/benchmark_vmec)

[GitHub repository](https://github.com/itpplasma/benchmark_vmec)

This repository runs an ordinary, non-differentiable benchmark for magnetic
equilibrium codes. It discovers cases, runs every available implementation,
compares common quantities, and records successful, failed, and unsupported
rows.

## Coverage

The corpus contains 344 analytical and numerical cases in 1-D, 2-D, and 3-D.
It covers these twelve implementations:

- VMEC-like: `educational_vmec`, `jVMEC`, `VMEC2000`, `VMEC++`, `VMEX`,
  `PARVMEC`
- Nested-surface: `DESC`, `GVEC`
- MRxMHD: `SPEC`, `SPECTRE`
- 2-D Grad-Shafranov: `FreeGS`, `CHEASE`

FreeGS and CHEASE run only on supported 2-D inputs. The differentiable MHD
benchmark is maintained separately. Optional sibling repositories are expected
one directory above this checkout. Missing repositories are recorded as
unavailable. `setup` clones those repositories recursively, including their
tracked test inputs. The benchmark-owned cases under `cases/` are versioned in
this repository. Files that are not tracked by either source must be provisioned
separately.

## TC24 matched-equilibrium bridge

- This repository owns the ordinary all-implementation benchmark. The [differentiable benchmark](https://gitlab.tugraz.at/plasma/proj/stel/mhd-differentiable) separately owns derivative and optimization comparisons.
- The [TC24 PLAN](https://gitlab.tugraz.at/plasma/proj/ntv/iter_tc24/-/blob/main/PLAN.md) and [case contract](https://gitlab.tugraz.at/plasma/proj/ntv/iter_tc24/-/blob/main/equilibrium/CASE_CONTRACT.md) own the current equilibrium-first cases, signed physical inputs and run registry.
- Reuse wrappers and format adapters after checking exact boundary/profile/flux laws, source revisions and conventions. Common scalar output or a successful process does not establish a matched physical problem.
- Historical FreeGS rows are operational probes: `tools/run_freegs.py` chooses hard-coded geometry/profiles by filename rather than reading the supplied physical input. They are not matched FreeGS/VMEC physics comparisons.
- The archived table preserves reported outcomes; native convergence is separate in `plots/quality.csv`. [Issue #1](https://github.com/itpplasma/benchmark_vmec/issues/1) tracks status and timing distinctions. The retained archive has scalar/quality exports and figures, not native states/logs or complete source/input manifests.
- Add admitted ordinary cases and reusable gates here; retain TC24 campaign authority there. Do not import a fitted solver state as an independent force reference or rerun the full historical corpus to establish a new focused case.

## Quick start

```bash
fpm build
fpm test

fpm run --target vmec-benchmark -- setup --base-dir ..
fpm run --target vmec-build -- --base-dir ..
fpm run --target vmec-benchmark -- run --base-dir ..
```

Useful discovery and focused-run commands:

```bash
fpm run --target vmec-benchmark -- list-repos --base-dir ..
fpm run --target vmec-benchmark -- list-cases --match tokamak
fpm run --target vmec-benchmark -- run --match tokamak --limit 5
```

Results are written to `benchmark_results/` with CSV and Markdown summaries,
native outputs, and adapter sidecars.

The curated exhaustive result is in `results/ordinary-0cf8e2c/`: 4,128 rows
covering all 344 cases and twelve implementations, together with final metric,
quality, runtime, boxplot, and boundary figures. Binary figures use Git LFS.

## Format adapters

The scripts in `tools/` keep conversions explicit and reproducible. Use
`convert_equilibrium.py` for VMEC, JSON, GEQDSK, and SPEC metadata. Use
`convert_vmec_to_gvec.py` and `convert_vmec_to_spectre.py` for GVEC and SPECTRE
inputs. Use `convert_gvec_to_common.py` for GVEC metrics, `run_freegs.py` for
2-D FreeGS plus GEQDSK, and `run_spectre.py` for native SPECTRE JSON.

CHEASE consumes the native GEQDSK wrapper. Use `uv run` for Python tools:

```bash
uv run python tools/convert_equilibrium.py --help
uv run python tools/convert_vmec_to_gvec.py input.example gvec.yaml
uv run python tools/convert_vmec_to_spectre.py input.example spectre.toml
```

These adapters transfer ordinary formats. They do not expose automatic
differentiation or Jacobian data.

## Plots

Plot completed Slurm results with:

```bash
uv run --with netCDF4 --with h5py --with matplotlib \
  python tools/plot_benchmark_results.py benchmark_results-slurm-<job-id>
```

The `plots/` directory contains:

- `metrics.png`: relative scalar agreement
- `quality.png` and `quality.csv`: native residual and convergence diagnostics
- `boxplots.png` and `boxplots.csv`: one box-and-whisker panel per scalar and runtime
- `runtime.png` and `runtime.csv`: code-reported timing distributions
- `surfaces*.png`: boundary overlays

Boxplots show the median, IQR, 1.5×IQR whiskers, and fliers from emitted
successful outputs. Missing diagnostics remain blank. Reported runtime is code
timing, not end-to-end Slurm wall time.

## Layout

```text
app/       command-line entry points
src/       benchmark runner and implementation wrappers
cases/     analytical and numerical 1-D, 2-D, and 3-D fixtures
tools/     format adapters and plotting scripts
test/      independent Fortran tests
```

Add implementations through a wrapper in `src/`, register it with the runner,
and add an independent test. Preserve native outputs and explicit failure or
unsupported records.

## License

MIT. Sibling implementations may use different licenses.
