#!/usr/bin/env bash
#SBATCH --job-name=vmecpp-canonical
#SBATCH --partition=compute
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=2:00:00
#SBATCH --output=slurm-%x-%j.out
#SBATCH --error=slurm-%x-%j.err

set -u

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=${SLURM_SUBMIT_DIR:-$(cd -- "$script_dir/.." && pwd)}
base_dir=${BENCHMARK_BASE_DIR:-$(dirname "$repo_root")}
output_dir=${BENCHMARK_OUTPUT_DIR:-"$repo_root/benchmark_results-vmecpp-canonical-${SLURM_JOB_ID:-local}"}
timeout_seconds=${BENCHMARK_TIMEOUT:-600}
python_cmd="$base_dir/vmecpp/.venv/bin/python"

export PATH="$HOME/.local/bin:$PATH"
for runtime_lib_dir in \
    "$HOME/.local/openblas/usr/lib/x86_64-linux-gnu/openblas-pthread" \
    "$HOME/.local/netcdff/usr/lib/x86_64-linux-gnu" \
    "/usr/lib/x86_64-linux-gnu/hdf5/serial"; do
    if [[ -d "$runtime_lib_dir" ]]; then
        export LD_LIBRARY_PATH="$runtime_lib_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    fi
done

[[ -x "$python_cmd" ]] || { echo "VMEC++ Python not found: $python_cmd" >&2; exit 1; }
"$python_cmd" -c 'import importlib.metadata, vmecpp; print("VMEC++", importlib.metadata.version("vmecpp"))'

cases=(
    cases/analytic/1d_cylindrical/input.analytic_1d
    cases/analytic/2d_solovev/input.solovev
    cases/analytic/3d_quasisymmetric/input.qh_analytic
    cases/numerical/1d_profile/input.profile_1d
    cases/numerical/2d_tokamak/input.tokamak_2d
    cases/numerical/3d_w7x/input.w7x
)

mkdir -p "$output_dir"
failures=0
for relative_input in "${cases[@]}"; do
    input_file="$repo_root/$relative_input"
    case_dir="$output_dir/benchmark_vmec__${relative_input//\//__}"
    implementation_dir="$case_dir/vmecpp"
    mkdir -p "$implementation_dir"
    input_basename=$(basename "$relative_input")
    cp "$input_file" "$implementation_dir/$input_basename"
    echo "Running VMEC++ $relative_input"
    set +e
    (
        cd "$implementation_dir" || exit 1
        /usr/bin/time -p timeout "$timeout_seconds" "$python_cmd" - "$input_basename" wout_input.nc > vmecpp.log 2>&1 <<'PY'
import sys
import vmecpp

vmec_input = vmecpp.VmecInput.from_file(sys.argv[1])
vmec_input.return_outputs_even_if_not_converged = True
output = vmecpp.run(vmec_input, max_threads=1, verbose=False)
output.wout.save(sys.argv[2])
print("VMEC++ completed")
PY
    )
    status=$?
    set -u
    if [[ $status -eq 0 && -f "$implementation_dir/wout_input.nc" ]]; then
        echo "VMEC++ completed: $relative_input"
    else
        echo "VMEC++ failed ($status): $relative_input" >&2
        failures=$((failures + 1))
    fi
done

echo "VMEC++ canonical rerun complete: $(( ${#cases[@]} - failures ))/${#cases[@]} succeeded"
exit "$((failures > 0 ? 1 : 0))"
