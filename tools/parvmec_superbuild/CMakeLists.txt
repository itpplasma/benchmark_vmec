cmake_minimum_required(VERSION 3.18)

project(vmec_benchmark_parvmec LANGUAGES C CXX Fortran)

if(NOT DEFINED PARVMEC_SOURCE_DIR OR NOT DEFINED LIBSTELL_SOURCE_DIR)
    message(FATAL_ERROR
        "PARVMEC_SOURCE_DIR and LIBSTELL_SOURCE_DIR must point to pinned source checkouts")
endif()

get_filename_component(PARVMEC_SOURCE_DIR "${PARVMEC_SOURCE_DIR}" REALPATH)
get_filename_component(LIBSTELL_SOURCE_DIR "${LIBSTELL_SOURCE_DIR}" REALPATH)
if(NOT EXISTS "${PARVMEC_SOURCE_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "PARVMEC_SOURCE_DIR is not a CMake source tree: ${PARVMEC_SOURCE_DIR}")
endif()
if(NOT EXISTS "${LIBSTELL_SOURCE_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "LIBSTELL_SOURCE_DIR is not a CMake source tree: ${LIBSTELL_SOURCE_DIR}")
endif()

# LIBSTELL owns the FindNetCDF/FindSCALAPACK modules consumed by its CMake
# project.  Add it before configuring either subproject so the dependency
# discovery is deterministic and does not depend on the host's module path.
list(PREPEND CMAKE_MODULE_PATH "${LIBSTELL_SOURCE_DIR}/cmake")

# PARVMEC's upstream CMakeLists predates projects that enable the Fortran
# preprocessor by default.  Keep the flag explicit: parallel_vmec_module.f90
# contains conditional MPI code and otherwise compiles as literal directives.
set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -cpp")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")

# LIBSTELL normally receives these harmless interface targets from the
# Stellarator-Tools superproject.  Define the same no-op interfaces here so a
# direct benchmark superbuild does not turn their names into ``-l...`` flags.
foreach(interface_name IN ITEMS sanitizer traps checks)
    if(NOT TARGET ${interface_name})
        add_library(${interface_name} INTERFACE)
    endif()
endforeach()

add_subdirectory("${LIBSTELL_SOURCE_DIR}" libstell)
add_subdirectory("${PARVMEC_SOURCE_DIR}" parvmec)

if(TARGET vmec)
    target_compile_options(vmec PRIVATE $<$<COMPILE_LANGUAGE:Fortran>:-cpp>)
endif()
if(TARGET xvmec)
    set_target_properties(xvmec PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
endif()
