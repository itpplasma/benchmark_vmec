#!/bin/bash

# Script to run specific benchmark cases to avoid segfault

echo "Running VMEC benchmarks on specific test cases..."

# Test case 1: lasym=F (axisymmetric)
TEST_CASE_F1="vmec_repos/vmecpp/src/vmecpp/cpp/vmecpp/test_data/input.cma"
TEST_CASE_F2="vmec_repos/vmecpp/src/vmecpp/cpp/vmecpp/test_data/input.cth_like_fixed_bdy"

# Test case 2: lasym=T (non-axisymmetric) 
TEST_CASE_T1="vmec_repos/VMEC2000/python/tests/input.up_down_asymmetric_tokamak"
TEST_CASE_T2="vmec_repos/educational_VMEC/test/from_MattLandreman_vmec_equilibria/ITER/hybridAxisymmFixedBoundaryNs201/input.ITER_hybridAxisymmFixedBoundaryNs201"

mkdir -p benchmark_results

echo "Running test case 1 (lasym=F): input.cma"
timeout 300 fpm run vmec-benchmark -- run --limit 1 --include-file "$TEST_CASE_F1"

echo "Running test case 2 (lasym=F): input.cth_like_fixed_bdy"  
timeout 300 fpm run vmec-benchmark -- run --limit 1 --include-file "$TEST_CASE_F2"

echo "Running test case 3 (lasym=T): input.up_down_asymmetric_tokamak"
timeout 300 fpm run vmec-benchmark -- run --limit 1 --include-file "$TEST_CASE_T1"

echo "Running test case 4 (lasym=T): input.ITER_hybridAxisymmFixedBoundaryNs201"
timeout 300 fmp run vmec-benchmark -- run --limit 1 --include-file "$TEST_CASE_T2"

echo "Benchmark runs completed!"