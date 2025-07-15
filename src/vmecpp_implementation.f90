module vmecpp_implementation
    use iso_fortran_env, only: int32, real64, error_unit, output_unit
    use vmec_implementation_base, only: vmec_implementation_t
    use vmec_benchmark_types, only: vmec_result_t
    implicit none
    private

    public :: vmecpp_t

    type, extends(vmec_implementation_t) :: vmecpp_t
    contains
        procedure :: build => vmecpp_build
        procedure :: run_case => vmecpp_run_case
        procedure :: extract_results => vmecpp_extract_results
    end type vmecpp_t

contains

    function vmecpp_build(this) result(success)
        class(vmecpp_t), intent(inout) :: this
        logical :: success
        character(len=:), allocatable :: cmd
        integer :: stat
        logical :: exists

        success = .false.

        inquire(file=trim(this%path), exist=exists)
        if (.not. exists) then
            write(error_unit, '(A)') "VMEC++ path does not exist: " // trim(this%path)
            return
        end if

        write(output_unit, '(A)') "Building VMEC++ with pip install"

        cmd = "cd " // trim(this%path) // " && pip install ."
        call execute_command_line(trim(cmd), exitstat=stat)

        if (stat /= 0) then
            write(error_unit, '(A)') "Failed to build VMEC++ with pip"
            return
        end if

        this%executable = 'python -c "import vmecpp; print(''VMEC++ ready'')"'
        this%available = .true.
        success = .true.
        write(output_unit, '(A)') "Successfully built VMEC++ Python package"
    end function vmecpp_build

    function vmecpp_run_case(this, input_file, output_dir, timeout) result(success)
        class(vmecpp_t), intent(inout) :: this
        character(len=*), intent(in) :: input_file
        character(len=*), intent(in) :: output_dir
        integer, intent(in), optional :: timeout
        logical :: success
        character(len=:), allocatable :: local_input, cmd, python_script, wout_name
        integer :: stat, timeout_val, unit

        success = .false.

        if (.not. this%validate_input(input_file)) return
        if (.not. this%prepare_output_dir(output_dir)) return
        if (.not. this%available) then
            write(error_unit, '(A)') "VMEC++ is not available"
            return
        end if

        timeout_val = 300
        if (present(timeout)) timeout_val = timeout

        local_input = trim(output_dir) // "/" // get_basename(input_file)
        cmd = "cp " // trim(input_file) // " " // trim(local_input)
        call execute_command_line(trim(cmd), exitstat=stat)

        wout_name = "wout_" // get_case_name(input_file) // ".nc"

        python_script = trim(output_dir) // "/run_vmecpp.py"
        open(newunit=unit, file=python_script, status='replace', action='write', iostat=stat)
        if (stat /= 0) then
            write(error_unit, '(A)') "Failed to create Python script"
            return
        end if

        write(unit, '(A)') "import sys"
        write(unit, '(A)') "import os"
        write(unit, '(A)') "try:"
        write(unit, '(A)') "    import vmecpp"
        write(unit, '(A)') "    os.chdir('" // trim(output_dir) // "')"
        write(unit, '(A)') "    vmec_input = vmecpp.VmecInput.from_file('" // get_basename(local_input) // "')"
        write(unit, '(A)') "    vmec_output = vmecpp.run(vmec_input)"
        write(unit, '(A)') "    vmec_output.wout.save('" // trim(wout_name) // "')"
        write(unit, '(A)') "    print('VMEC++ run completed successfully')"
        write(unit, '(A)') "except Exception as e:"
        write(unit, '(A)') "    print(f'VMEC++ failed: {e}')"
        write(unit, '(A)') "    sys.exit(1)"
        close(unit)

        cmd = "cd " // trim(output_dir) // " && timeout " // int_to_str(timeout_val) // &
              " python " // trim(python_script) // " > vmecpp.log 2>&1"

        call execute_command_line(trim(cmd), exitstat=stat)

        if (stat == 0) then
            success = .true.
        else if (stat == 124) then
            write(error_unit, '(A)') "VMEC++ timed out for " // get_basename(input_file)
        else
            write(error_unit, '(A)') "VMEC++ failed for " // get_basename(input_file)
        end if
    end function vmecpp_run_case

    subroutine vmecpp_extract_results(this, output_dir, results)
        class(vmecpp_t), intent(in) :: this
        character(len=*), intent(in) :: output_dir
        type(vmec_result_t), intent(out) :: results
        character(len=256) :: wout_file
        integer :: stat
        logical :: exists

        call results%clear()

        call execute_command_line("ls " // trim(output_dir) // "/wout_*.nc 2>/dev/null", &
                                exitstat=stat, cmdmsg=wout_file)

        if (stat == 0 .and. len_trim(wout_file) > 0) then
            inquire(file=trim(adjustl(wout_file)), exist=exists)
            if (exists) then
                results%success = .true.
            else
                results%error_message = "No wout file found"
            end if
        else
            results%error_message = "No wout file found"
        end if
    end subroutine vmecpp_extract_results

    function get_basename(filename) result(basename)
        character(len=*), intent(in) :: filename
        character(len=:), allocatable :: basename
        integer :: last_slash

        last_slash = index(filename, '/', back=.true.)
        if (last_slash > 0) then
            basename = filename(last_slash+1:)
        else
            basename = filename
        end if
    end function get_basename

    function get_case_name(filepath) result(name)
        character(len=*), intent(in) :: filepath
        character(len=:), allocatable :: name
        integer :: last_slash, last_dot

        last_slash = index(filepath, '/', back=.true.)
        if (last_slash > 0) then
            name = filepath(last_slash+1:)
        else
            name = filepath
        end if

        last_dot = index(name, '.', back=.true.)
        if (last_dot > 0) then
            name = name(1:last_dot-1)
        end if

        if (index(name, "input.") == 1) then
            name = name(7:)
        end if
    end function get_case_name

    function int_to_str(i) result(str)
        integer, intent(in) :: i
        character(len=:), allocatable :: str
        character(len=32) :: temp

        write(temp, '(I0)') i
        str = trim(temp)
    end function int_to_str

end module vmecpp_implementation