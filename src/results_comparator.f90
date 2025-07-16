module results_comparator
    use iso_fortran_env, only: int32, real64, error_unit, output_unit
    use vmec_benchmark_types, only: vmec_result_t
    implicit none
    private

    public :: results_comparator_t

    type :: case_results_t
        character(len=:), allocatable :: case_name
        character(len=:), allocatable :: impl_names(:)
        type(vmec_result_t), allocatable :: results(:)
        integer :: n_impls = 0
    end type case_results_t

    type :: results_comparator_t
        type(case_results_t), allocatable :: case_results(:)
        integer :: n_cases = 0
        character(len=32), dimension(6) :: key_quantities = [ &
            "wb              ", &
            "betatotal       ", &
            "aspect          ", &
            "raxis_cc        ", &
            "volume_p        ", &
            "iotaf_edge      " &
        ]
    contains
        procedure :: initialize => results_comparator_initialize
        procedure :: add_result => results_comparator_add_result
        procedure :: create_comparison_table => results_comparator_create_comparison_table
        procedure :: calculate_relative_differences => results_comparator_calculate_relative_differences
        procedure :: get_convergence_summary => results_comparator_get_convergence_summary
        procedure :: generate_report => results_comparator_generate_report
        procedure :: export_to_csv => results_comparator_export_to_csv
        procedure :: finalize => results_comparator_finalize
    end type results_comparator_t

contains

    subroutine results_comparator_initialize(this, max_cases)
        class(results_comparator_t), intent(inout) :: this
        integer, intent(in) :: max_cases
        
        allocate(this%case_results(max_cases))
        this%n_cases = 0
    end subroutine results_comparator_initialize

    subroutine results_comparator_add_result(this, case_name, impl_name, result)
        class(results_comparator_t), intent(inout) :: this
        character(len=*), intent(in) :: case_name
        character(len=*), intent(in) :: impl_name
        type(vmec_result_t), intent(in) :: result
        integer :: i, j
        logical :: case_found
        
        case_found = .false.
        
        ! Find or create case entry
        do i = 1, this%n_cases
            if (this%case_results(i)%case_name == case_name) then
                case_found = .true.
                exit
            end if
        end do
        
        if (.not. case_found) then
            this%n_cases = this%n_cases + 1
            i = this%n_cases
            this%case_results(i)%case_name = trim(case_name)
            allocate(character(len=64) :: this%case_results(i)%impl_names(20))
            allocate(this%case_results(i)%results(20))
            this%case_results(i)%n_impls = 0
        end if
        
        ! Add implementation result
        this%case_results(i)%n_impls = this%case_results(i)%n_impls + 1
        j = this%case_results(i)%n_impls
        this%case_results(i)%impl_names(j) = trim(impl_name)
        this%case_results(i)%results(j) = result
    end subroutine results_comparator_add_result

    subroutine results_comparator_create_comparison_table(this, unit)
        class(results_comparator_t), intent(in) :: this
        integer, intent(in) :: unit
        integer :: i, j
        character(len=128) :: fmt
        
        write(unit, '(A)') "## Key Quantities Comparison"
        write(unit, '(A)') ""
        
        do i = 1, this%n_cases
            write(unit, '(A)') "### " // trim(this%case_results(i)%case_name)
            write(unit, '(A)') ""
            
            ! Table header
            write(unit, '(A)', advance='no') "| Implementation "
            do j = 1, 6
                write(unit, '(A)', advance='no') "| " // trim(this%key_quantities(j)) // " "
            end do
            write(unit, '(A)') "|"
            
            ! Separator
            write(unit, '(A)', advance='no') "|----------------|"
            do j = 1, 6
                write(unit, '(A)', advance='no') "----------------|"
            end do
            write(unit, '(A)') ""
            
            ! Data rows
            do j = 1, this%case_results(i)%n_impls
                if (this%case_results(i)%results(j)%success) then
                    write(unit, '(A,A14)', advance='no') "| ", &
                        this%case_results(i)%impl_names(j)(1:min(14,len_trim(this%case_results(i)%impl_names(j))))
                    write(unit, '(A,ES14.6)', advance='no') " | ", &
                        this%case_results(i)%results(j)%wb
                    write(unit, '(A,ES14.6)', advance='no') " | ", &
                        this%case_results(i)%results(j)%betatotal
                    write(unit, '(A,ES14.6)', advance='no') " | ", &
                        this%case_results(i)%results(j)%aspect
                    write(unit, '(A,ES14.6)', advance='no') " | ", &
                        this%case_results(i)%results(j)%raxis_cc
                    write(unit, '(A,ES14.6)', advance='no') " | ", &
                        this%case_results(i)%results(j)%volume_p
                    write(unit, '(A,ES14.6,A)') " | ", &
                        this%case_results(i)%results(j)%iotaf_edge, " |"
                else
                    write(unit, '(A,A14,A)') "| ", &
                        this%case_results(i)%impl_names(j)(1:min(14,len_trim(this%case_results(i)%impl_names(j)))), &
                        " | Failed | Failed | Failed | Failed | Failed | Failed |"
                end if
            end do
            
            write(unit, '(A)') ""
        end do
    end subroutine results_comparator_create_comparison_table

    subroutine results_comparator_calculate_relative_differences(this, reference_impl, unit)
        class(results_comparator_t), intent(in) :: this
        character(len=*), intent(in) :: reference_impl
        integer, intent(in) :: unit
        integer :: i, j, ref_idx
        real(real64) :: ref_val, impl_val, rel_diff
        logical :: ref_found
        
        write(unit, '(A)') "## Relative Differences"
        write(unit, '(A)') ""
        write(unit, '(A)') "Using " // trim(reference_impl) // " as reference implementation"
        write(unit, '(A)') ""
        
        do i = 1, this%n_cases
            ! Find reference implementation
            ref_found = .false.
            ref_idx = 0
            do j = 1, this%case_results(i)%n_impls
                if (this%case_results(i)%impl_names(j) == reference_impl) then
                    ref_found = .true.
                    ref_idx = j
                    exit
                end if
            end do
            
            if (.not. ref_found .or. &
                .not. this%case_results(i)%results(ref_idx)%success) then
                cycle
            end if
            
            write(unit, '(A)') "### " // trim(this%case_results(i)%case_name)
            write(unit, '(A)') ""
            
            do j = 1, this%case_results(i)%n_impls
                if (j == ref_idx) cycle
                if (.not. this%case_results(i)%results(j)%success) cycle
                
                write(unit, '(A)') "**" // trim(this%case_results(i)%impl_names(j)) // "**:"
                
                ! Calculate relative differences for each quantity
                ref_val = this%case_results(i)%results(ref_idx)%wb
                impl_val = this%case_results(i)%results(j)%wb
                if (abs(ref_val) > 0.0_real64) then
                    rel_diff = (impl_val - ref_val) / abs(ref_val)
                    write(unit, '(A,ES12.4)') "- wb relative difference: ", rel_diff
                end if
                
                ref_val = this%case_results(i)%results(ref_idx)%betatotal
                impl_val = this%case_results(i)%results(j)%betatotal
                if (abs(ref_val) > 0.0_real64) then
                    rel_diff = (impl_val - ref_val) / abs(ref_val)
                    write(unit, '(A,ES12.4)') "- betatotal relative difference: ", rel_diff
                end if
                
                write(unit, '(A)') ""
            end do
        end do
    end subroutine results_comparator_calculate_relative_differences

    subroutine results_comparator_get_convergence_summary(this, unit)
        class(results_comparator_t), intent(in) :: this
        integer, intent(in) :: unit
        integer :: i, j
        
        write(unit, '(A)') "## Convergence Summary"
        write(unit, '(A)') ""
        
        ! Table header
        write(unit, '(A)', advance='no') "| Case "
        
        ! Get unique implementation names
        do i = 1, this%n_cases
            do j = 1, this%case_results(i)%n_impls
                write(unit, '(A,A14,A)', advance='no') "| ", &
                    this%case_results(i)%impl_names(j)(1:min(14,len_trim(this%case_results(i)%impl_names(j)))), &
                    " "
            end do
            exit  ! Just need first case for headers
        end do
        write(unit, '(A)') "|"
        
        ! Separator
        write(unit, '(A)', advance='no') "|------|"
        do i = 1, this%n_cases
            do j = 1, this%case_results(i)%n_impls
                write(unit, '(A)', advance='no') "----------------|"
            end do
            exit
        end do
        write(unit, '(A)') ""
        
        ! Data rows
        do i = 1, this%n_cases
            write(unit, '(A,A)', advance='no') "| ", &
                this%case_results(i)%case_name(1:min(64,len_trim(this%case_results(i)%case_name)))
            
            do j = 1, this%case_results(i)%n_impls
                if (this%case_results(i)%results(j)%success) then
                    write(unit, '(A)', advance='no') "| ✓ "
                else
                    write(unit, '(A)', advance='no') "| ✗ "
                end if
            end do
            write(unit, '(A)') "|"
        end do
        
        write(unit, '(A)') ""
    end subroutine results_comparator_get_convergence_summary

    subroutine results_comparator_generate_report(this, output_file)
        class(results_comparator_t), intent(in) :: this
        character(len=*), intent(in) :: output_file
        integer :: unit, iostat
        
        open(newunit=unit, file=output_file, status='replace', action='write', iostat=iostat)
        if (iostat /= 0) then
            write(error_unit, '(A)') "Failed to create report file: " // trim(output_file)
            return
        end if
        
        write(unit, '(A)') "# VMEC Implementation Comparison Report"
        write(unit, '(A)') ""
        write(unit, '(A)') "Generated by VMEC Benchmark Suite (Fortran version)"
        write(unit, '(A)') ""
        
        ! Convergence summary
        call this%get_convergence_summary(unit)
        
        ! Key quantities comparison
        call this%create_comparison_table(unit)
        
        ! Relative differences (if we have at least one implementation)
        if (this%n_cases > 0 .and. this%case_results(1)%n_impls > 0) then
            call this%calculate_relative_differences( &
                this%case_results(1)%impl_names(1), unit)
        end if
        
        close(unit)
        
        write(output_unit, '(A)') "Report saved to " // trim(output_file)
    end subroutine results_comparator_generate_report

    subroutine results_comparator_export_to_csv(this, output_dir)
        class(results_comparator_t), intent(in) :: this
        character(len=*), intent(in) :: output_dir
        integer :: unit, i, j, iostat
        character(len=:), allocatable :: filename
        
        ! Create output directory
        call execute_command_line("mkdir -p " // trim(output_dir))
        
        ! Export comparison table
        filename = trim(output_dir) // "/comparison_table.csv"
        open(newunit=unit, file=filename, status='replace', action='write', iostat=iostat)
        if (iostat == 0) then
            ! Header
            write(unit, '(A)') "case,implementation,wb,betatotal,aspect,raxis_cc,volume_p,iotaf_edge"
            
            ! Data
            do i = 1, this%n_cases
                do j = 1, this%case_results(i)%n_impls
                    if (this%case_results(i)%results(j)%success) then
                        write(unit, '(A,",",A,6(",",ES14.6))') &
                            trim(this%case_results(i)%case_name), &
                            trim(this%case_results(i)%impl_names(j)), &
                            this%case_results(i)%results(j)%wb, &
                            this%case_results(i)%results(j)%betatotal, &
                            this%case_results(i)%results(j)%aspect, &
                            this%case_results(i)%results(j)%raxis_cc, &
                            this%case_results(i)%results(j)%volume_p, &
                            this%case_results(i)%results(j)%iotaf_edge
                    end if
                end do
            end do
            
            close(unit)
            write(output_unit, '(A)') "CSV files exported to " // trim(output_dir)
        end if
    end subroutine results_comparator_export_to_csv

    subroutine results_comparator_finalize(this)
        class(results_comparator_t), intent(inout) :: this
        integer :: i
        
        if (allocated(this%case_results)) then
            do i = 1, this%n_cases
                if (allocated(this%case_results(i)%case_name)) &
                    deallocate(this%case_results(i)%case_name)
                if (allocated(this%case_results(i)%impl_names)) &
                    deallocate(this%case_results(i)%impl_names)
                if (allocated(this%case_results(i)%results)) &
                    deallocate(this%case_results(i)%results)
            end do
            deallocate(this%case_results)
        end if
        
        this%n_cases = 0
    end subroutine results_comparator_finalize

end module results_comparator