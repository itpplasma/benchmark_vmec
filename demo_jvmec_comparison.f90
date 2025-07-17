program demo_jvmec_comparison
    use iso_fortran_env, only: int32, real64, output_unit
    use vmec_benchmark_types, only: vmec_result_t
    use jvmec_comparison, only: generate_jvmec_quantitative_summary
    implicit none
    
    type(vmec_result_t) :: results(4)
    character(len=20), parameter :: impl_names(4) = [ &
        "educational_vmec    ", &
        "jvmec               ", &
        "vmec2000            ", &
        "vmecpp              " &
    ]
    character(len=50), parameter :: case_names(4) = [ &
        "cma_lasym_F                                       ", &
        "cth_like_fixed_bdy_lasym_F                        ", &
        "up_down_asymmetric_tokamak_lasym_T                ", &
        "ITER_hybrid_lasym_T                               " &
    ]
    logical, parameter :: lasym_settings(4) = [.false., .false., .true., .true.]
    integer :: i, j, case_idx
    
    write(output_unit, '(A)') "Demo: Enhanced jVMEC Comparison Analysis"
    write(output_unit, '(A)') "========================================"
    
    ! Create simulated benchmark results for each test case
    do case_idx = 1, 4
        write(output_unit, '(/,A,I0,A,A)') "Case ", case_idx, ": ", trim(case_names(case_idx))
        write(output_unit, '(A,L1)') "  LASYM = ", lasym_settings(case_idx)
        
        ! Create mock results for each implementation
        do i = 1, 4
            call results(i)%clear()
            results(i)%success = .true.
            
            ! Simulate realistic R-axis values with small variations
            results(i)%raxis_cc = 1.0_real64 + 0.01_real64 * real(i-1, real64)
            if (lasym_settings(case_idx)) then
                ! Add more variation for non-axisymmetric cases
                results(i)%raxis_cc = results(i)%raxis_cc + 0.005_real64 * real(case_idx, real64)
            end if
            
            ! Add physics quantities
            results(i)%betatotal = 0.05_real64 + 0.001_real64 * real(i, real64)
            results(i)%volume_p = 10.0_real64 + 0.1_real64 * real(i, real64)
            results(i)%aspect = 3.0_real64 + 0.05_real64 * real(i, real64)
            
            ! Add Fourier coefficients for first 3 implementations
            if (i <= 3) then
                allocate(results(i)%rmnc(25, 10))
                allocate(results(i)%zmns(25, 10))
                allocate(results(i)%lmns(25, 10))
                allocate(results(i)%xm(10))
                allocate(results(i)%xn(10))
                
                ! Fill with realistic values
                results(i)%rmnc = 1.0_real64 + 0.001_real64 * real(i, real64)
                results(i)%zmns = 0.5_real64 + 0.0005_real64 * real(i, real64)
                results(i)%lmns = 0.1_real64 + 0.0001_real64 * real(i, real64)
                
                ! Mode numbers
                results(i)%xm = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
                results(i)%xn = [0, 0, 0, 1, 1, 1, 2, 2, 2, 3]
                
                ! Add some realistic variation in the modes
                do j = 1, 10
                    results(i)%rmnc(:, j) = results(i)%rmnc(:, j) * &
                        (1.0_real64 + 0.1_real64 * sin(real(j, real64)))
                    results(i)%zmns(:, j) = results(i)%zmns(:, j) * &
                        (1.0_real64 + 0.05_real64 * cos(real(j, real64)))
                end do
                
                ! Add asymmetric effects for LASYM=T cases
                if (lasym_settings(case_idx)) then
                    allocate(results(i)%rmns(25, 10))
                    allocate(results(i)%zmnc(25, 10))
                    results(i)%rmns = 0.01_real64 + 0.0001_real64 * real(i, real64)
                    results(i)%zmnc = 0.02_real64 + 0.0002_real64 * real(i, real64)
                end if
            end if
            
            ! Simulate jVMEC having limited data (partial results)
            if (i == 2) then  ! jVMEC implementation
                results(i)%betatotal = 0.0_real64  ! Not available
                results(i)%volume_p = 0.0_real64   ! Not available
                results(i)%aspect = 0.0_real64     ! Not available
            end if
        end do
        
        ! Generate comparison report for this case
        call generate_jvmec_quantitative_summary(results, impl_names, &
            "demo_jvmec_comparison_" // trim(case_names(case_idx)) // ".md")
        
        ! Clean up
        do i = 1, 4
            call results(i)%clear()
        end do
    end do
    
    write(output_unit, '(/,A)') "Demo completed! Check generated .md files for:"
    write(output_unit, '(A)') "- Quantitative comparison metrics"
    write(output_unit, '(A)') "- Fourier mode RMS/Max differences"
    write(output_unit, '(A)') "- Statistical summaries"
    write(output_unit, '(A)') "- Handling of jVMEC partial data"
    
end program demo_jvmec_comparison