#!/usr/bin/env bash
# Submit reproducible bounded arrays for an exhaustive benchmark case list.
#
# Usage:
#   tools/submit_slurm_case_arrays.sh CASE_LIST IMPLEMENTATION [...]
#
# CASE_LIST must contain one stable path suffix per line.  Generate it from
# the exact `list-cases` discovery output for the checkout under test.  Each
# implementation gets an independent output tree and Slurm array.
set -euo pipefail

if [[ $# -lt 2 ]]; then
    printf 'usage: %s CASE_LIST IMPLEMENTATION [...]\n' "$0" >&2
    exit 2
fi

case_list=$1
shift
[[ -r "$case_list" ]] || {
    printf 'case list is not readable: %s\n' "$case_list" >&2
    exit 2
}

cases_per_task=${BENCHMARK_CASES_PER_TASK:-4}
concurrency=${BENCHMARK_ARRAY_CONCURRENCY:-32}
output_root=${BENCHMARK_ARRAY_OUTPUT_ROOT:-}
repo_root=$(git rev-parse --show-toplevel)

[[ "$cases_per_task" =~ ^[1-9][0-9]*$ ]] || {
    printf 'BENCHMARK_CASES_PER_TASK must be a positive integer\n' >&2
    exit 2
}
[[ "$concurrency" =~ ^[1-9][0-9]*$ ]] || {
    printf 'BENCHMARK_ARRAY_CONCURRENCY must be a positive integer\n' >&2
    exit 2
}

case_count=$(awk '!/^[[:space:]]*(#|$)/ {count++} END {print count+0}' "$case_list")
((case_count > 0)) || {
    printf 'case list has no active entries: %s\n' "$case_list" >&2
    exit 2
}
task_count=$(( (case_count + cases_per_task - 1) / cases_per_task ))

export_args="ALL,BENCHMARK_CASE_LIST=$case_list,BENCHMARK_CASES_PER_TASK=$cases_per_task"
if [[ -n "$output_root" ]]; then
    export_args+=",BENCHMARK_ARRAY_OUTPUT_ROOT=$output_root"
fi

for implementation in "$@"; do
    printf 'Submitting %s: %d cases, %d tasks, concurrency %d\n' \
        "$implementation" "$case_count" "$task_count" "$concurrency"
    sbatch --array="0-$((task_count - 1))%$concurrency" \
        --export="$export_args,BENCHMARK_IMPLEMENTATION=$implementation" \
        "$repo_root/tools/run_slurm_case_array.sbatch"
done
