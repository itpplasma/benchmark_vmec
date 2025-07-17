module jvmec_comparison
    use iso_fortran_env, only: int32, real64, output_unit
    use vmec_benchmark_types, only: vmec_result_t
    implicit none
    private
    
    public :: compare_jvmec_results, write_jvmec_comparison_report, &
              generate_jvmec_quantitative_summary, compare_fourier_modes
    
contains
    
    subroutine compare_jvmec_results(results, impl_names, output_file)
        type(vmec_result_t), intent(in) :: results(:)
        character(len=*), intent(in) :: impl_names(:)
        character(len=*), intent(in) :: output_file
        integer :: unit, i, j, n_impl
        
        n_impl = size(results)
        
        open(newunit=unit, file=output_file, status='replace', action='write')
        
        write(unit, '(A)') "# jVMEC-Compatible Comparison Report"
        write(unit, '(A)') ""
        write(unit, '(A)') "## Fourier Coefficient Comparison"
        write(unit, '(A)') ""
        write(unit, '(A)') "Comparing quantities available in jVMEC NetCDF output"
        write(unit, '(A)') ""
        
        ! Compare R axis values
        write(unit, '(A)') "### R axis (m=0, n=0 mode)"
        write(unit, '(A)') ""
        write(unit, '(A)') "| Implementation | R_axis |"
        write(unit, '(A)') "|----------------|--------|"
        
        do i = 1, n_impl
            if (results(i)%success) then
                write(unit, '(A,A15,A,F10.6,A)') "| ", impl_names(i), " | ", results(i)%raxis_cc, " |"
            else
                write(unit, '(A,A15,A)') "| ", impl_names(i), " | Failed |"
            end if
        end do
        
        write(unit, '(A)') ""
        
        ! Compare first few Fourier modes if available
        write(unit, '(A)') "### Fourier Modes (first 5 modes at boundary)"
        write(unit, '(A)') ""
        
        do i = 1, n_impl
            if (results(i)%success .and. allocated(results(i)%rmnc)) then
                write(unit, '(A,A,A)') "#### ", trim(impl_names(i)), ":"
                write(unit, '(A)') ""
                write(unit, '(A)') "| Mode (m,n) | R_mn | Z_mn |"
                write(unit, '(A)') "|------------|------|------|"
                
                do j = 1, min(5, size(results(i)%xm))
                    if (allocated(results(i)%xm) .and. allocated(results(i)%xn)) then
                        write(unit, '(A,I2,A,I2,A,ES12.5,A,ES12.5,A)') &
                            "| (", int(results(i)%xm(j)), ",", int(results(i)%xn(j)), ") | ", &
                            results(i)%rmnc(size(results(i)%rmnc,1), j), " | ", &
                            results(i)%zmns(size(results(i)%zmns,1), j), " |"
                    end if
                end do
                write(unit, '(A)') ""
            end if
        end do
        
        close(unit)
        
        write(output_unit, '(A)') "jVMEC comparison report written to: " // trim(output_file)
        
    end subroutine compare_jvmec_results
    
    subroutine write_jvmec_comparison_report(case_name, results, impl_names)
        character(len=*), intent(in) :: case_name
        type(vmec_result_t), intent(in) :: results(:)
        character(len=*), intent(in) :: impl_names(:)
        integer :: i, n_impl
        
        n_impl = size(results)
        
        write(output_unit, '(A)') ""
        write(output_unit, '(A,A)') "=== jVMEC-Compatible Results for case: ", trim(case_name)
        write(output_unit, '(A)') ""
        
        ! Show convergence status
        write(output_unit, '(A)') "Convergence Status:"
        do i = 1, n_impl
            write(output_unit, '(A15,A,L1)') adjustl(impl_names(i)), ": ", results(i)%success
        end do
        
        ! Show R axis comparison
        write(output_unit, '(A)') ""
        write(output_unit, '(A)') "R axis values:"
        do i = 1, n_impl
            if (results(i)%success) then
                write(output_unit, '(A15,A,F10.6)') adjustl(impl_names(i)), ": ", results(i)%raxis_cc
            end if
        end do
        
    end subroutine write_jvmec_comparison_report
    
    subroutine generate_jvmec_quantitative_summary(results, impl_names, &
                                                   output_file)
        type(vmec_result_t), intent(in) :: results(:)
        character(len=*), intent(in) :: impl_names(:)
        character(len=*), intent(in) :: output_file
        integer :: unit, i, j, n_impl, reference_idx
        real(real64) :: rel_diff, max_diff, rms_diff
        logical :: has_reference
        
        n_impl = size(results)
        
        open(newunit=unit, file=output_file, status='replace', action='write')
        
        write(unit, '(A)') "# Quantitative jVMEC Comparison Summary"
        write(unit, '(A)') ""
        
        ! Find reference implementation (first successful one)
        has_reference = .false.
        reference_idx = 0
        do i = 1, n_impl
            if (results(i)%success) then
                has_reference = .true.
                reference_idx = i
                exit
            end if
        end do
        
        if (.not. has_reference) then
            write(unit, '(A)') "No successful implementations found for comparison"
            close(unit)
            return
        end if
        
        write(unit, '(A,A)') "Reference implementation: ", &
                             trim(impl_names(reference_idx))
        write(unit, '(A)') ""
        
        ! Convergence analysis
        write(unit, '(A)') "## Convergence Analysis"
        write(unit, '(A)') ""
        write(unit, '(A)') "| Implementation | Status | R_axis | Available Data |"
        write(unit, '(A)') "|---|---|---|---|"
        
        do i = 1, n_impl
            if (results(i)%success) then
                write(unit, '(A,A,A,F10.6,A)', advance='no') &
                    "| ", trim(impl_names(i)), " | ✓ | ", &
                    results(i)%raxis_cc, " | "
                
                if (allocated(results(i)%rmnc)) then
                    write(unit, '(A,I0,A,I0,A)') "Fourier (", &
                        size(results(i)%rmnc,1), "×", &
                        size(results(i)%rmnc,2), ") |"
                else
                    write(unit, '(A)') "Limited |"
                end if
            else
                write(unit, '(A,A,A)') "| ", trim(impl_names(i)), &
                                       " | ✗ | - | - |"
            end if
        end do
        write(unit, '(A)') ""
        
        ! Quantitative differences
        write(unit, '(A)') "## Quantitative Differences from Reference"
        write(unit, '(A)') ""
        
        do i = 1, n_impl
            if (i == reference_idx .or. .not. results(i)%success) cycle
            
            write(unit, '(A,A,A)') "### ", trim(impl_names(i)), &
                                   " vs Reference"
            write(unit, '(A)') ""
            
            ! R-axis difference
            rel_diff = abs(results(i)%raxis_cc - results(reference_idx)%raxis_cc)
            if (abs(results(reference_idx)%raxis_cc) > 1e-12_real64) then
                rel_diff = rel_diff / abs(results(reference_idx)%raxis_cc)
            end if
            write(unit, '(A,ES12.5,A,ES12.5,A)') &
                "- R-axis: Δ = ", rel_diff, " (ref: ", &
                results(reference_idx)%raxis_cc, ")"
            
            ! Fourier mode comparison if available
            call compare_fourier_modes(results(reference_idx), results(i), &
                                      unit, impl_names(i))
            
            write(unit, '(A)') ""
        end do
        
        ! Statistical summary
        call write_statistical_summary(results, impl_names, unit, &
                                       reference_idx)
        
        close(unit)
        
        write(output_unit, '(A)') &
            "Quantitative jVMEC summary written to: " // trim(output_file)
        
    end subroutine generate_jvmec_quantitative_summary
    
    subroutine compare_fourier_modes(ref_result, test_result, unit, impl_name)
        type(vmec_result_t), intent(in) :: ref_result, test_result
        integer, intent(in) :: unit
        character(len=*), intent(in) :: impl_name
        integer :: i, j, n_modes_compare, ns_ref, ns_test
        real(real64) :: rms_diff, max_diff, mode_diff
        integer :: n_compared = 0
        
        if (.not. (allocated(ref_result%rmnc) .and. &
                   allocated(test_result%rmnc))) then
            write(unit, '(A)') "- Fourier coefficients: Not available for comparison"
            return
        end if
        
        ns_ref = size(ref_result%rmnc, 1)
        ns_test = size(test_result%rmnc, 1)
        n_modes_compare = min(size(ref_result%rmnc, 2), &
                             size(test_result%rmnc, 2), 10)
        
        if (n_modes_compare == 0) then
            write(unit, '(A)') "- Fourier coefficients: No modes to compare"
            return
        end if
        
        ! RMS difference in first few modes at boundary
        rms_diff = 0.0_real64
        max_diff = 0.0_real64
        n_compared = 0
        
        do j = 1, n_modes_compare
            if (ns_ref > 0 .and. ns_test > 0) then
                mode_diff = abs(ref_result%rmnc(ns_ref, j) - &
                               test_result%rmnc(ns_test, j))
                rms_diff = rms_diff + mode_diff**2
                max_diff = max(max_diff, mode_diff)
                n_compared = n_compared + 1
            end if
        end do
        
        if (n_compared > 0) then
            rms_diff = sqrt(rms_diff / real(n_compared, real64))
            write(unit, '(A,ES12.5,A,ES12.5,A,I0,A)') &
                "- Fourier R modes: RMS Δ = ", rms_diff, &
                ", Max Δ = ", max_diff, " (", n_compared, " modes)"
        end if
        
        ! Similar for Z modes if available
        if (allocated(ref_result%zmns) .and. allocated(test_result%zmns)) then
            rms_diff = 0.0_real64
            max_diff = 0.0_real64
            n_compared = 0
            
            do j = 1, min(size(ref_result%zmns, 2), &
                          size(test_result%zmns, 2), 10)
                if (ns_ref > 0 .and. ns_test > 0) then
                    mode_diff = abs(ref_result%zmns(ns_ref, j) - &
                                   test_result%zmns(ns_test, j))
                    rms_diff = rms_diff + mode_diff**2
                    max_diff = max(max_diff, mode_diff)
                    n_compared = n_compared + 1
                end if
            end do
            
            if (n_compared > 0) then
                rms_diff = sqrt(rms_diff / real(n_compared, real64))
                write(unit, '(A,ES12.5,A,ES12.5,A,I0,A)') &
                    "- Fourier Z modes: RMS Δ = ", rms_diff, &
                    ", Max Δ = ", max_diff, " (", n_compared, " modes)"
            end if
        end if
        
    end subroutine compare_fourier_modes
    
    subroutine write_statistical_summary(results, impl_names, unit, &
                                         reference_idx)
        type(vmec_result_t), intent(in) :: results(:)
        character(len=*), intent(in) :: impl_names(:)
        integer, intent(in) :: unit, reference_idx
        integer :: i, n_success, n_impl
        real(real64) :: mean_raxis, std_raxis, min_raxis, max_raxis
        real(real64), allocatable :: raxis_values(:)
        integer :: n_values
        
        n_impl = size(results)
        n_success = 0
        
        ! Count successful runs
        do i = 1, n_impl
            if (results(i)%success) n_success = n_success + 1
        end do
        
        write(unit, '(A)') "## Statistical Summary"
        write(unit, '(A)') ""
        write(unit, '(A,I0,A,I0,A)') "- Total implementations: ", n_impl, &
                                     " (", n_success, " successful)"
        
        if (n_success < 2) then
            write(unit, '(A)') "- Insufficient data for statistical analysis"
            return
        end if
        
        ! Collect R-axis values
        allocate(raxis_values(n_success))
        n_values = 0
        
        do i = 1, n_impl
            if (results(i)%success) then
                n_values = n_values + 1
                raxis_values(n_values) = results(i)%raxis_cc
            end if
        end do
        
        ! Calculate statistics
        mean_raxis = sum(raxis_values) / real(n_values, real64)
        min_raxis = minval(raxis_values)
        max_raxis = maxval(raxis_values)
        
        std_raxis = 0.0_real64
        if (n_values > 1) then
            std_raxis = sqrt(sum((raxis_values - mean_raxis)**2) / &
                            real(n_values - 1, real64))
        end if
        
        write(unit, '(A,ES12.5)') "- R-axis mean: ", mean_raxis
        write(unit, '(A,ES12.5)') "- R-axis std dev: ", std_raxis
        write(unit, '(A,ES12.5,A,ES12.5,A)') "- R-axis range: [", &
                                             min_raxis, ", ", max_raxis, "]"
        
        ! Relative std dev
        if (abs(mean_raxis) > 1e-12_real64) then
            write(unit, '(A,ES12.5,A)') "- R-axis relative std dev: ", &
                                        std_raxis/abs(mean_raxis), " (ratio)"
        end if
        
        deallocate(raxis_values)
        
    end subroutine write_statistical_summary
    
end module jvmec_comparison