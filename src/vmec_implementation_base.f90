module vmec_implementation_base
    use iso_fortran_env, only: int32, real64, error_unit
    use vmec_benchmark_types, only: vmec_result_t
    implicit none
    private

    public :: vmec_implementation_t, select_python_command, prepare_vmec_input, &
        read_unsupported_marker, shell_quote
    public :: temporary_path

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

    function temporary_path(prefix) result(path)
        character(len=*), intent(in) :: prefix
        character(len=:), allocatable :: path
        character(len=128) :: tag_value
        integer :: tag_length, tag_status

        ! Each Slurm allocation gets its own namespace.  The benchmark runs
        ! several Fortran drivers concurrently on the same node, so fixed
        ! names under /tmp would let discovery/result extraction overwrite a
        ! neighbour's file.  BENCHMARK_TEMP_TAG is useful for local parallel
        ! smoke tests; otherwise local runs share a harmless ``local`` tag.
        call get_environment_variable('BENCHMARK_TEMP_TAG', tag_value, &
                                      length=tag_length, status=tag_status)
        if (tag_status /= 0 .or. tag_length <= 0) then
            call get_environment_variable('SLURM_JOB_ID', tag_value, &
                                          length=tag_length, status=tag_status)
        end if
        if (tag_status /= 0 .or. tag_length <= 0) then
            tag_value = 'local'
            tag_length = len_trim(tag_value)
        end if
        path = '/tmp/' // trim(prefix) // '_' // trim(tag_value(:tag_length)) // '.tmp'
    end function temporary_path

    logical function prepare_vmec_input(input_file, output_file, implementation_path) result(success)
        character(len=*), intent(in) :: input_file, output_file, implementation_path
        character(len=:), allocatable :: benchmark_root, source_dir, python_cmd, cmd
        character(len=1024) :: root_value
        integer :: root_length, root_status, last_slash, stat

        success = .false.
        call get_environment_variable('BENCHMARK_REPO_ROOT', root_value, &
                                      length=root_length, status=root_status)
        if (root_status == 0 .and. root_length > 0) then
            benchmark_root = trim(root_value(1:root_length))
        else
            ! Local smoke tests are launched from the benchmark checkout.
            benchmark_root = '.'
        end if

        last_slash = index(trim(input_file), '/', back=.true.)
        if (last_slash > 1) then
            source_dir = trim(input_file(:last_slash-1))
        else
            source_dir = '.'
        end if
        python_cmd = select_python_command(implementation_path)
        ! Input fixtures can live below directories containing spaces (the
        ! educational_VMEC Free Boundary corpus is one such case).  Every
        ! path passed through the shell must therefore be quoted as a single
        ! argument; the Python helper itself handles the actual file I/O.
        cmd = shell_quote(python_cmd) // ' ' // &
              shell_quote(trim(benchmark_root) // '/tools/prepare_vmec_input.py') // ' ' // &
              shell_quote(input_file) // ' ' // shell_quote(output_file) // &
              ' --search-root ' // shell_quote(source_dir)
        call execute_command_line(trim(cmd), exitstat=stat)
        success = (stat == 0)
        if (.not. success) then
            write(error_unit, '(A)') 'Failed to prepare VMEC input: ' // trim(input_file)
        end if
    end function prepare_vmec_input

    logical function read_unsupported_marker(output_dir, message) result(found)
        character(len=*), intent(in) :: output_dir
        character(len=:), allocatable, intent(out) :: message
        character(len=2048) :: line
        integer :: unit, stat

        found = .false.
        message = ''
        open(newunit=unit, file=trim(output_dir) // '/benchmark_unsupported.txt', &
             status='old', action='read', iostat=stat)
        if (stat /= 0) return
        read(unit, '(A)', iostat=stat) line
        close(unit)
        if (stat == 0 .and. len_trim(line) > 0) then
            message = trim(line)
            found = .true.
        end if
    end function read_unsupported_marker

    function select_python_command(repo_path) result(python_cmd)
        character(len=*), intent(in) :: repo_path
        character(len=:), allocatable :: python_cmd
        character(len=512) :: env_python
        integer :: env_status, env_length
        logical :: exists

        call get_environment_variable("VMEC_BENCHMARK_PYTHON", env_python, &
                                      length=env_length, status=env_status)
        if (env_status == 0 .and. env_length > 0) then
            inquire(file=trim(env_python(1:env_length)), exist=exists)
            if (exists) then
                python_cmd = trim(env_python(1:env_length))
                return
            end if
        end if

        inquire(file=trim(repo_path) // "/.venv/bin/python", exist=exists)
        if (exists) then
            python_cmd = trim(repo_path) // "/.venv/bin/python"
            return
        end if

        python_cmd = "python3"
    end function select_python_command

    subroutine vmec_implementation_initialize(this, name, path)
        class(vmec_implementation_t), intent(inout) :: this
        character(len=*), intent(in) :: name
        character(len=*), intent(in) :: path
        character(len=512) :: resolved_path
        character(len=:), allocatable :: resolved_path_file
        integer :: stat, unit, io_status
        
        this%name = trim(name)
        this%path = trim(path)

        ! Repository paths are commonly supplied relative to the benchmark
        ! process.  Runs happen in per-case output directories, so retain an
        ! absolute path for executables, Python environments, and Java class
        ! paths used after that directory change.
        resolved_path_file = temporary_path('vmec_implementation_path')
        call execute_command_line("realpath -m " // shell_quote(path) // &
            " > " // shell_quote(resolved_path_file), exitstat=stat)
        if (stat == 0) then
            open(newunit=unit, file=resolved_path_file, &
                status="old", action="read", iostat=io_status)
            if (io_status == 0) then
                read(unit, '(A)', iostat=io_status) resolved_path
                close(unit)
                if (io_status == 0 .and. len_trim(resolved_path) > 0) then
                    this%path = trim(adjustl(resolved_path))
                end if
            end if
        end if
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
        
        call execute_command_line("mkdir -p " // shell_quote(output_dir), exitstat=stat)
        success = (stat == 0)
        
        if (.not. success) then
            write(error_unit, '(A)') "Failed to create output directory: " // trim(output_dir)
        end if
    end function vmec_implementation_prepare_output_dir

    function shell_quote(text) result(quoted)
        character(len=*), intent(in) :: text
        character(len=:), allocatable :: quoted

        ! Repository and output paths are controlled by the benchmark.  A
        ! single-quoted shell argument preserves spaces and shell metacharacters
        ! without changing the path seen by the child process.
        quoted = "'" // trim(text) // "'"
    end function shell_quote

    subroutine vmec_implementation_finalize(this)
        class(vmec_implementation_t), intent(inout) :: this
        
        if (allocated(this%name)) deallocate(this%name)
        if (allocated(this%path)) deallocate(this%path)
        if (allocated(this%executable)) deallocate(this%executable)
        this%available = .false.
    end subroutine vmec_implementation_finalize

end module vmec_implementation_base
