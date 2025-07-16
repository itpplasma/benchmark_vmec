module vmec2000_implementation
    use iso_fortran_env, only: int32, real64, error_unit, output_unit
    use vmec_implementation_base, only: vmec_implementation_t
    use vmec_benchmark_types, only: vmec_result_t
    implicit none
    private

    public :: vmec2000_t

    type, extends(vmec_implementation_t) :: vmec2000_t
    contains
        procedure :: build => vmec2000_build
        procedure :: run_case => vmec2000_run_case
        procedure :: extract_results => vmec2000_extract_results
    end type vmec2000_t

contains

    function vmec2000_build(this) result(success)
        class(vmec2000_t), intent(inout) :: this
        logical :: success
        character(len=:), allocatable :: cmd
        integer :: stat
        logical :: exists

        success = .false.

        inquire(file=trim(this%path), exist=exists)
        if (.not. exists) then
            write(error_unit, '(A)') "VMEC2000 path does not exist: " // trim(this%path)
            return
        end if
        
        ! Check if already built by testing if vmec module can be imported
        cmd = 'cd ' // trim(this%path) // ' && python -c "import vmec; print(''VMEC2000 available'')"'
        call execute_command_line(trim(cmd), exitstat=stat)
        if (stat == 0) then
            ! Already built
            this%executable = 'python -c "import vmec; print(''VMEC2000 ready'')"'
            this%available = .true.
            success = .true.
            write(output_unit, '(A)') "VMEC2000 already built (Python module available)"
            return
        end if

        write(output_unit, '(A)') "Building VMEC2000 with pip install"

        ! Install dependencies first
        cmd = "pip install numpy mpi4py"
        call execute_command_line(trim(cmd), exitstat=stat)
        
        if (stat /= 0) then
            write(error_unit, '(A)') "Failed to install VMEC2000 dependencies"
            return
        end if

        ! Update cmake config file for Arch Linux paths if needed
        cmd = "cd " // trim(this%path) // " && " // &
              "if [ -f cmake_config_file.json ]; then " // &
              "cp cmake_config_file.json cmake_config_file.json.bak && " // &
              "sed -i 's|/usr/lib64/openmpi/bin/mpicc|/usr/bin/mpicc|g' cmake_config_file.json && " // &
              "sed -i 's|/usr/lib64/openmpi/bin/mpifort|/usr/bin/mpifort|g' cmake_config_file.json && " // &
              "sed -i 's|/usr/include/openmpi-x86_64|/usr/include|g' cmake_config_file.json && " // &
              "sed -i 's|/usr/lib64/openmpi/lib|/usr/lib|g' cmake_config_file.json; fi && " // &
              "pip install ."
        call execute_command_line(trim(cmd), exitstat=stat)

        if (stat /= 0) then
            write(error_unit, '(A)') "Failed to build VMEC2000 with pip"
            return
        end if

        this%executable = 'python -c "import vmec; print(''VMEC2000 ready'')"'
        this%available = .true.
        success = .true.
        write(output_unit, '(A)') "Successfully built VMEC2000 Python extension"
    end function vmec2000_build

    function vmec2000_run_case(this, input_file, output_dir, timeout) result(success)
        class(vmec2000_t), intent(inout) :: this
        character(len=*), intent(in) :: input_file
        character(len=*), intent(in) :: output_dir
        integer, intent(in), optional :: timeout
        logical :: success
        character(len=:), allocatable :: local_input, cmd, python_script
        integer :: stat, timeout_val, unit

        success = .false.

        if (.not. this%validate_input(input_file)) return
        if (.not. this%prepare_output_dir(output_dir)) return
        if (.not. this%available) then
            write(error_unit, '(A)') "VMEC2000 is not available"
            return
        end if

        timeout_val = 300
        if (present(timeout)) timeout_val = timeout

        local_input = trim(output_dir) // "/" // get_basename(input_file)
        cmd = "cp " // trim(input_file) // " " // trim(local_input)
        call execute_command_line(trim(cmd), exitstat=stat)

        python_script = trim(output_dir) // "/run_vmec2000.py"
        open(newunit=unit, file=python_script, status='replace', action='write', iostat=stat)
        if (stat /= 0) then
            write(error_unit, '(A)') "Failed to create Python script"
            return
        end if

        write(unit, '(A)') "import sys"
        write(unit, '(A)') "import os"
        write(unit, '(A)') "import numpy as np"
        write(unit, '(A)') "try:"
        write(unit, '(A)') "    from mpi4py import MPI"
        write(unit, '(A)') "    fcomm = MPI.COMM_WORLD.py2f()"
        write(unit, '(A)') "except ImportError:"
        write(unit, '(A)') "    # Fallback for systems without MPI"
        write(unit, '(A)') "    fcomm = -1"
        write(unit, '(A)') "try:"
        write(unit, '(A)') "    import vmec"
        write(unit, '(A)') "    # Already in correct directory"
        write(unit, '(A)') "    # Setup VMEC2000 parameters"
        write(unit, '(A)') "    ictrl = np.zeros(5, dtype=np.int32)"
        write(unit, '(A)') "    verbose = True"
        write(unit, '(A)') "    reset_file = ''"
        write(unit, '(A)') "    # Run VMEC: readin + timestep + output + cleanup"
        write(unit, '(A)') "    ictrl[0] = 2 + 4 + 8 + 16"
        write(unit, '(A)') "    vmec.runvmec(ictrl, '" // get_basename(local_input) // "', verbose, fcomm, reset_file)"
        write(unit, '(A)') "    print('VMEC2000 run completed successfully')"
        write(unit, '(A)') "except Exception as e:"
        write(unit, '(A)') "    print(f'VMEC2000 failed: {e}')"
        write(unit, '(A)') "    import traceback"
        write(unit, '(A)') "    traceback.print_exc()"
        write(unit, '(A)') "    sys.exit(1)"
        close(unit)

        cmd = "cd " // trim(output_dir) // " && timeout " // int_to_str(timeout_val) // &
              " python " // get_basename(python_script) // " > vmec2000.log 2>&1"

        call execute_command_line(trim(cmd), exitstat=stat)

        if (stat == 0) then
            success = .true.
        else if (stat == 124) then
            write(error_unit, '(A)') "VMEC2000 timed out for " // get_basename(input_file)
        else
            write(error_unit, '(A)') "VMEC2000 failed for " // get_basename(input_file)
        end if
    end function vmec2000_run_case

    subroutine vmec2000_extract_results(this, output_dir, results)
        class(vmec2000_t), intent(in) :: this
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
    end subroutine vmec2000_extract_results

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

    function int_to_str(i) result(str)
        integer, intent(in) :: i
        character(len=:), allocatable :: str
        character(len=32) :: temp

        write(temp, '(I0)') i
        str = trim(temp)
    end function int_to_str

end module vmec2000_implementation