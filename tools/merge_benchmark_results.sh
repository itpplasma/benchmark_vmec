#!/usr/bin/env bash
# Merge standard or case-array benchmark result trees.
#
# Usage:
#   tools/merge_benchmark_results.sh DEST SOURCE [...]
#
# Sources are applied in argument order; a later source replaces the same
# case/implementation directory from an earlier source.  Case-array sources
# may contain one report root per Slurm task, while ordinary runs have one
# report root.  Only implementation directories below report roots are copied,
# so transient plots and aggregate CSV files never contaminate the merged tree.
set -euo pipefail

if [[ $# -lt 2 ]]; then
    printf 'usage: %s DEST SOURCE [...]\n' "$0" >&2
    exit 2
fi

destination=$1
shift
mkdir -p "$destination"

copy_report_root() {
    local report_root=$1
    local case_dir implementation_dir case_name implementation
    while IFS= read -r -d '' case_dir; do
        case_name=$(basename "$case_dir")
        case "$case_name" in
            plots|jvmec_reports) continue ;;
        esac
        while IFS= read -r -d '' implementation_dir; do
            implementation=$(basename "$implementation_dir")
            mkdir -p "$destination/$case_name"
            # The destination is generated benchmark output selected by the
            # caller.  Removing exactly one old implementation lets a later,
            # corrected rerun take precedence without touching other cases.
            rm -rf -- "$destination/$case_name/$implementation"
            cp -a -- "$implementation_dir" "$destination/$case_name/"
        done < <(find "$case_dir" -mindepth 1 -maxdepth 1 -type d -print0)
    done < <(find "$report_root" -mindepth 1 -maxdepth 1 -type d -print0)
}

for source in "$@"; do
    [[ -d "$source" ]] || {
        printf 'skipping missing source: %s\n' "$source" >&2
        continue
    }
    while IFS= read -r -d '' report_root; do
        copy_report_root "$report_root"
    done < <(find "$source" -type f -name comparison_table.csv -printf '%h\0' | sort -zu)
done

printf 'Merged implementation directories: %s\n' \
    "$(find "$destination" -mindepth 2 -maxdepth 2 -type d | wc -l)"
