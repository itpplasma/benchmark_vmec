#!/usr/bin/env bash
# Build PARVMEC with the exact LIBSTELL/PARVMEC revisions used by the
# benchmark.  The script is deliberately independent of the other benchmark
# implementations so it can run in its own Slurm allocation.
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
base_dir=${BENCHMARK_BASE_DIR:-$(dirname "$repo_root")}
source_root=${PARVMEC_SOURCE_ROOT:-"$base_dir/parvmec-sources"}
parvmec_ref=${PARVMEC_REF:-eae0ff26ae39dc0a3aacbe15e02008972f02ee84}
libstell_ref=${LIBSTELL_REF:-8f0dbd7ea1465b159b54127f00639806745ffdca}
parvmec_build_dir=${PARVMEC_BUILD_DIR:-"$base_dir/parvmec-build"}

parvmec_url=${PARVMEC_URL:-https://github.com/ORNL-Fusion/PARVMEC.git}
libstell_url=${LIBSTELL_URL:-https://github.com/ORNL-Fusion/LIBSTELL.git}

die() {
    printf 'build_parvmec: %s\n' "$*" >&2
    exit 1
}

ensure_checkout() {
    local name=$1 url=$2 ref=$3 destination=$4
    if [[ -e "$destination" && ! -d "$destination/.git" ]]; then
        die "$destination exists but is not a git checkout"
    fi
    if [[ ! -d "$destination/.git" ]]; then
        mkdir -p "$(dirname "$destination")"
        git clone --filter=blob:none --no-checkout "$url" "$destination"
        git -C "$destination" fetch --depth 1 origin "$ref"
        git -C "$destination" checkout --detach "$ref"
    fi
    local actual
    actual=$(git -C "$destination" rev-parse HEAD)
    [[ "$actual" == "$ref" ]] || die "$name checkout is $actual, expected pinned $ref"
}

# Reuse an already staged checkout only when it carries Git metadata and the
# requested commit.  Otherwise place a fresh, pinned checkout in a dedicated
# sibling directory; never rewrite an existing source tree in place.
choose_source() {
    local env_name=$1 fallback=$2 ref=$3
    local requested=${!env_name:-}
    if [[ -n "$requested" ]]; then
        printf '%s\n' "$requested"
        return
    fi
    local candidate actual
    for candidate in "$base_dir/PARVMEC" "$base_dir/Stellarator-Tools/PARVMEC"; do
        if [[ -d "$candidate/.git" ]]; then
            actual=$(git -C "$candidate" rev-parse HEAD 2>/dev/null || true)
            if [[ "$actual" == "$ref" ]]; then
                printf '%s\n' "$candidate"
                return
            fi
        fi
    done
    printf '%s\n' "$fallback"
}

parvmec_source=$(choose_source PARVMEC_SOURCE_DIR "$source_root/PARVMEC" "$parvmec_ref")
libstell_source=$(choose_source LIBSTELL_SOURCE_DIR "$source_root/LIBSTELL" "$libstell_ref")
ensure_checkout PARVMEC "$parvmec_url" "$parvmec_ref" "$parvmec_source"
ensure_checkout LIBSTELL "$libstell_url" "$libstell_ref" "$libstell_source"

mkdir -p "$parvmec_build_dir"

netcdff_root=${NETCDFF_ROOT:-"$HOME/.local/netcdff/usr"}
netcdf_c_include=${NETCDF_C_INCLUDE_DIR:-/usr/include}
netcdf_c_library=${NETCDF_C_LIBRARY:-/usr/lib/x86_64-linux-gnu/libnetcdf.so.19}
netcdf_f_include=${NETCDF_FORTRAN_INCLUDE_DIR:-"$netcdff_root/include"}
netcdf_f_library=${NETCDF_FORTRAN_LIBRARY:-"$netcdff_root/lib/x86_64-linux-gnu/libnetcdff.so.7.1.0"}
scalapack_library=${SCALAPACK_LIBRARY:-/usr/lib/x86_64-linux-gnu/libscalapack-openmpi.so.2.2.1}
blas_library=${BLAS_LIBRARY:-/usr/lib/x86_64-linux-gnu/libblas.so.3}
lapack_library=${LAPACK_LIBRARY:-/usr/lib/x86_64-linux-gnu/liblapack.so.3}

for required in "$netcdf_c_library" "$netcdf_f_library" "$scalapack_library" \
    "$blas_library" "$lapack_library"; do
    [[ -f "$required" ]] || die "required library not found: $required"
done
[[ -f "$netcdf_c_include/netcdf.h" ]] || die "NetCDF C headers not found under $netcdf_c_include"
[[ -f "$netcdf_f_include/netcdf.inc" ]] || die "NetCDF Fortran headers not found under $netcdf_f_include"

export LD_LIBRARY_PATH="$netcdff_root/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
cmake_args=(
    -S "$repo_root/tools/parvmec_superbuild"
    -B "$parvmec_build_dir"
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_Fortran_COMPILER="${FC:-mpifort}"
    -DCMAKE_C_COMPILER="${CC:-mpicc}"
    -DCMAKE_CXX_COMPILER="${CXX:-mpicxx}"
    -DPARVMEC_SOURCE_DIR="$parvmec_source"
    -DLIBSTELL_SOURCE_DIR="$libstell_source"
    -DNetCDF_C_INCLUDE_DIR="$netcdf_c_include"
    -DNetCDF_C_LIBRARY="$netcdf_c_library"
    -DNetCDF_Fortran_INCLUDE_DIR="$netcdf_f_include"
    -DNetCDF_Fortran_LIBRARY="$netcdf_f_library"
    -DSCALAPACK_LIBRARY="$scalapack_library"
    -DBLAS_LIBRARIES="$blas_library"
    -DLAPACK_LIBRARIES="$lapack_library"
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
)
cmake "${cmake_args[@]}"
cmake --build "$parvmec_build_dir" --target xvmec --parallel "${CMAKE_BUILD_PARALLEL_LEVEL:-4}"

executable="$parvmec_build_dir/bin/xvmec"
[[ -x "$executable" ]] || die "PARVMEC build completed without $executable"
printf '%s\n' "$executable" > "$parvmec_build_dir/executable.path"
cat > "$parvmec_build_dir/build-manifest.txt" <<EOF
PARVMEC_SOURCE_DIR=$parvmec_source
PARVMEC_COMMIT=$parvmec_ref
LIBSTELL_SOURCE_DIR=$libstell_source
LIBSTELL_COMMIT=$libstell_ref
PARVMEC_EXECUTABLE=$executable
EOF
printf 'PARVMEC executable: %s\n' "$executable"
