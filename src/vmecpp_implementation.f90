module vmecpp_implementation
    use iso_fortran_env, only: int32, real64, error_unit, output_unit
    use vmec_implementation_base, only: vmec_implementation_t
    use vmec_benchmark_types, only: vmec_result_t
    use hdf5_reader, only: hdf5_data_t, read_hdf5_file
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
        integer :: stat, timeout_val
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

        ! Look for corresponding JSON file first
        if (index(input_file, ".json") > 0) then
            ! Already a JSON file
            local_input = trim(output_dir) // "/" // get_basename(input_file)
            cmd = "cp " // trim(input_file) // " " // trim(local_input)
            call execute_command_line(trim(cmd), exitstat=stat)
        else
            ! Try to find corresponding JSON file
            local_input = get_json_filename(input_file)
            inquire(file=local_input, exist=exists)
            if (exists) then
                ! Copy the JSON file instead
                local_input = trim(output_dir) // "/" // get_basename(local_input)
                cmd = "cp " // get_json_filename(input_file) // " " // trim(local_input)
                call execute_command_line(trim(cmd), exitstat=stat)
            else
                write(error_unit, '(A)') "No JSON file found for VMEC++ input: " // trim(input_file)
                return
            end if
        end if

        ! Run VMEC++ standalone executable
        cmd = "cd " // trim(output_dir) // " && timeout " // int_to_str(timeout_val) // &
              " " // trim(this%executable) // " " // get_basename(local_input) // &
              " > vmecpp.log 2>&1"

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
        character(len=256) :: hdf5_file
        type(hdf5_data_t) :: hdf5_data
        integer :: stat, unit
        logical :: exists, read_success

        call results%clear()

        ! Look for HDF5 file - use the most recently modified one
        call execute_command_line("ls -t " // trim(output_dir) // "/*.out.h5 2>/dev/null | head -1 > /tmp/hdf5_file_vmecpp.tmp", &
                                exitstat=stat)
        if (stat == 0) then
            open(newunit=unit, file="/tmp/hdf5_file_vmecpp.tmp", status="old", action="read")
            read(unit, '(A)') hdf5_file
            close(unit)
        else
            hdf5_file = ""
        end if

        if (stat == 0 .and. len_trim(hdf5_file) > 0) then
            hdf5_file = trim(adjustl(hdf5_file))
            inquire(file=hdf5_file, exist=exists)
            
            if (exists) then
                ! Read the HDF5 file
                read_success = read_hdf5_file(hdf5_file, hdf5_data)
                
                if (read_success .and. hdf5_data%valid) then
                    results%success = .true.
                    
                    ! Copy physics quantities to results
                    results%wb = hdf5_data%wb
                    results%betatotal = hdf5_data%betatotal
                    results%betapol = hdf5_data%betapol
                    results%betator = hdf5_data%betator
                    results%aspect = hdf5_data%aspect
                    results%raxis_cc = hdf5_data%raxis_cc
                    results%volume_p = hdf5_data%volume_p
                    results%iotaf_edge = hdf5_data%iotaf_edge
                    results%itor = hdf5_data%itor
                    results%b0 = hdf5_data%b0
                    results%rmajor_p = hdf5_data%rmajor_p
                    results%aminor_p = hdf5_data%aminor_p
                    
                    ! Copy Fourier coefficients if available
                    if (allocated(hdf5_data%rmnc)) then
                        allocate(results%rmnc(size(hdf5_data%rmnc,1), size(hdf5_data%rmnc,2)))
                        results%rmnc = hdf5_data%rmnc
                    end if
                    if (allocated(hdf5_data%rmns)) then
                        allocate(results%rmns(size(hdf5_data%rmns,1), size(hdf5_data%rmns,2)))
                        results%rmns = hdf5_data%rmns
                    end if
                    if (allocated(hdf5_data%zmnc)) then
                        allocate(results%zmnc(size(hdf5_data%zmnc,1), size(hdf5_data%zmnc,2)))
                        results%zmnc = hdf5_data%zmnc
                    end if
                    if (allocated(hdf5_data%zmns)) then
                        allocate(results%zmns(size(hdf5_data%zmns,1), size(hdf5_data%zmns,2)))
                        results%zmns = hdf5_data%zmns
                    end if
                    if (allocated(hdf5_data%lmnc)) then
                        allocate(results%lmnc(size(hdf5_data%lmnc,1), size(hdf5_data%lmnc,2)))
                        results%lmnc = hdf5_data%lmnc
                    end if
                    if (allocated(hdf5_data%lmns)) then
                        allocate(results%lmns(size(hdf5_data%lmns,1), size(hdf5_data%lmns,2)))
                        results%lmns = hdf5_data%lmns
                    end if
                    if (allocated(hdf5_data%xm)) then
                        allocate(results%xm(size(hdf5_data%xm)))
                        results%xm = hdf5_data%xm
                    end if
                    if (allocated(hdf5_data%xn)) then
                        allocate(results%xn(size(hdf5_data%xn)))
                        results%xn = hdf5_data%xn
                    end if
                    
                else
                    results%error_message = "Failed to read HDF5 file: " // trim(hdf5_file)
                end if
            else
                results%error_message = "HDF5 file not found: " // trim(hdf5_file)
            end if
        else
            results%error_message = "No HDF5 file found"
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