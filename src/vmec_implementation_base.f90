module vmec_implementation_base
    use iso_fortran_env, only: int32, real64, error_unit
    use vmec_benchmark_types, only: vmec_result_t
    implicit none
    private

    public :: vmec_implementation_t

    type, abstract :: vmec_implementation_t
        character(len=:), allocatable :: name
        character(len=:), allocatable :: path
        logical :: available = .false.
        character(len=:), allocatable :: executable
    contains
        procedure :: initialize => vmec_implementation_initialize
        procedure :: is_available => vmec_implementation_is_available
        procedure :: validate_input => vmec_implementation_validate_input
        procedure :: prepare_output_dir => vmec_implementation_prepare_output_dir
        procedure(build_interface), deferred :: build
        procedure(run_case_interface), deferred :: run_case
        procedure(extract_results_interface), deferred :: extract_results
        procedure :: finalize => vmec_implementation_finalize
    end type vmec_implementation_t

    abstract interface
        function build_interface(this) result(success)
            import :: vmec_implementation_t
            class(vmec_implementation_t), intent(inout) :: this
            logical :: success
        end function build_interface

        function run_case_interface(this, input_file, output_dir, timeout) result(success)
            import :: vmec_implementation_t
            class(vmec_implementation_t), intent(inout) :: this
            character(len=*), intent(in) :: input_file
            character(len=*), intent(in) :: output_dir
            integer, intent(in), optional :: timeout
            logical :: success
        end function run_case_interface

        subroutine extract_results_interface(this, output_dir, results)
            import :: vmec_implementation_t, vmec_result_t
            class(vmec_implementation_t), intent(in) :: this
            character(len=*), intent(in) :: output_dir
            type(vmec_result_t), intent(out) :: results
        end subroutine extract_results_interface
    end interface

contains

    subroutine vmec_implementation_initialize(this, name, path)
        class(vmec_implementation_t), intent(inout) :: this
        character(len=*), intent(in) :: name
        character(len=*), intent(in) :: path
        
        this%name = trim(name)
        this%path = trim(path)
        this%available = .false.
    end subroutine vmec_implementation_initialize

    function vmec_implementation_is_available(this) result(is_available)
        class(vmec_implementation_t), intent(in) :: this
        logical :: is_available
        
        is_available = this%available
    end function vmec_implementation_is_available

    function vmec_implementation_validate_input(this, input_file) result(valid)
        class(vmec_implementation_t), intent(in) :: this
        character(len=*), intent(in) :: input_file
        logical :: valid
        logical :: exists, is_file
        
        valid = .false.
        
        inquire(file=trim(input_file), exist=exists)
        if (.not. exists) then
            write(error_unit, '(A)') "Input file does not exist: " // trim(input_file)
            return
        end if
        
        ! Check if it's a regular file (not a directory)
        inquire(file=trim(input_file), exist=is_file)
        if (is_file) then
            valid = .true.
        else
            write(error_unit, '(A)') "Input path is not a file: " // trim(input_file)
        end if
    end function vmec_implementation_validate_input

    function vmec_implementation_prepare_output_dir(this, output_dir) result(success)
        class(vmec_implementation_t), intent(in) :: this
        character(len=*), intent(in) :: output_dir
        logical :: success
        integer :: stat
        
        call execute_command_line("mkdir -p " // trim(output_dir), exitstat=stat)
        success = (stat == 0)
        
        if (.not. success) then
            write(error_unit, '(A)') "Failed to create output directory: " // trim(output_dir)
        end if
    end function vmec_implementation_prepare_output_dir

    subroutine vmec_implementation_finalize(this)
        class(vmec_implementation_t), intent(inout) :: this
        
        if (allocated(this%name)) deallocate(this%name)
        if (allocated(this%path)) deallocate(this%path)
        if (allocated(this%executable)) deallocate(this%executable)
        this%available = .false.
    end subroutine vmec_implementation_finalize

end module vmec_implementation_base