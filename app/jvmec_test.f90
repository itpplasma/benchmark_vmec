program jvmec_test
    use iso_fortran_env, only: output_unit, error_unit
    use vmec_benchmark_types, only: vmec_result_t
    use jvmec_implementation, only: jvmec_t
    use educational_vmec_implementation, only: educational_vmec_t
    use jvmec_comparison, only: compare_jvmec_results, write_jvmec_comparison_report
    implicit none
    
    type(jvmec_t) :: jvmec
    type(educational_vmec_t) :: edu_vmec
    type(vmec_result_t) :: results(2)
    character(len=32) :: impl_names(2)
    character(len=256) :: test_file, output_dir
    logical :: success
    
    ! Initialize implementations
    call jvmec%initialize("jVMEC", "./vmec_repos/jvmec")
    call edu_vmec%initialize("Educational VMEC", "./vmec_repos/educational_VMEC")
    
    impl_names(1) = "jVMEC"
    impl_names(2) = "Educational VMEC"
    
    ! Build implementations
    write(output_unit, '(A)') "Building implementations..."
    success = jvmec%build()
    if (.not. success) then
        write(error_unit, '(A)') "Failed to build jVMEC"
        stop 1
    end if
    
    success = edu_vmec%build()
    if (.not. success) then
        write(error_unit, '(A)') "Failed to build Educational VMEC"
        stop 1
    end if
    
    ! Run symmetric test case
    test_file = "test_symmetric.txt"
    write(output_unit, '(A)') ""
    write(output_unit, '(A,A)') "Running symmetric test case: ", trim(test_file)
    
    output_dir = "jvmec_test_results/symmetric/jvmec"
    success = jvmec%run_case(test_file, output_dir)
    call jvmec%extract_results(output_dir, results(1))
    
    output_dir = "jvmec_test_results/symmetric/educational"
    success = edu_vmec%run_case(test_file, output_dir)
    call edu_vmec%extract_results(output_dir, results(2))
    
    ! Write comparison
    call write_jvmec_comparison_report("Symmetric Case", results, impl_names)
    
    ! Run asymmetric test case
    test_file = "test_asymmetric.txt"
    write(output_unit, '(A)') ""
    write(output_unit, '(A,A)') "Running asymmetric test case: ", trim(test_file)
    
    output_dir = "jvmec_test_results/asymmetric/jvmec"
    success = jvmec%run_case(test_file, output_dir)
    call jvmec%extract_results(output_dir, results(1))
    
    output_dir = "jvmec_test_results/asymmetric/educational"
    success = edu_vmec%run_case(test_file, output_dir)
    call edu_vmec%extract_results(output_dir, results(2))
    
    ! Write comparison
    call write_jvmec_comparison_report("Asymmetric Case", results, impl_names)
    
    ! Write detailed report
    call compare_jvmec_results(results, impl_names, "jvmec_test_results/comparison_report.md")
    
    write(output_unit, '(A)') ""
    write(output_unit, '(A)') "Test completed successfully!"
    
end program jvmec_test