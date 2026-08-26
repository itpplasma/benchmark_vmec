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
csv_rows=$(mktemp)
csv_header=$(mktemp)
csv_unique=$(mktemp)
trap 'rm -f -- "$csv_rows" "$csv_header" "$csv_unique"' EXIT

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
        report_csv="$report_root/comparison_table.csv"
        if [[ ! -s "$csv_header" ]]; then
            head -n 1 "$report_csv" > "$csv_header"
        fi
        tail -n +2 "$report_csv" >> "$csv_rows"
    done < <(find "$source" -type f -name comparison_table.csv -printf '%h\0' | sort -zu)
done

if [[ -s "$csv_header" ]]; then
    # Keep first-seen order for readable reports while letting later sources
    # replace an earlier case/implementation pair.
    awk -F, ' {
        key = $1 SUBSEP $2
        if (!(key in line)) order[++n] = key
        line[key] = $0
    } END {
        for (i = 1; i <= n; ++i) print line[order[i]]
    }' "$csv_rows" > "$csv_unique"
    cat "$csv_header" "$csv_unique" > "$destination/comparison_table.csv"

    # Unsupported branches do not run an implementation and therefore have
    # no output directory to copy.  Materialize their explicit markers so the
    # merged tree and its per-case inventory retain those rows as well.
    while IFS=, read -r case_name implementation status error _; do
        [[ "$status" == failed ]] || continue
        case_slug=$(printf '%s' "$case_name" | sed -e 's#/#__#g' -e 's#[^A-Za-z0-9._-]#_#g')
        implementation_dir="$destination/$case_slug/$implementation"
        if [[ "$error" == Unsupported:* ]]; then
            rm -rf -- "$implementation_dir"
        fi
        mkdir -p "$implementation_dir"
        if [[ "$error" == Unsupported:* ]]; then
            printf '%s\n' "$error" > "$implementation_dir/benchmark_unsupported.txt"
        else
            printf '%s\n' "$error" > "$implementation_dir/benchmark_failure.txt"
        fi
    done < "$csv_unique"
fi

printf 'Merged implementation directories: %s\n' \
    "$(find "$destination" -mindepth 2 -maxdepth 2 -type d | wc -l)"
