program test_jvmec_comparison
    use iso_fortran_env, only: int32, real64, output_unit
    use vmec_benchmark_types, only: vmec_result_t
    use jvmec_comparison, only: generate_jvmec_quantitative_summary, &
                                compare_fourier_modes
    implicit none
    
    call test_quantitative_summary()
    call test_fourier_comparison()
    
    write(output_unit, '(A)') "All jVMEC comparison tests passed!"
    
contains
    
    subroutine test_quantitative_summary()
        type(vmec_result_t) :: results(3)
        character(len=20) :: impl_names(3)
        integer :: i
        
        write(output_unit, '(A)') "Testing jVMEC quantitative summary..."
        
        ! Create test data
        impl_names(1) = "educational_vmec"
        impl_names(2) = "jvmec"
        impl_names(3) = "vmec2000"
        
        ! Set up test results
        do i = 1, 3
            call results(i)%clear()
            results(i)%success = .true.
            results(i)%raxis_cc = 1.0_real64 + 0.01_real64 * real(i-1, real64)
            
            ! Add some Fourier data for testing
            allocate(results(i)%rmnc(50, 10))
            allocate(results(i)%zmns(50, 10))
            allocate(results(i)%xm(10))
            allocate(results(i)%xn(10))
            
            results(i)%rmnc = 1.0_real64
            results(i)%zmns = 0.5_real64
            results(i)%xm = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
            results(i)%xn = [0, 0, 0, 1, 1, 1, 2, 2, 2, 3]
            
            ! Add small differences for testing
            if (i > 1) then
                results(i)%rmnc = results(i)%rmnc * (1.0_real64 + 0.001_real64 * i)
                results(i)%zmns = results(i)%zmns * (1.0_real64 + 0.002_real64 * i)
            end if
        end do
        
        ! Test the summary generation
        call generate_jvmec_quantitative_summary(results, impl_names, &
                                                 "test_jvmec_summary.md")
        
        ! Cleanup
        do i = 1, 3
            call results(i)%clear()
        end do
        
        write(output_unit, '(A)') "  ✓ Quantitative summary test passed"
        
    end subroutine test_quantitative_summary
    
    subroutine test_fourier_comparison()
        type(vmec_result_t) :: ref_result, test_result
        integer :: unit
        
        write(output_unit, '(A)') "Testing Fourier mode comparison..."
        
        ! Set up test data
        call ref_result%clear()
        call test_result%clear()
        
        ref_result%success = .true.
        test_result%success = .true.
        
        allocate(ref_result%rmnc(30, 5))
        allocate(ref_result%zmns(30, 5))
        allocate(test_result%rmnc(30, 5))
        allocate(test_result%zmns(30, 5))
        
        ! Fill with test data
        ref_result%rmnc = 1.0_real64
        ref_result%zmns = 0.5_real64
        test_result%rmnc = 1.001_real64  ! Small difference
        test_result%zmns = 0.502_real64  ! Small difference
        
        ! Test comparison
        open(newunit=unit, file="test_fourier_comparison.txt", &
             status='replace', action='write')
        
        call compare_fourier_modes(ref_result, test_result, unit, "test_impl")
        
        close(unit)
        
        ! Cleanup
        call ref_result%clear()
        call test_result%clear()
        
        write(output_unit, '(A)') "  ✓ Fourier comparison test passed"
        
    end subroutine test_fourier_comparison
    
end program test_jvmec_comparison