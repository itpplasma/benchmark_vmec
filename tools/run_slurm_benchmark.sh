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
case_match=${BENCHMARK_MATCH:-}
implementation_filter=${BENCHMARK_IMPLEMENTATION:-}

case_match_args=()
if [[ -n "$case_match" ]]; then
    case_match_args=(--match "$case_match")
fi
implementation_args=()
if [[ -n "$implementation_filter" ]]; then
    implementation_args=(--impl "$implementation_filter")
fi

export PATH="$HOME/.local/bin:$PATH"
export BENCHMARK_BASE_DIR="$base_dir"
# Fo's compiler autodetection can select the Debian triplet wrapper on the
# cluster; that wrapper exposes a flag-joining bug in Fo's first-build path.
# Prefer the canonical gfortran executable while retaining an explicit caller
# override for other toolchains.
if [[ -z "${FO_FC:-}" ]] && command -v gfortran >/dev/null 2>&1; then
    export FO_FC="$(command -v gfortran)"
fi
# Parallel Slurm allocations must not refresh fo's shared dependency cache at
# the same time.  Keep fo's normal persistent cache, but serialize the short
# build/test bootstrap below; callers may override both paths explicitly.
export FO_CACHE_DIR="${FO_CACHE_DIR:-$HOME/.cache/fo}"
mkdir -p "$FO_CACHE_DIR"
# Index reusable magnetic-grid fixtures once per allocation.  Several upstream
# VMEC tests refer to a grid by basename while running in an isolated output
# directory; adapters use this index to stage the matching file when present.
mgrid_index=${VMEC_BENCHMARK_MGRID_INDEX:-"${TMPDIR:-/tmp}/vmec-benchmark-mgrid-${SLURM_JOB_ID:-local}.txt"}
if [[ ! -s "$mgrid_index" ]]; then
    mgrid_index_tmp="${mgrid_index}.tmp.$$"
    # Staged cluster stacks use sibling symlinks; follow them so jVMEC and
    # VMEC++ can see fixtures held in an educational_VMEC checkout.
    find -L "$base_dir" -maxdepth 8 \
        \( -type d -name 'benchmark_results*' -o -type d -name 'build' -o \
           -type d -name '.git' -o -type d -name '.venv' -o -type d -name 'target' -o \
           -type d -name 'CMakeFiles' -o -type d -name '__pycache__' \) -prune -o \
        -type f -iname 'mgrid*' -print 2>/dev/null > "$mgrid_index_tmp" || true
    mv -f "$mgrid_index_tmp" "$mgrid_index"
fi
export VMEC_BENCHMARK_MGRID_INDEX="$mgrid_index"
# Keep user-local scientific runtimes visible in batch shells.  These paths
# are optional; they are used when a staged code was built against OpenBLAS or
# NetCDF-Fortran without administrator privileges.
for runtime_lib_dir in \
    "$HOME/.local/openblas/usr/lib/x86_64-linux-gnu/openblas-pthread" \
    "$HOME/.local/netcdff/usr/lib/x86_64-linux-gnu" \
    "/usr/lib/x86_64-linux-gnu/hdf5/serial"; do
    if [[ -d "$runtime_lib_dir" ]]; then
        export LD_LIBRARY_PATH="$runtime_lib_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    fi
done
# The user-local NetCDF-Fortran package is staged under ~/.local, while its
# generated .pc file still carries the administrator prefix (/usr).  Give
# pkg-config an explicit user-local override so fo sees netcdf.mod and the
# linker sees the matching library.  This also keeps the fpm fallback usable.
netcdff_pc="$HOME/.local/netcdff/usr/lib/x86_64-linux-gnu/pkgconfig/netcdf-fortran.pc"
netcdff_override="$HOME/.local/pkgconfig/netcdf-fortran.pc"
if [[ -f "$netcdff_pc" ]]; then
    mkdir -p "$(dirname "$netcdff_override")"
    if [[ ! -f "$netcdff_override" || "$netcdff_pc" -nt "$netcdff_override" ]]; then
        sed "s#^prefix=/usr#prefix=$HOME/.local/netcdff/usr#" \
            "$netcdff_pc" > "$netcdff_override"
    fi
    pkgconfig_dir=$(dirname "$netcdff_override")
    export PKG_CONFIG_PATH="$pkgconfig_dir${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
fi
# Include the manually staged Java implementation whenever its checkout is
# present.  It remains an ordinary (non-differentiable) participant.
export BENCHMARK_INCLUDE_JVMEC="${BENCHMARK_INCLUDE_JVMEC:-1}"
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

stage_chease_case() {
    # CHEASE needs a genuine EQDSK contract.  Stage the solver's small D3D
    # regression fixture into the benchmark corpus without vendoring a
    # third-party data file into this repository.
    local source="$base_dir/CHEASE/WK/TESTCASES/D3D/geqdsk_COCOS5"
    local destination="$repo_root/cases/generated/2d_chease/input.geqdsk"
    if [[ -f "$source" ]]; then
        mkdir -p "$(dirname "$destination")"
        if [[ ! -f "$destination" || "$source" -nt "$destination" ]]; then
            cp "$source" "$destination"
        fi
        printf 'Staged CHEASE native 2-D fixture: %s\n' "$destination"
    else
        printf 'CHEASE native fixture unavailable; no generated GEQDSK case staged\n' >&2
    fi
}

driver=fo
prepare_driver() {
    local fo_cache_lock_fd
    fo_cache_lock="${FO_CACHE_LOCK:-${FO_CACHE_DIR}.lock}"
    exec {fo_cache_lock_fd}>"$fo_cache_lock"
    flock "$fo_cache_lock_fd"
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
        # The cluster image exposes the HDF5 Fortran module and libraries via
        # the serial HDF5 installation, while some fpm/pkg-config combinations
        # only propagate the C ``hdf5`` flags.  Supply the explicit include
        # and link paths for the HDF5-backed SPEC reader before the fallback
        # build so the fallback is equivalent to the fo path.
        hdf5_cflags=$(pkg-config --cflags-only-I hdf5 2>/dev/null || true)
        hdf5_ldflags=$(pkg-config --libs-only-L hdf5 2>/dev/null || true)
        if [[ -n "$hdf5_cflags" && -n "$hdf5_ldflags" ]]; then
            export FPM_FFLAGS="${FPM_FFLAGS:-} ${hdf5_cflags}"
            export FPM_LDFLAGS="${FPM_LDFLAGS:-} ${hdf5_ldflags} -lhdf5_fortran -lhdf5"
        fi
        # fo and fpm share the build directory.  Remove fo's partially linked
        # artifacts so fpm cannot report the failed link as "up to date".
        fpm clean --skip >/dev/null 2>&1 || true
        fpm build
        if [[ "$mode" == smoke ]]; then
            fpm test
        fi
        driver=fpm
    fi
    flock -u "$fo_cache_lock_fd"
    eval "exec ${fo_cache_lock_fd}>&-"
}

run_driver() {
    if [[ "$driver" == fo ]]; then
        BENCHMARK_REPO_ROOT="$repo_root" fo run vmec-benchmark -- "$@" \
            --base-dir "$base_dir" --output-dir "$output_dir"
    else
        # Keep discovery rooted in this checkout on the fpm fallback too.
        # Without the export, the executable defaults to a sibling
        # ``benchmark_vmec`` symlink, which can point at an unrelated or
        # already-running result tree.
        BENCHMARK_REPO_ROOT="$repo_root" fpm run --target vmec-benchmark -- "$@" \
            --base-dir "$base_dir" --output-dir "$output_dir"
    fi
}

case "$mode" in
    smoke)
        prepare_driver
        stage_chease_case
        run_driver list-repos
        if [[ -n "$case_match" ]]; then
            run_driver list-cases "${case_match_args[@]}" --limit 1
            run_driver run "${case_match_args[@]}" "${implementation_args[@]}" --limit 1 --timeout "$timeout_seconds"
        else
            run_driver list-cases --match 'cases/analytic/2d_solovev' --limit 1
            run_driver run --match 'cases/analytic/2d_solovev' "${implementation_args[@]}" --limit 1 --timeout "$timeout_seconds"
        fi
        ;;
    full)
        prepare_driver
        stage_chease_case
        run_driver list-repos
        run_driver list-cases "${case_match_args[@]}"
        run_driver run "${case_match_args[@]}" "${implementation_args[@]}" --timeout "$timeout_seconds"
        ;;
    *)
        printf 'usage: %s {smoke|full}\n' "$0" >&2
        exit 2
        ;;
esac
