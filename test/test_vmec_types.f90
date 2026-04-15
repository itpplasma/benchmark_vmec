program test_vmec_types
    use iso_fortran_env, only: int32, real64, error_unit, output_unit
    use vmec_benchmark_types, only: repository_config_t, vmec_result_t, string_t
    use vmec_implementation_base, only: select_python_command
    use vmecpp_implementation, only: write_vmecpp_runner_script
    implicit none
    
    integer :: n_tests, n_passed
    
    n_tests = 0
    n_passed = 0
    
    write(output_unit, '(A)') "Running vmec_benchmark_types tests..."
    
    call test_repository_config_initialize(n_tests, n_passed)
    call test_vmec_result_clear(n_tests, n_passed)
    call test_string_type(n_tests, n_passed)
    call test_select_python_command_prefers_repo_venv(n_tests, n_passed)
    call test_vmecpp_runner_script_uses_single_thread(n_tests, n_passed)
    
    write(output_unit, '(/,A,I0,A,I0,A)') "Tests passed: ", n_passed, "/", n_tests, " tests"
    
    if (n_passed /= n_tests) then
        write(error_unit, '(A)') "Some tests failed!"
        stop 1
    end if

contains

    subroutine test_repository_config_initialize(n_tests, n_passed)
        integer, intent(inout) :: n_tests, n_passed
        type(repository_config_t) :: config
        
        n_tests = n_tests + 1
        
        call config%initialize( &
            name="Test Repo", &
            url="https://github.com/test/repo.git", &
            branch="develop", &
            build_command="make", &
            test_data_path="tests/data")
        
        if (config%name == "Test Repo" .and. &
            config%url == "https://github.com/test/repo.git" .and. &
            config%branch == "develop" .and. &
            config%build_command == "make" .and. &
            config%test_data_path == "tests/data") then
            n_passed = n_passed + 1
            write(output_unit, '(A)') "✓ test_repository_config_initialize"
        else
            write(error_unit, '(A)') "✗ test_repository_config_initialize"
        end if
    end subroutine test_repository_config_initialize
    
    subroutine test_vmec_result_clear(n_tests, n_passed)
        integer, intent(inout) :: n_tests, n_passed
        type(vmec_result_t) :: result
        
        n_tests = n_tests + 1
        
        ! Set some values
        result%success = .true.
        result%error_message = "Test error"
        result%wb = 1.23_real64
        allocate(result%rmnc(10,10))
        allocate(result%xm(10))
        
        ! Clear
        call result%clear()
        
        if (.not. result%success .and. &
            .not. allocated(result%error_message) .and. &
            result%wb == 0.0_real64 .and. &
            .not. allocated(result%rmnc) .and. &
            .not. allocated(result%xm)) then
            n_passed = n_passed + 1
            write(output_unit, '(A)') "✓ test_vmec_result_clear"
        else
            write(error_unit, '(A)') "✗ test_vmec_result_clear"
        end if
    end subroutine test_vmec_result_clear
    
    subroutine test_string_type(n_tests, n_passed)
        integer, intent(inout) :: n_tests, n_passed
        type(string_t) :: str1, str2
        
        n_tests = n_tests + 1
        
        str1%str = "Hello"
        str2%str = "World"
        
        if (str1%str == "Hello" .and. str2%str == "World") then
            n_passed = n_passed + 1
            write(output_unit, '(A)') "✓ test_string_type"
        else
            write(error_unit, '(A)') "✗ test_string_type"
        end if
    end subroutine test_string_type

    subroutine test_select_python_command_prefers_repo_venv(n_tests, n_passed)
        integer, intent(inout) :: n_tests, n_passed
        character(len=:), allocatable :: python_cmd
        character(len=*), parameter :: repo_dir = "/tmp/benchmark_vmec_python_repo"
        integer :: stat

        n_tests = n_tests + 1

        call execute_command_line("rm -rf " // repo_dir, exitstat=stat)
        call execute_command_line("mkdir -p " // repo_dir // "/.venv/bin", exitstat=stat)
        call execute_command_line("touch " // repo_dir // "/.venv/bin/python", exitstat=stat)

        python_cmd = select_python_command(repo_dir)

        if (trim(python_cmd) == repo_dir // "/.venv/bin/python") then
            n_passed = n_passed + 1
            write(output_unit, '(A)') "✓ test_select_python_command_prefers_repo_venv"
        else
            write(error_unit, '(A)') "✗ test_select_python_command_prefers_repo_venv"
        end if

        call execute_command_line("rm -rf " // repo_dir, exitstat=stat)
    end subroutine test_select_python_command_prefers_repo_venv

    subroutine test_vmecpp_runner_script_uses_single_thread(n_tests, n_passed)
        integer, intent(inout) :: n_tests, n_passed
        character(len=*), parameter :: script_path = "/tmp/benchmark_vmec_vmecpp_runner.py"
        integer :: stat, unit

        n_tests = n_tests + 1

        open(newunit=unit, file=script_path, status="replace", action="write")
        call write_vmecpp_runner_script(unit, "input.test_case")
        close(unit)

        if (file_contains(script_path, "vmecpp.run(vmec_input, max_threads=1, verbose=False)") .and. &
            file_contains(script_path, "output.wout.save('wout_input.nc')")) then
            n_passed = n_passed + 1
            write(output_unit, '(A)') "✓ test_vmecpp_runner_script_uses_single_thread"
        else
            write(error_unit, '(A)') "✗ test_vmecpp_runner_script_uses_single_thread"
        end if

        call execute_command_line("rm -f " // script_path, exitstat=stat)
    end subroutine test_vmecpp_runner_script_uses_single_thread

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

end program test_vmec_types
