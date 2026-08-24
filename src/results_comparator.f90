module results_comparator
    use iso_fortran_env, only: int32, real64, error_unit, output_unit
    use vmec_benchmark_types, only: vmec_result_t
    use jvmec_comparison, only: generate_jvmec_quantitative_summary
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
        character(len=:), allocatable :: output_dir
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
        procedure :: write_fourier_summary => write_fourier_summary
        procedure :: generate_jvmec_reports => generate_jvmec_reports
        procedure :: finalize => results_comparator_finalize
    end type results_comparator_t

contains

    subroutine results_comparator_initialize(this, max_cases, output_dir)
        class(results_comparator_t), intent(inout) :: this
        integer, intent(in) :: max_cases
        character(len=*), intent(in), optional :: output_dir
        integer :: stat

        allocate(this%case_results(max_cases))
        this%n_cases = 0
        if (present(output_dir)) then
            this%output_dir = trim(output_dir)
        else
            this%output_dir = "benchmark_results"
        end if
        call execute_command_line("mkdir -p " // trim(this%output_dir), exitstat=stat)
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
            allocate(character(len=64) :: this%case_results(i)%impl_names(32))
            allocate(this%case_results(i)%results(32))
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
                    write(unit, '(A,A)', advance='no') "| ", trim(this%case_results(i)%impl_names(j))
                    if (trim(result_family(this%case_results(i)%results(j))) == 'vmec_family') then
                        write(unit, '(A,ES14.6)', advance='no') " | ", this%case_results(i)%results(j)%wb
                        write(unit, '(A,ES14.6)', advance='no') " | ", this%case_results(i)%results(j)%betatotal
                        write(unit, '(A,ES14.6)', advance='no') " | ", this%case_results(i)%results(j)%aspect
                        write(unit, '(A,ES14.6)', advance='no') " | ", this%case_results(i)%results(j)%raxis_cc
                        write(unit, '(A,ES14.6)', advance='no') " | ", this%case_results(i)%results(j)%volume_p
                        write(unit, '(A,ES14.6,A)') " | ", this%case_results(i)%results(j)%iotaf_edge, " |"
                    else
                        write(unit, '(A)') " | n/a | n/a | n/a | n/a | n/a | n/a |"
                    end if
                else
                    write(unit, '(A,A,A)') "| ", &
                        trim(this%case_results(i)%impl_names(j)), &
                        " | Failed | Failed | Failed | Failed | Failed | Failed |"
                end if
            end do

            write(unit, '(A)') ""
        end do
    end subroutine results_comparator_create_comparison_table

    subroutine results_comparator_calculate_relative_differences(this, unit)
        class(results_comparator_t), intent(in) :: this
        integer, intent(in) :: unit
        integer :: i, j, ref_idx
        real(real64) :: ref_val, impl_val, rel_diff
        logical :: has_reference_section

        write(unit, '(A)') "## Relative Differences"
        write(unit, '(A)') ""
        write(unit, '(A)') "Reference priority: educational_vmec, vmec2000, vmex, jvmec, vmecpp, desc, gvec"
        write(unit, '(A)') ""

        has_reference_section = .false.

        do i = 1, this%n_cases
            ref_idx = choose_case_reference(this%case_results(i))

            if (ref_idx == 0) cycle
            has_reference_section = .true.

            write(unit, '(A)') "### " // trim(this%case_results(i)%case_name)
            write(unit, '(A)') ""
            write(unit, '(A)') "Reference implementation: " // &
                trim(this%case_results(i)%impl_names(ref_idx))
            write(unit, '(A)') ""

            do j = 1, this%case_results(i)%n_impls
                if (j == ref_idx) cycle
                if (.not. this%case_results(i)%results(j)%success) cycle
                ! WOUT scalars are only meaningful within the same physical
                ! family and dimensionality.  A 2-D GEQDSK result must never
                ! be compared numerically with a 3-D VMEC WOUT row.
                if (.not. same_domain(this%case_results(i)%results(ref_idx), &
                    this%case_results(i)%results(j))) cycle

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

        if (.not. has_reference_section) then
            write(unit, '(A)') "No successful implementations were available for relative differences."
            write(unit, '(A)') ""
        end if
    end subroutine results_comparator_calculate_relative_differences

    subroutine results_comparator_get_convergence_summary(this, unit)
        class(results_comparator_t), intent(in) :: this
        integer, intent(in) :: unit
        integer :: i, j, k, n_headers
        character(len=64) :: headers(20)
        logical :: already_present

        write(unit, '(A)') "## Convergence Summary"
        write(unit, '(A)') ""

        headers = ""
        n_headers = 0
        do i = 1, this%n_cases
            do j = 1, this%case_results(i)%n_impls
                already_present = .false.
                do k = 1, n_headers
                    if (trim(headers(k)) == trim(this%case_results(i)%impl_names(j))) then
                        already_present = .true.
                        exit
                    end if
                end do
                if (.not. already_present) then
                    n_headers = n_headers + 1
                    headers(n_headers) = trim(this%case_results(i)%impl_names(j))
                end if
            end do
        end do

        ! Table header
        write(unit, '(A)', advance='no') "| Case "
        do i = 1, n_headers
            write(unit, '(A,A,A)', advance='no') "| ", trim(headers(i)), " "
        end do
        write(unit, '(A)') "|"

        ! Separator
        write(unit, '(A)', advance='no') "|------|"
        do i = 1, n_headers
            write(unit, '(A)', advance='no') "----------------|"
        end do
        write(unit, '(A)') ""

        ! Data rows
        do i = 1, this%n_cases
            write(unit, '(A,A)', advance='no') "| ", &
                trim(this%case_results(i)%case_name)

            do j = 1, n_headers
                do k = 1, this%case_results(i)%n_impls
                    if (trim(this%case_results(i)%impl_names(k)) == trim(headers(j))) then
                        if (this%case_results(i)%results(k)%success) then
                            write(unit, '(A)', advance='no') "| ✓ "
                        else
                            write(unit, '(A)', advance='no') "| ✗ "
                        end if
                        exit
                    end if
                end do
                if (k > this%case_results(i)%n_impls) then
                    write(unit, '(A)', advance='no') "| - "
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
            call this%calculate_relative_differences(unit)
        end if

        ! Fourier coefficient summary
        call this%write_fourier_summary(unit)

        close(unit)

        ! Generate jVMEC-specific quantitative reports
        call this%generate_jvmec_reports()

        write(output_unit, '(A)') "Report saved to " // trim(output_file)
    end subroutine results_comparator_generate_report

    subroutine results_comparator_export_to_csv(this, output_dir)
        class(results_comparator_t), intent(in) :: this
        character(len=*), intent(in) :: output_dir
        integer :: unit, i, j, iostat
        character(len=:), allocatable :: filename
        character(len=256) :: case_name, implementation, status, error_text
        character(len=64) :: family, input_format, output_format

        ! Create output directory
        call execute_command_line("mkdir -p " // trim(output_dir))

        ! Export comparison table
        filename = trim(output_dir) // "/comparison_table.csv"
        open(newunit=unit, file=filename, status='replace', action='write', iostat=iostat)
        if (iostat == 0) then
            ! Header
            write(unit, '(A)') "case,implementation,status,error,dimension,family,input_format," // &
                "output_format,wb,betatotal,aspect,raxis_cc,volume_p,iotaf_edge," // &
                "pressure_axis,plasma_current"

            ! Data
            do i = 1, this%n_cases
                do j = 1, this%case_results(i)%n_impls
                    case_name = trim(this%case_results(i)%case_name)
                    implementation = trim(this%case_results(i)%impl_names(j))
                    if (this%case_results(i)%results(j)%success) then
                        status = 'success'
                    else
                        status = 'failed'
                    end if
                    error_text = ''
                    if (allocated(this%case_results(i)%results(j)%error_message)) then
                        error_text = trim(this%case_results(i)%results(j)%error_message)
                    end if
                    family = ''
                    if (allocated(this%case_results(i)%results(j)%family)) then
                        family = trim(this%case_results(i)%results(j)%family)
                    end if
                    input_format = ''
                    if (allocated(this%case_results(i)%results(j)%input_format)) then
                        input_format = trim(this%case_results(i)%results(j)%input_format)
                    end if
                    output_format = ''
                    if (allocated(this%case_results(i)%results(j)%output_format)) then
                        output_format = trim(this%case_results(i)%results(j)%output_format)
                    end if
                    write(unit, '(A,",",A,",",A,",",A,",",I0,",",A,",",A,",",A)', advance='no') &
                        trim(case_name), trim(implementation), trim(status), trim(error_text), &
                        this%case_results(i)%results(j)%dimension, &
                        trim(family), trim(input_format), trim(output_format)
                    if (this%case_results(i)%results(j)%success) then
                        write(unit, '(8(",",ES14.6))') this%case_results(i)%results(j)%wb, &
                            this%case_results(i)%results(j)%betatotal, this%case_results(i)%results(j)%aspect, &
                            this%case_results(i)%results(j)%raxis_cc, this%case_results(i)%results(j)%volume_p, &
                            this%case_results(i)%results(j)%iotaf_edge, &
                            this%case_results(i)%results(j)%pressure_axis, &
                            this%case_results(i)%results(j)%plasma_current
                    else
                        write(unit, '(A)') ",,,,,,,,,,,,,,,,,"
                    end if
                end do
            end do

            close(unit)
            write(output_unit, '(A)') "CSV files exported to " // trim(output_dir)
        end if
    end subroutine results_comparator_export_to_csv

    subroutine write_fourier_summary(this, unit)
        class(results_comparator_t), intent(in) :: this
        integer, intent(in) :: unit
        integer :: i, j

        write(unit, '(A)') ""
        write(unit, '(A)') "## Fourier Coefficients Summary"
        write(unit, '(A)') ""

        do i = 1, this%n_cases
            write(unit, '(A)') "### " // this%case_results(i)%case_name
            write(unit, '(A)') ""

            write(unit, '(A)') "| Implementation | ns | mnmax | rmnc(1,1) | zmns(1,1) | lmns(1,1) |"
            write(unit, '(A)') "|---|---|---|---|---|---|"

            do j = 1, this%case_results(i)%n_impls
                if (this%case_results(i)%results(j)%success) then
                    call write_fourier_row(unit, this%case_results(i)%impl_names(j), &
                        this%case_results(i)%results(j))
                else
                    write(unit, '(A,A,A)') "| ", trim(this%case_results(i)%impl_names(j)), &
                        " | Failed | Failed | Failed | Failed | Failed |"
                end if
            end do
            write(unit, '(A)') ""
        end do
    end subroutine write_fourier_summary

    subroutine write_fourier_row(unit, impl_name, result)
        integer, intent(in) :: unit
        character(len=*), intent(in) :: impl_name
        type(vmec_result_t), intent(in) :: result

        integer :: ns, mnmax
        real(real64) :: rmnc_11, zmns_11, lmns_11

        ns = 0
        mnmax = 0
        rmnc_11 = 0.0_real64
        zmns_11 = 0.0_real64
        lmns_11 = 0.0_real64

        ! Get dimensions and first mode values
        if (allocated(result%rmnc)) then
            ns = size(result%rmnc, 1)
            mnmax = size(result%rmnc, 2)
            if (ns > 0 .and. mnmax > 0) then
                rmnc_11 = result%rmnc(1, 1)
            end if
        end if

        if (allocated(result%zmns)) then
            if (size(result%zmns, 1) > 0 .and. size(result%zmns, 2) > 0) then
                zmns_11 = result%zmns(1, 1)
            end if
        end if

        if (allocated(result%lmns)) then
            if (size(result%lmns, 1) > 0 .and. size(result%lmns, 2) > 0) then
                lmns_11 = result%lmns(1, 1)
            end if
        end if

        write(unit, '(A,A,A,I0,A,I0,A,ES12.5,A,ES12.5,A,ES12.5,A)') &
            "| ", trim(impl_name), " | ", ns, " | ", mnmax, " | ", &
            rmnc_11, " | ", zmns_11, " | ", lmns_11, " |"
    end subroutine write_fourier_row

    subroutine generate_jvmec_reports(this)
        class(results_comparator_t), intent(in) :: this
        integer :: i, stat
        character(len=:), allocatable :: jvmec_report_dir, jvmec_report_file

        jvmec_report_dir = trim(this%output_dir) // "/jvmec_reports"
        call execute_command_line("mkdir -p " // trim(jvmec_report_dir), exitstat=stat)
        if (stat /= 0) then
            write(error_unit, '(A)') "Failed to create jVMEC report directory: " // &
                trim(jvmec_report_dir)
            return
        end if

        do i = 1, this%n_cases
            if (this%case_results(i)%n_impls > 0) then
                jvmec_report_file = trim(jvmec_report_dir) // "/jvmec_quantitative_" // &
                    sanitize_filename(this%case_results(i)%case_name) // ".md"

                call generate_jvmec_quantitative_summary( &
                    this%case_results(i)%results(1:this%case_results(i)%n_impls), &
                    this%case_results(i)%impl_names(1:this%case_results(i)%n_impls), &
                    jvmec_report_file)
            end if
        end do

    end subroutine generate_jvmec_reports

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
        if (allocated(this%output_dir)) deallocate(this%output_dir)

        this%n_cases = 0
    end subroutine results_comparator_finalize

    function sanitize_filename(name) result(filename)
        character(len=*), intent(in) :: name
        character(len=:), allocatable :: filename
        integer :: i
        character(len=1) :: ch

        filename = ""
        do i = 1, len_trim(name)
            ch = name(i:i)
            select case (ch)
            case ('A':'Z', 'a':'z', '0':'9', '-', '_', '.')
                filename = filename // ch
            case ('/')
                filename = filename // "__"
            case default
                filename = filename // "_"
            end select
        end do
    end function sanitize_filename

    integer function choose_case_reference(case_result) result(reference_idx)
        type(case_results_t), intent(in) :: case_result
        integer :: i, j
        character(len=*), parameter :: priority(7) = [ &
            "educational_vmec", &
            "vmec2000        ", &
            "vmex            ", &
            "jvmec           ", &
            "vmecpp          ", &
            "desc            ", &
            "gvec            " &
            ]

        do i = 1, size(priority)
            do j = 1, case_result%n_impls
                if (trim(case_result%impl_names(j)) == trim(priority(i)) .and. &
                    case_result%results(j)%success) then
                    reference_idx = j
                    return
                end if
            end do
        end do

        reference_idx = 0
        do j = 1, case_result%n_impls
            if (case_result%results(j)%success) then
                reference_idx = j
                return
            end if
        end do
    end function choose_case_reference

    logical function same_domain(left, right)
        type(vmec_result_t), intent(in) :: left, right

        same_domain = left%dimension == right%dimension .and. &
            trim(result_family(left)) == trim(result_family(right))
    end function same_domain

    function result_family(result) result(family)
        type(vmec_result_t), intent(in) :: result
        character(len=:), allocatable :: family

        if (allocated(result%family)) then
            family = trim(result%family)
        else
            family = 'vmec_family'
        end if
    end function result_family

end module results_comparator
