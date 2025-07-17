module jvmec_comparison
    use iso_fortran_env, only: int32, real64, output_unit
    use vmec_benchmark_types, only: vmec_result_t
    implicit none
    private
    
    public :: compare_jvmec_results, write_jvmec_comparison_report
    
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
    
end module jvmec_comparison