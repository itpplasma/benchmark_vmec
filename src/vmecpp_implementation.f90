module vmecpp_implementation
    use iso_fortran_env, only: int32, real64, error_unit, output_unit
    use vmec_implementation_base, only: vmec_implementation_t
    use vmec_benchmark_types, only: vmec_result_t
    use wout_reader, only: wout_data_t, read_wout_file
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
        character(len=:), allocatable :: cmd, build_dir
        character(len=1000) :: temp_path
        integer :: stat, i, unit
        logical :: exists

        success = .false.

        inquire(file=trim(this%path), exist=exists)
        if (.not. exists) then
            write(error_unit, '(A)') "VMEC++ path does not exist: " // trim(this%path)
            return
        end if
        
        build_dir = trim(this%path) // "/build"
        
        ! Store absolute path
        call execute_command_line("realpath " // trim(build_dir) // " > /tmp/vmecpp_build_path.tmp", exitstat=stat)
        if (stat == 0) then
            open(newunit=unit, file="/tmp/vmecpp_build_path.tmp", status="old", action="read")
            read(unit, '(A)', iostat=i) temp_path
            close(unit)
            if (i == 0) then
                this%executable = trim(adjustl(temp_path)) // "/vmec_standalone"
            else
                this%executable = trim(build_dir) // "/vmec_standalone"
            end if
        else
            this%executable = trim(build_dir) // "/vmec_standalone"
        end if
        
        ! Check if already built
        inquire(file=trim(this%executable), exist=exists)
        if (exists) then
            this%available = .true.
            success = .true.
            write(output_unit, '(A)') "VMEC++ already built at " // trim(this%executable)
            return
        end if

        write(output_unit, '(A)') "Building VMEC++ standalone executable with CMake"

        ! Create build directory
        call execute_command_line("mkdir -p " // trim(build_dir), exitstat=stat)
        
        ! Configure with CMake
        cmd = "cd " // trim(build_dir) // " && cmake .."
        call execute_command_line(trim(cmd), exitstat=stat)
        
        if (stat /= 0) then
            write(error_unit, '(A)') "Failed to configure VMEC++ with CMake"
            return
        end if
        
        ! Build the standalone executable
        cmd = "cd " // trim(build_dir) // " && make -j vmec_standalone"
        call execute_command_line(trim(cmd), exitstat=stat)

        if (stat /= 0) then
            write(error_unit, '(A)') "Failed to build VMEC++ standalone executable"
            return
        end if
        
        ! Check if executable exists and get absolute path
        inquire(file=trim(this%executable), exist=exists)
        if (exists) then
            ! Get absolute path again to make sure it's correct
            call execute_command_line("realpath " // trim(this%executable) // " > /tmp/vmecpp_exec_path.tmp", exitstat=stat)
            if (stat == 0) then
                open(newunit=unit, file="/tmp/vmecpp_exec_path.tmp", status="old", action="read")
                read(unit, '(A)', iostat=i) temp_path
                close(unit)
                if (i == 0) then
                    this%executable = trim(adjustl(temp_path))
                end if
            end if
            this%available = .true.
            success = .true.
            write(output_unit, '(A)') "Successfully built VMEC++ standalone at " // trim(this%executable)
        else
            write(error_unit, '(A)') "Build completed but executable not found"
        end if
    end function vmecpp_build

    function vmecpp_run_case(this, input_file, output_dir, timeout) result(success)
        class(vmecpp_t), intent(inout) :: this
        character(len=*), intent(in) :: input_file
        character(len=*), intent(in) :: output_dir
        integer, intent(in), optional :: timeout
        logical :: success
        character(len=:), allocatable :: local_input, cmd
        integer :: stat, timeout_val, unit
        logical :: exists

        success = .false.

        if (.not. this%validate_input(input_file)) return
        if (.not. this%prepare_output_dir(output_dir)) return
        if (.not. this%available) then
            write(error_unit, '(A)') "VMEC++ is not available"
            return
        end if

        timeout_val = 300
        if (present(timeout)) timeout_val = timeout

        ! Copy input file (JSON or INDATA) to output directory
        local_input = trim(output_dir) // "/" // get_basename(input_file)
        cmd = "cp " // trim(input_file) // " " // trim(local_input)
        call execute_command_line(trim(cmd), exitstat=stat)
        if (stat /= 0) then
            write(error_unit, '(A)') "Failed to copy input file to output directory"
            return
        end if

        ! Create a Python script to run VMEC++
        open(newunit=unit, file=trim(output_dir) // "/run_vmecpp.py", status="replace", action="write")
        write(unit, '(A)') "#!/usr/bin/env python3"
        write(unit, '(A)') "import vmecpp"
        write(unit, '(A)') "import sys"
        write(unit, '(A)') "try:"
        write(unit, '(A)') "    # VMEC++ can load INDATA files directly"
        write(unit, '(A)') "    vmec_input = vmecpp.VmecInput.from_file('" // get_basename(local_input) // "')"
        write(unit, '(A)') "    # Allow non-converged results for benchmarking"
        write(unit, '(A)') "    vmec_input.return_outputs_even_if_not_converged = True"
        write(unit, '(A)') "    output = vmecpp.run(vmec_input)"
        write(unit, '(A)') "    output.wout.save('wout_" // get_basename_without_ext(local_input) // ".nc')"
        write(unit, '(A)') "    print('VMEC++ completed')"
        write(unit, '(A)') "except Exception as e:"
        write(unit, '(A)') "    print(f'VMEC++ Error: {e}')"
        write(unit, '(A)') "    import traceback"
        write(unit, '(A)') "    traceback.print_exc()"
        write(unit, '(A)') "    sys.exit(1)"
        close(unit)
        
        ! Run the Python script
        cmd = "cd " // trim(output_dir) // " && timeout " // int_to_str(timeout_val) // &
              " python3 run_vmecpp.py > vmecpp.log 2>&1"

        write(output_unit, '(A)') "DEBUG: Running command: " // trim(cmd)
        
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
        character(len=256) :: netcdf_file
        type(wout_data_t) :: wout_data
        integer :: stat, unit
        logical :: exists, read_success

        call results%clear()

        ! Look for NetCDF file - use the most recently modified one
        call execute_command_line("ls -t " // trim(output_dir) // "/wout_*.nc 2>/dev/null | head -1 > /tmp/netcdf_file_vmecpp.tmp", &
                                exitstat=stat)
        if (stat == 0) then
            open(newunit=unit, file="/tmp/netcdf_file_vmecpp.tmp", status="old", action="read")
            read(unit, '(A)', iostat=stat) netcdf_file
            close(unit)
            if (stat /= 0) netcdf_file = ""
        else
            netcdf_file = ""
        end if

        if (stat == 0 .and. len_trim(netcdf_file) > 0) then
            netcdf_file = trim(adjustl(netcdf_file))
            inquire(file=netcdf_file, exist=exists)
            
            if (exists) then
                write(output_unit, '(A)') "DEBUG: File exists, calling read_wout_file"
                ! Read the NetCDF file
                read_success = read_wout_file(netcdf_file, wout_data)
                
                if (read_success .and. wout_data%valid) then
                    results%success = .true.
                    
                    ! Copy physics quantities to results
                    results%wb = wout_data%wb
                    results%betatotal = wout_data%betatotal
                    results%betapol = wout_data%betapol
                    results%betator = wout_data%betator
                    results%aspect = wout_data%aspect
                    results%raxis_cc = wout_data%raxis_cc
                    results%volume_p = wout_data%volume_p
                    results%iotaf_edge = wout_data%iotaf_edge
                    results%itor = wout_data%itor
                    results%b0 = wout_data%b0
                    results%rmajor_p = wout_data%rmajor_p
                    results%aminor_p = wout_data%aminor_p
                    
                    ! Copy Fourier coefficients if available
                    if (allocated(wout_data%rmnc)) then
                        allocate(results%rmnc(size(wout_data%rmnc,1), size(wout_data%rmnc,2)))
                        results%rmnc = wout_data%rmnc
                    end if
                    if (allocated(wout_data%rmns)) then
                        allocate(results%rmns(size(wout_data%rmns,1), size(wout_data%rmns,2)))
                        results%rmns = wout_data%rmns
                    end if
                    if (allocated(wout_data%zmnc)) then
                        allocate(results%zmnc(size(wout_data%zmnc,1), size(wout_data%zmnc,2)))
                        results%zmnc = wout_data%zmnc
                    end if
                    if (allocated(wout_data%zmns)) then
                        allocate(results%zmns(size(wout_data%zmns,1), size(wout_data%zmns,2)))
                        results%zmns = wout_data%zmns
                    end if
                    if (allocated(wout_data%lmnc)) then
                        allocate(results%lmnc(size(wout_data%lmnc,1), size(wout_data%lmnc,2)))
                        results%lmnc = wout_data%lmnc
                    end if
                    if (allocated(wout_data%lmns)) then
                        allocate(results%lmns(size(wout_data%lmns,1), size(wout_data%lmns,2)))
                        results%lmns = wout_data%lmns
                    end if
                    if (allocated(wout_data%xm)) then
                        allocate(results%xm(size(wout_data%xm)))
                        results%xm = wout_data%xm
                    end if
                    if (allocated(wout_data%xn)) then
                        allocate(results%xn(size(wout_data%xn)))
                        results%xn = wout_data%xn
                    end if
                    
                else
                    results%error_message = "Failed to read NetCDF file: " // trim(netcdf_file)
                end if
            else
                results%error_message = "NetCDF file not found: " // trim(netcdf_file)
            end if
        else
            results%error_message = "No NetCDF file found"
        end if
        
        ! Clean up wout data
        call wout_data%clear()
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

    function get_basename_without_ext(filename) result(basename)
        character(len=*), intent(in) :: filename
        character(len=:), allocatable :: basename
        character(len=:), allocatable :: temp
        integer :: last_slash, last_dot

        last_slash = index(filename, '/', back=.true.)
        if (last_slash > 0) then
            temp = filename(last_slash+1:)
        else
            temp = filename
        end if
        
        last_dot = index(temp, '.', back=.true.)
        if (last_dot > 0) then
            basename = temp(1:last_dot-1)
        else
            basename = temp
        end if
    end function get_basename_without_ext

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

    function get_json_filename(input_file) result(json_file)
        character(len=*), intent(in) :: input_file
        character(len=:), allocatable :: json_file
        integer :: last_slash, last_dot
        character(len=:), allocatable :: base_name, dir_name
        
        ! Get directory part
        last_slash = index(input_file, '/', back=.true.)
        if (last_slash > 0) then
            dir_name = input_file(1:last_slash-1)
            base_name = input_file(last_slash+1:)
        else
            dir_name = "."
            base_name = input_file
        end if
        
        ! Remove input. prefix if present
        if (index(base_name, "input.") == 1) then
            base_name = base_name(7:)
        end if
        
        ! Construct JSON filename
        json_file = trim(dir_name) // "/" // trim(base_name) // ".json"
    end function get_json_filename

end module vmecpp_implementation