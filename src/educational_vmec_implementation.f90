module educational_vmec_implementation
    use iso_fortran_env, only: int32, real64, error_unit, output_unit
    use vmec_implementation_base, only: vmec_implementation_t
    use vmec_benchmark_types, only: vmec_result_t
    use json_module
    use wout_reader, only: wout_data_t, read_wout_file
    implicit none
    private

    public :: educational_vmec_t

    type, extends(vmec_implementation_t) :: educational_vmec_t
    contains
        procedure :: build => educational_vmec_build
        procedure :: run_case => educational_vmec_run_case
        procedure :: extract_results => educational_vmec_extract_results
        procedure :: convert_json_to_indata => educational_vmec_convert_json_to_indata
    end type educational_vmec_t

contains

    function educational_vmec_build(this) result(success)
        class(educational_vmec_t), intent(inout) :: this
        logical :: success
        character(len=:), allocatable :: build_dir, cmd
        character(len=1000) :: temp_path
        integer :: stat, i, unit
        logical :: exists
        
        success = .false.
        
        ! Check if path exists
        inquire(file=trim(this%path), exist=exists)
        if (.not. exists) then
            write(error_unit, '(A)') "Educational VMEC path does not exist: " // trim(this%path)
            return
        end if
        
        build_dir = trim(this%path) // "/build"
        
        ! Check if already built
        inquire(file=trim(build_dir) // "/bin/xvmec", exist=exists)
        if (exists) then
            ! Already built, just set the absolute executable path
            call execute_command_line("realpath " // trim(this%path) // " > /tmp/vmec_path.tmp", exitstat=stat)
            if (stat == 0) then
                open(newunit=unit, file="/tmp/vmec_path.tmp", status="old", action="read")
                read(unit, '(A)', iostat=i) temp_path
                close(unit)
                if (i == 0) then
                    this%executable = trim(adjustl(temp_path)) // "/build/bin/xvmec"
                end if
            else
                ! Fallback to current working directory + relative path
                call execute_command_line("pwd > /tmp/vmec_pwd.tmp", exitstat=stat)
                if (stat == 0) then
                    open(newunit=unit, file="/tmp/vmec_pwd.tmp", status="old", action="read")
                    read(unit, '(A)', iostat=i) temp_path
                    close(unit)
                    if (i == 0) then
                        this%executable = trim(adjustl(temp_path)) // "/" // trim(build_dir) // "/bin/xvmec"
                    end if
                end if
            end if
            this%available = .true.
            success = .true.
            write(output_unit, '(A)') "Educational VMEC already built at " // trim(this%executable)
            return
        end if
        
        ! Create build directory
        call execute_command_line("mkdir -p " // trim(build_dir), exitstat=stat)
        
        write(output_unit, '(A)') "Initializing Educational VMEC submodules"
        
        ! Initialize only the working submodules (skip vac2/vac3)
        cmd = "cd " // trim(this%path) // " && git submodule update --init json-fortran abscab-fortran"
        call execute_command_line(trim(cmd), exitstat=stat)
        
        if (stat /= 0) then
            write(error_unit, '(A)') "Failed to initialize submodules"
            return
        end if
        
        write(output_unit, '(A)') "Configuring Educational VMEC with CMake"
        
        ! Configure with CMake
        cmd = "cd " // trim(build_dir) // " && cmake .."
        call execute_command_line(trim(cmd), exitstat=stat)
        
        if (stat /= 0) then
            write(error_unit, '(A)') "Failed to configure Educational VMEC with CMake"
            return
        end if
        
        write(output_unit, '(A)') "Building Educational VMEC"
        
        ! Build
        cmd = "cd " // trim(build_dir) // " && make -j"
        call execute_command_line(trim(cmd), exitstat=stat)
        
        if (stat /= 0) then
            write(error_unit, '(A)') "Failed to build Educational VMEC"
            return
        end if
        
        ! Check if executable exists and store absolute path
        this%executable = trim(build_dir) // "/bin/xvmec"
        inquire(file=trim(this%executable), exist=exists)
        
        if (exists) then
            ! Set absolute path using the same method as for pre-built
            call execute_command_line("realpath " // trim(this%path) // " > /tmp/vmec_path.tmp", exitstat=stat)
            if (stat == 0) then
                open(newunit=unit, file="/tmp/vmec_path.tmp", status="old", action="read")
                read(unit, '(A)', iostat=i) temp_path
                close(unit)
                if (i == 0) then
                    this%executable = trim(adjustl(temp_path)) // "/build/bin/xvmec"
                end if
            else
                ! Fallback: create absolute path manually
                call execute_command_line("pwd > /tmp/vmec_pwd.tmp", exitstat=stat)
                if (stat == 0) then
                    open(newunit=unit, file="/tmp/vmec_pwd.tmp", status="old", action="read")
                    read(unit, '(A)', iostat=i) temp_path
                    close(unit)
                    if (i == 0) then
                        this%executable = trim(adjustl(temp_path)) // "/" // trim(build_dir) // "/bin/xvmec"
                    end if
                end if
            end if
            
            this%available = .true.
            success = .true.
            write(output_unit, '(A)') "Successfully built Educational VMEC at " // trim(this%executable)
        else
            write(error_unit, '(A)') "Build completed but executable not found"
        end if
    end function educational_vmec_build

    function educational_vmec_run_case(this, input_file, output_dir, timeout) result(success)
        class(educational_vmec_t), intent(inout) :: this
        character(len=*), intent(in) :: input_file
        character(len=*), intent(in) :: output_dir
        integer, intent(in), optional :: timeout
        logical :: success
        character(len=:), allocatable :: indata_file, local_input, cmd
        integer :: stat, unit, timeout_val
        logical :: is_json
        
        success = .false.
        
        if (.not. this%validate_input(input_file)) return
        if (.not. this%prepare_output_dir(output_dir)) return
        if (.not. this%available) then
            write(error_unit, '(A)') "Educational VMEC is not available"
            return
        end if
        
        timeout_val = 300
        if (present(timeout)) timeout_val = timeout
        
        ! Check if input is JSON
        is_json = index(input_file, ".json") > 0
        
        if (is_json) then
            indata_file = trim(output_dir) // "/input." // get_basename(input_file)
            if (.not. this%convert_json_to_indata(input_file, indata_file)) return
        else
            indata_file = input_file
        end if
        
        ! Copy input file to output directory
        local_input = trim(output_dir) // "/" // get_basename(indata_file)
        if (local_input /= indata_file) then
            cmd = "cp " // trim(indata_file) // " " // trim(local_input)
            call execute_command_line(trim(cmd), exitstat=stat)
        end if
        
        ! Run Educational VMEC
        cmd = "cd " // trim(output_dir) // " && timeout " // int_to_str(timeout_val) // &
              " " // trim(this%executable) // " " // get_basename(local_input) // &
              " > educational_vmec.log 2>&1"
        
        ! Debug: print the command being executed
        write(output_unit, '(A)') "DEBUG: Running command: " // trim(cmd)
        
        call execute_command_line(trim(cmd), exitstat=stat)
        
        if (stat == 0) then
            success = .true.
        else if (stat == 124) then
            write(error_unit, '(A)') "Educational VMEC timed out for " // get_basename(input_file)
        else
            write(error_unit, '(A)') "Educational VMEC failed for " // get_basename(input_file)
        end if
    end function educational_vmec_run_case

    subroutine educational_vmec_extract_results(this, output_dir, results)
        class(educational_vmec_t), intent(in) :: this
        character(len=*), intent(in) :: output_dir
        type(vmec_result_t), intent(out) :: results
        character(len=256) :: wout_file
        type(wout_data_t) :: wout_data
        integer :: stat
        logical :: exists, read_success
        
        call results%clear()
        
        ! Look for wout file - use the most recently modified one
        call execute_command_line("ls -t " // trim(output_dir) // "/wout_*.nc 2>/dev/null | head -1", &
                                exitstat=stat, cmdmsg=wout_file)
        if (stat /= 0) then
            wout_file = ""
        end if
        
        if (stat == 0 .and. len_trim(wout_file) > 0) then
            wout_file = trim(adjustl(wout_file))
            inquire(file=wout_file, exist=exists)
            
            if (exists) then
                ! Read the NetCDF file
                read_success = read_wout_file(wout_file, wout_data)
                
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
                else
                    results%error_message = "Failed to read wout file: " // trim(wout_file)
                end if
            else
                results%error_message = "Wout file not found: " // trim(wout_file)
            end if
        else
            results%error_message = "No wout file found"
        end if
    end subroutine educational_vmec_extract_results

    function educational_vmec_convert_json_to_indata(this, json_filename, output_file) result(success)
        class(educational_vmec_t), intent(in) :: this
        character(len=*), intent(in) :: json_filename
        character(len=*), intent(in) :: output_file
        logical :: success
        type(json_file) :: json
        type(json_core) :: core
        type(json_value), pointer :: p_root, p_val, p_array, p_elem
        logical :: found, lasym, lfreeb
        integer :: nfp, mpol, ntor, i, n, m, unit
        real(real64) :: delt, tcon0, phiedge, pres_scale, curtor, gamma
        real(real64), allocatable :: ns_array(:), ftol_array(:), am(:), ac(:)
        real(real64), allocatable :: raxis_c(:), zaxis_s(:)
        character(len=:), allocatable :: pmass_type, pcurr_type
        
        success = .false.
        
        ! Initialize JSON
        call json%initialize()
        call json%load(filename=json_filename)
        
        if (json%failed()) then
            write(error_unit, '(A)') "Failed to load JSON file: " // trim(json_filename)
            call json%destroy()
            return
        end if
        
        ! Open output file
        open(newunit=unit, file=output_file, status='replace', action='write', iostat=i)
        if (i /= 0) then
            write(error_unit, '(A)') "Failed to open output file: " // trim(output_file)
            call json%destroy()
            return
        end if
        
        write(unit, '(A)') "&INDATA"
        
        ! Basic parameters
        call json%get('lasym', lasym, found)
        if (found) then
            write(unit, '(A,L1)') "  LASYM = ", lasym
        else
            write(unit, '(A)') "  LASYM = F"
        end if
        
        call json%get('nfp', nfp, found)
        if (found) write(unit, '(A,I0)') "  NFP = ", nfp
        
        call json%get('mpol', mpol, found)
        if (found) write(unit, '(A,I0)') "  MPOL = ", mpol
        
        call json%get('ntor', ntor, found)
        if (found) write(unit, '(A,I0)') "  NTOR = ", ntor
        
        ! Arrays - simplified handling
        ! In a real implementation, we would properly read JSON arrays
        
        write(unit, '(A)') "/"
        write(unit, '(A)') "&END"
        
        close(unit)
        
        call json%destroy()
        success = .true.
        
    end function educational_vmec_convert_json_to_indata

    ! Utility functions
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
        
        ! Remove .json extension if present
        last_slash = index(basename, '.json')
        if (last_slash > 0) then
            basename = basename(1:last_slash-1)
        end if
    end function get_basename

    function int_to_str(i) result(str)
        integer, intent(in) :: i
        character(len=:), allocatable :: str
        character(len=32) :: temp
        
        write(temp, '(I0)') i
        str = trim(temp)
    end function int_to_str

end module educational_vmec_implementation