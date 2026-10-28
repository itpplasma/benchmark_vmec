# Tools

The Python scripts in `tools/` convert between input and output formats so
that every code can run the same case. Run them with `uv`:

    uv run python tools/convert_equilibrium.py --help
    uv run python tools/convert_vmec_to_gvec.py input.example gvec.yaml
    uv run python tools/convert_vmec_to_spectre.py input.example spectre.toml

| Script | Purpose |
| --- | --- |
| `convert_equilibrium.py` | VMEC, JSON, GEQDSK and SPEC metadata |
| `convert_vmec_to_gvec.py` | VMEC input to GVEC parameter file |
| `convert_vmec_to_spectre.py` | VMEC input to SPECTRE input |
| `convert_gvec_to_common.py` | GVEC output to the common metrics |
| `run_freegs.py` | 2-D FreeGS run with GEQDSK output |
| `run_spectre.py` | SPECTRE run with native JSON output |
| `prepare_vmec_input.py` | VMEC input preparation |
| `plot_benchmark_results.py` | plots from a results directory |

CHEASE reads GEQDSK through its native wrapper. The adapters convert ordinary
file formats only; they provide no derivatives or Jacobians.

The `*.sh` and `*.sbatch` scripts run the benchmark as Slurm job arrays and
merge or recover their results; `build_parvmec.sh` and `parvmec_superbuild/`
build PARVMEC.
