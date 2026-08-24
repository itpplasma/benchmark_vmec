#!/usr/bin/env bash
# Run the ordinary benchmark from one reproducible Slurm allocation.
#
# Usage:
#   tools/run_slurm_benchmark.sh smoke
#   tools/run_slurm_benchmark.sh full
#
# The caller must stage this checkout and its sibling implementation repositories
# one directory below the selected base directory. Failed and unsupported rows
# remain in the report; a non-zero implementation build does not abort discovery.
set -euo pipefail

mode=${1:-full}
repo_root=$(git rev-parse --show-toplevel)
base_dir=${BENCHMARK_BASE_DIR:-$(dirname "$repo_root")}
output_dir=${BENCHMARK_OUTPUT_DIR:-"$repo_root/benchmark_results-slurm-${SLURM_JOB_ID:-local}"}
timeout_seconds=${BENCHMARK_TIMEOUT:-300}

export PATH="$HOME/.local/bin:$PATH"
export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-1}"
export OMP_DYNAMIC=false
export OMP_PLACES=cores
export OMP_PROC_BIND=spread

run_driver() {
    fo run vmec-benchmark -- "$@" --base-dir "$base_dir" --output-dir "$output_dir"
}

case "$mode" in
    smoke)
        fo check
        fo test --all
        run_driver list-repos
        run_driver list-cases --match 'cases/analytic/2d_solovev' --limit 1
        run_driver run --match 'cases/analytic/2d_solovev' --limit 1 --timeout "$timeout_seconds"
        ;;
    full)
        fo check
        run_driver list-repos
        run_driver list-cases
        run_driver run --timeout "$timeout_seconds"
        ;;
    *)
        printf 'usage: %s {smoke|full}\n' "$0" >&2
        exit 2
        ;;
esac
