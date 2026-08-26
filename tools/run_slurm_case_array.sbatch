#!/usr/bin/env bash
# Run a bounded slice of an exhaustive case list in one isolated Slurm job.
#
# BENCHMARK_CASE_LIST contains one stable path suffix per line.  A suffix is
# matched against the discovered source path, so it remains valid when the
# launcher unpacks the benchmark checkout in a job-local temporary directory.
# One task runs BENCHMARK_CASES_PER_TASK cases sequentially and writes each
# result under BENCHMARK_ARRAY_OUTPUT_ROOT/<implementation>/<case-slug>.
#
# The list is deliberately external to the repository: it is generated from
# the exact discovery output of the checkout being benchmarked.  This avoids
# silently changing the corpus while a long array is queued.
#
# Usage is normally through submit_slurm_case_arrays.sh.
# shellcheck shell=bash
#SBATCH --job-name=vmec-case-array
#SBATCH --partition=compute
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=04:00:00
#SBATCH --output=slurm-%x-%A_%a.out
#SBATCH --error=slurm-%x-%A_%a.err

set -euo pipefail

if [[ -n "${SLURM_SUBMIT_DIR:-}" ]]; then
    repo_root=$(cd -- "$SLURM_SUBMIT_DIR" && pwd)
else
    script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
    repo_root=$(cd -- "$script_dir/.." && pwd)
fi

case_list=${BENCHMARK_CASE_LIST:?BENCHMARK_CASE_LIST is required}
implementation=${BENCHMARK_IMPLEMENTATION:?BENCHMARK_IMPLEMENTATION is required}
cases_per_task=${BENCHMARK_CASES_PER_TASK:-4}
array_output_root=${BENCHMARK_ARRAY_OUTPUT_ROOT:-"$repo_root/benchmark_results-array-${SLURM_ARRAY_JOB_ID:-${SLURM_JOB_ID:-local}}"}
base_dir=${BENCHMARK_BASE_DIR:-$(dirname "$repo_root")}
timeout_seconds=${BENCHMARK_TIMEOUT:-600}

[[ -r "$case_list" ]] || {
    printf 'case list is not readable: %s\n' "$case_list" >&2
    exit 2
}
[[ "$cases_per_task" =~ ^[1-9][0-9]*$ ]] || {
    printf 'BENCHMARK_CASES_PER_TASK must be a positive integer\n' >&2
    exit 2
}

first_line=$(( ${SLURM_ARRAY_TASK_ID:-0} * cases_per_task + 1 ))
last_line=$((first_line + cases_per_task - 1))
case_no=0

slugify() {
    # Keep paths recognizable while making them safe as directory names.
    local digest readable
    digest=$(printf '%s' "$1" | sha256sum | cut -c1-12)
    readable=$(printf '%s' "$1" | sed -e 's#^/##' -e 's#[^A-Za-z0-9._-][^A-Za-z0-9._-]*#_#g' | cut -c1-150)
    printf '%s_%s' "$readable" "$digest"
}

run_case() {
    local case_match=$1
    local slug output_dir
    slug=$(slugify "$case_match")
    output_dir="$array_output_root/$implementation/$slug"
    mkdir -p "$output_dir"
    export BENCHMARK_BASE_DIR="$base_dir"
    export BENCHMARK_CASE_LIST="$case_list"
    export BENCHMARK_IMPLEMENTATION="$implementation"
    export BENCHMARK_MATCH="$case_match"
    export BENCHMARK_OUTPUT_DIR="$output_dir"
    export BENCHMARK_TIMEOUT="$timeout_seconds"
    # Reuse one source/build tree for the sequential cases in this task.  No
    # other task shares it, so this remains isolated from all parallel Fo jobs.
    export BENCHMARK_ISOLATED_REPO="${TMPDIR:-/tmp}/benchmark_vmec-case-array-${SLURM_JOB_ID:-local}"

    if [[ "$implementation" == parvmec ]]; then
        "$repo_root/tools/run_parvmec_slurm.sh" full
    else
        "$repo_root/tools/run_slurm_benchmark.sh" full
    fi
}

while IFS= read -r case_match; do
    # The list format permits comments and blank lines without changing array
    # indexing.  They are ignored after the selected range is read.
    [[ -z "${case_match//[[:space:]]/}" || "$case_match" == \#* ]] && continue
    case_no=$((case_no + 1))
    if ((case_no < first_line)); then
        continue
    fi
    if ((case_no > last_line)); then
        break
    fi
    run_case "$case_match"
done < "$case_list"
