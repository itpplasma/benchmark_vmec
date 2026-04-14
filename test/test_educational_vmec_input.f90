program test_educational_vmec_input
    use iso_fortran_env, only: error_unit, output_unit
    use educational_vmec_implementation, only: educational_vmec_t
    implicit none

    integer :: n_tests, n_passed

    n_tests = 0
    n_passed = 0

    write(output_unit, '(A)') "Running educational VMEC input-cleaning tests..."

    call test_clean_input_drops_duplicate_niter_and_renames_axis(n_tests, n_passed)
    call test_clean_input_rewrites_niter_without_niter_array(n_tests, n_passed)

    write(output_unit, '(/,A,I0,A,I0,A)') "Tests passed: ", n_passed, "/", n_tests, " tests"

    if (n_passed /= n_tests) then
        write(error_unit, '(A)') "Some tests failed!"
        stop 1
    end if

contains

    subroutine test_clean_input_drops_duplicate_niter_and_renames_axis(n_tests, n_passed)
        integer, intent(inout) :: n_tests, n_passed
        type(educational_vmec_t) :: impl
        character(len=*), parameter :: input_file = "/tmp/benchmark_vmec_edu_input_1.txt"
        character(len=*), parameter :: output_file = "/tmp/benchmark_vmec_edu_output_1.txt"
        integer :: unit, stat
        logical :: success

        n_tests = n_tests + 1

        open(newunit=unit, file=input_file, status='replace', action='write', iostat=stat)
        write(unit, '(A)') "&INDATA"
        write(unit, '(A)') "  LOPTIM = F"
        write(unit, '(A)') "  NITER_ARRAY = 2500"
        write(unit, '(A)') "  NITER = 2500"
        write(unit, '(A)') "  RAXIS = 1.0 0.1"
        write(unit, '(A)') "  ZAXIS = 0.0 0.2"
        write(unit, '(A)') "/"
        close(unit)

        success = impl%clean_input_for_educational_vmec(input_file, output_file)

        if (success .and. file_contains(output_file, "NITER_ARRAY = 2500") .and. &
            .not. file_contains(output_file, "NITER = 2500") .and. &
            .not. file_contains(output_file, "LOPTIM") .and. &
            file_contains(output_file, "RAXIS_CC = 1.0 0.1") .and. &
            file_contains(output_file, "ZAXIS_CS = 0.0 0.2")) then
            n_passed = n_passed + 1
            write(output_unit, '(A)') "✓ test_clean_input_drops_duplicate_niter_and_renames_axis"
        else
            write(error_unit, '(A)') "✗ test_clean_input_drops_duplicate_niter_and_renames_axis"
        end if

        call execute_command_line("rm -f " // input_file // " " // output_file, exitstat=stat)
    end subroutine test_clean_input_drops_duplicate_niter_and_renames_axis

    subroutine test_clean_input_rewrites_niter_without_niter_array(n_tests, n_passed)
        integer, intent(inout) :: n_tests, n_passed
        type(educational_vmec_t) :: impl
        character(len=*), parameter :: input_file = "/tmp/benchmark_vmec_edu_input_2.txt"
        character(len=*), parameter :: output_file = "/tmp/benchmark_vmec_edu_output_2.txt"
        integer :: unit, stat
        logical :: success

        n_tests = n_tests + 1

        open(newunit=unit, file=input_file, status='replace', action='write', iostat=stat)
        write(unit, '(A)') "&INDATA"
        write(unit, '(A)') "  NITER = 5000"
        write(unit, '(A)') "/"
        close(unit)

        success = impl%clean_input_for_educational_vmec(input_file, output_file)

        if (success .and. file_contains(output_file, "NITER_ARRAY = 5000") .and. &
            .not. file_contains(output_file, "NITER = 5000")) then
            n_passed = n_passed + 1
            write(output_unit, '(A)') "✓ test_clean_input_rewrites_niter_without_niter_array"
        else
            write(error_unit, '(A)') "✗ test_clean_input_rewrites_niter_without_niter_array"
        end if

        call execute_command_line("rm -f " // input_file // " " // output_file, exitstat=stat)
    end subroutine test_clean_input_rewrites_niter_without_niter_array

    logical function file_contains(path, needle)
        character(len=*), intent(in) :: path
        character(len=*), intent(in) :: needle
        character(len=512) :: line
        integer :: unit, stat

        file_contains = .false.

        open(newunit=unit, file=path, status='old', action='read', iostat=stat)
        if (stat /= 0) return

        do
            read(unit, '(A)', iostat=stat) line
            if (stat /= 0) exit
            if (index(line, needle) > 0) then
                file_contains = .true.
                exit
            end if
        end do

        close(unit)
    end function file_contains

end program test_educational_vmec_input
