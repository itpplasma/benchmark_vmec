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
# Batch shells do not load the interactive model-runtime environment.  `fo`
# delegates Fortran builds to any user-local fpm; select a stable installed
# runtime when fpm is not already on PATH.
if ! command -v fpm >/dev/null 2>&1; then
    for fpm_candidate in "$HOME"/.local/fortbench-runtime-py311/bin/fpm \
        "$HOME"/.local/fortbench-runtime-*/bin/fpm; do
        if [[ -x "$fpm_candidate" ]]; then
            PATH="$(dirname "$fpm_candidate"):$PATH"
            export PATH
            break
        fi
    done
fi
command -v fpm >/dev/null 2>&1 || {
    printf 'fpm is required by fo but was not found in PATH or ~/.local/fortbench-runtime-*\n' >&2
    exit 1
}
export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-1}"
export OMP_DYNAMIC=false
export OMP_PLACES=cores
export OMP_PROC_BIND=spread

driver=fo
prepare_driver() {
    # Prefer the repository-standard fo checks.  Some older cluster fpm builds
    # concatenate -pipe with pkg-config include flags; use the same fpm project
    # directly if that backend-specific failure is encountered.
    if fo check; then
        driver=fo
        if [[ "$mode" == smoke ]]; then
            fo test --all
        fi
    else
        printf 'fo check failed; retrying the same project through fpm\n' >&2
        fpm build
        if [[ "$mode" == smoke ]]; then
            fpm test
        fi
        driver=fpm
    fi
}

run_driver() {
    if [[ "$driver" == fo ]]; then
        fo run vmec-benchmark -- "$@" --base-dir "$base_dir" --output-dir "$output_dir"
    else
        fpm run --target vmec-benchmark -- "$@" --base-dir "$base_dir" --output-dir "$output_dir"
    fi
}

case "$mode" in
    smoke)
        prepare_driver
        run_driver list-repos
        run_driver list-cases --match 'cases/analytic/2d_solovev' --limit 1
        run_driver run --match 'cases/analytic/2d_solovev' --limit 1 --timeout "$timeout_seconds"
        ;;
    full)
        prepare_driver
        run_driver list-repos
        run_driver list-cases
        run_driver run --timeout "$timeout_seconds"
        ;;
    *)
        printf 'usage: %s {smoke|full}\n' "$0" >&2
        exit 2
        ;;
esac
