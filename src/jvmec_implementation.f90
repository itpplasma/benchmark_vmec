module jvmec_implementation
    use iso_fortran_env, only: int32, real64, error_unit, output_unit
    use vmec_implementation_base, only: vmec_implementation_t
    use vmec_benchmark_types, only: vmec_result_t
    use json_module
    implicit none
    private

    public :: jvmec_t

    type, extends(vmec_implementation_t) :: jvmec_t
    contains
        procedure :: build => jvmec_build
        procedure :: run_case => jvmec_run_case
        procedure :: extract_results => jvmec_extract_results
        procedure :: convert_json_to_indata => jvmec_convert_json_to_indata
    end type jvmec_t

contains

    function jvmec_build(this) result(success)
        class(jvmec_t), intent(inout) :: this
        logical :: success
        character(len=:), allocatable :: cmd, jar_file
        integer :: stat
        logical :: exists
        
        success = .false.
        
        ! Check if path exists
        inquire(file=trim(this%path), exist=exists)
        if (.not. exists) then
            write(error_unit, '(A)') "jVMEC path does not exist: " // trim(this%path)
            return
        end if
        
        ! Check if already built
        jar_file = trim(this%path) // "/target/classes"
        inquire(file=trim(jar_file), exist=exists)
        if (exists) then
            ! Already built, just set the executable
            this%executable = "java -cp " // trim(this%path) // "/target/classes:" // &
                             trim(this%path) // "/target/lib/* de.labathome.test.RunAllVmecTests"
            this%available = .true.
            success = .true.
            write(output_unit, '(A)') "jVMEC already built at " // trim(jar_file)
            return
        end if
        
        write(output_unit, '(A)') "Building jVMEC with Maven"
        
        ! Build jVMEC - the POM has parent dependency issues that prevent standard build
        ! Using dependency resolution + manual compilation as workaround
        ! This follows the same pattern as documented but bypasses the parent POM issue
        cmd = "cd " // trim(this%path) // " && " // &
              "mvn dependency:copy-dependencies -DoutputDirectory=target/lib -q && " // &
              "mvn compiler:compile -Dmaven.compiler.source=11 -Dmaven.compiler.target=11"
        call execute_command_line(trim(cmd), exitstat=stat)
        
        if (stat /= 0) then
            write(error_unit, '(A)') "Failed to build jVMEC with Maven"
            return
        end if
        
        ! Check for compiled classes (since we're using compiler:compile)
        jar_file = trim(this%path) // "/target/classes"
        inquire(file=trim(jar_file), exist=exists)
        
        if (exists) then
            ! Use test runner instead of direct Vmec class
            this%executable = "java -cp " // trim(this%path) // "/target/classes:" // &
                             trim(this%path) // "/target/lib/* de.labathome.test.RunAllVmecTests"
            this%available = .true.
            success = .true.
            write(output_unit, '(A)') "Successfully built jVMEC classes at " // trim(jar_file)
        else
            write(error_unit, '(A)') "Build completed but compiled classes not found"
        end if
    end function jvmec_build

    function jvmec_run_case(this, input_file, output_dir, timeout) result(success)
        class(jvmec_t), intent(inout) :: this
        character(len=*), intent(in) :: input_file
        character(len=*), intent(in) :: output_dir
        integer, intent(in), optional :: timeout
        logical :: success
        character(len=:), allocatable :: indata_file, local_input, cmd
        integer :: stat, timeout_val
        logical :: is_json
        
        success = .false.
        
        if (.not. this%validate_input(input_file)) return
        if (.not. this%prepare_output_dir(output_dir)) return
        if (.not. this%available) then
            write(error_unit, '(A)') "jVMEC is not available"
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
        
        ! Run jVMEC
        cmd = "cd " // trim(output_dir) // " && timeout " // int_to_str(timeout_val) // &
              " " // trim(this%executable) // " " // get_basename(local_input) // &
              " > jvmec.log 2>&1"
        
        call execute_command_line(trim(cmd), exitstat=stat)
        
        if (stat == 0) then
            success = .true.
        else if (stat == 124) then
            write(error_unit, '(A)') "jVMEC timed out for " // get_basename(input_file)
        else
            write(error_unit, '(A)') "jVMEC failed for " // get_basename(input_file)
        end if
    end function jvmec_run_case

    subroutine jvmec_extract_results(this, output_dir, results)
        class(jvmec_t), intent(in) :: this
        character(len=*), intent(in) :: output_dir
        type(vmec_result_t), intent(out) :: results
        character(len=256) :: wout_file
        integer :: stat
        logical :: exists
        
        call results%clear()
        
        ! Look for wout file
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
    end subroutine jvmec_extract_results

    function jvmec_convert_json_to_indata(this, json_filename, output_file) result(success)
        class(jvmec_t), intent(in) :: this
        character(len=*), intent(in) :: json_filename
        character(len=*), intent(in) :: output_file
        logical :: success
        type(json_file) :: json
        logical :: found, lasym
        integer :: nfp, mpol, ntor, unit, stat
        
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
        open(newunit=unit, file=output_file, status='replace', action='write', iostat=stat)
        if (stat /= 0) then
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
        
        write(unit, '(A)') "/"
        write(unit, '(A)') "&END"
        
        close(unit)
        call json%destroy()
        success = .true.
        
    end function jvmec_convert_json_to_indata

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

end module jvmec_implementation