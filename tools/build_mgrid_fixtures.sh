#!/usr/bin/env bash
# Build the mgrid fixtures listed in tools/mgrid_fixtures.tsv.
#
# Usage: tools/build_mgrid_fixtures.sh MGRID_EXECUTABLE BASE_DIR OUTPUT_DIR
#
# MGRID_EXECUTABLE is ORNL MAKEGRID's `mgrid` (built by the PARVMEC superbuild
# with -DMAKEGRID_SOURCE_DIR).  Existing fixtures are kept.
set -euo pipefail

mgrid=$(realpath "$1"); base_dir=$(realpath "$2"); output_dir=$3
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
mkdir -p "$output_dir"; output_dir=$(realpath "$output_dir")

while IFS=$'\t' read -r name source arguments; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    target="$output_dir/$name"
    [[ -s "$target" ]] && continue
    if [[ "$source" == http* ]]; then
        curl -fsSL -o "$target.part" "$source"
        mv "$target.part" "$target"
        continue
    fi
    work=$(mktemp -d)
    cp "$base_dir/$source" "$work/coils.fixture"
    # shellcheck disable=SC2086
    (cd "$work" && "$mgrid" fixture $arguments > makegrid.log 2>&1) || {
        printf 'MAKEGRID failed for %s, see %s/makegrid.log\n' "$name" "$work" >&2
        exit 1
    }
    mv "$work/mgrid_fixture.nc" "$target"
    rm -rf "$work"
done < "$script_dir/mgrid_fixtures.tsv"
