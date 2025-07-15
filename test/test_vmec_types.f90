program test_vmec_types
    use iso_fortran_env, only: int32, real64, error_unit, output_unit
    use vmec_benchmark_types, only: repository_config_t, vmec_result_t, string_t
    implicit none
    
    integer :: n_tests, n_passed
    
    n_tests = 0
    n_passed = 0
    
    write(output_unit, '(A)') "Running vmec_benchmark_types tests..."
    
    call test_repository_config_initialize(n_tests, n_passed)
    call test_vmec_result_clear(n_tests, n_passed)
    call test_string_type(n_tests, n_passed)
    
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

end program test_vmec_types