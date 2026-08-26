#!/usr/bin/env bash
# Build and run only PARVMEC in an isolated benchmark output tree.  This is
# intended for use beside (not as a dependency of) the exhaustive Slurm job.
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
base_dir=${BENCHMARK_BASE_DIR:-$(dirname "$repo_root")}
output_dir=${BENCHMARK_OUTPUT_DIR:-"$repo_root/benchmark_results-parvmec-${SLURM_JOB_ID:-local}"}
build_dir=${PARVMEC_BUILD_DIR:-"$base_dir/parvmec-build-${SLURM_JOB_ID:-local}"}

export BENCHMARK_BASE_DIR="$base_dir"
export PARVMEC_BUILD_DIR="$build_dir"
"$repo_root/tools/build_parvmec.sh"
parvmec_executable=$(<"$build_dir/executable.path")
[[ -x "$parvmec_executable" ]] || {
    printf 'PARVMEC executable is not runnable: %s\n' "$parvmec_executable" >&2
    exit 1
}
export VMEC_BENCHMARK_PARVMEC="$parvmec_executable"
export BENCHMARK_IMPLEMENTATION=parvmec
export BENCHMARK_OUTPUT_DIR="$output_dir"
export BENCHMARK_TIMEOUT=${BENCHMARK_TIMEOUT:-600}

# The generic launcher can index a whole staged stack, which is needlessly
# expensive when the exhaustive run is writing results beside this job.  Build
# a narrow, reusable index from source/case trees only; PARVMEC does not need
# any files from another implementation's result directory.
mgrid_index="$build_dir/mgrid-index.txt"
if [[ ! -s "$mgrid_index" ]]; then
    mgrid_index_tmp="${mgrid_index}.tmp.$$"
    find -L "$repo_root/cases" \
        "$base_dir/PARVMEC" "$base_dir/educational_VMEC" "$base_dir/VMEC2000" \
        "$base_dir/vmecpp" "$base_dir/VMEX" "$base_dir/DESC" "$base_dir/gvec" \
        -type f -iname 'mgrid*' -print 2>/dev/null > "$mgrid_index_tmp" || true
    mv -f "$mgrid_index_tmp" "$mgrid_index"
fi
export VMEC_BENCHMARK_MGRID_INDEX="$mgrid_index"

exec "$repo_root/tools/run_slurm_benchmark.sh" "${BENCHMARK_MODE:-full}"
