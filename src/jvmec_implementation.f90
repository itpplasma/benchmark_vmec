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
        procedure :: clean_input_for_jvmec => jvmec_clean_input_for_jvmec
    end type jvmec_t

contains

    function jvmec_build(this) result(success)
        class(jvmec_t), intent(inout) :: this
        logical :: success
        character(len=:), allocatable :: cmd, jar_file
        character(len=256) :: local_input
        integer :: stat
        logical :: exists
        
        success = .false.
        
        ! Check if path exists
        inquire(file=trim(this%path), exist=exists)
        if (.not. exists) then
            write(error_unit, '(A)') "jVMEC path does not exist: " // trim(this%path)
            return
        end if
        
        ! Check if already built (JAR file)
        jar_file = trim(this%path) // "/target/jVMEC-1.0.0.jar"
        inquire(file=trim(jar_file), exist=exists)
        if (exists) then
            ! Already built, set executable with absolute path including dependencies
            this%executable = "java -cp /home/ert/code/benchmark_vmec/vmec_repos/jvmec/target/jVMEC-1.0.0.jar:" // &
                             "/home/ert/code/benchmark_vmec/vmec_repos/jvmec/target/dependency/* de.labathome.jvmec.VmecRunner"
            this%available = .true.
            success = .true.
            write(output_unit, '(A)') "jVMEC already built at " // trim(jar_file)
            return
        end if
        
        ! Check if classes directory exists (alternative build method)
        jar_file = trim(this%path) // "/target/classes"
        inquire(file=trim(jar_file), exist=exists)
        if (exists) then
            ! Already built, just set the executable using classes dir with dependencies
            this%executable = "java -cp /home/ert/code/benchmark_vmec/vmec_repos/jvmec/target/classes:" // &
                             "/home/ert/code/benchmark_vmec/vmec_repos/jvmec/target/lib/* de.labathome.jvmec.VmecRunner"
            this%available = .true.
            success = .true.
            write(output_unit, '(A)') "jVMEC already built at " // trim(jar_file)
            return
        end if
        
        write(output_unit, '(A)') "Building jVMEC with build script"
        
        ! Use the build script which handles all the Maven complexities
        cmd = "cd " // trim(this%path) // " && ./build.sh"
        call execute_command_line(trim(cmd), exitstat=stat)
        
        if (stat /= 0) then
            write(error_unit, '(A)') "Failed to build jVMEC with build script"
            return
        end if
        
        ! Check for built JAR file
        jar_file = trim(this%path) // "/target/jVMEC-1.0.0.jar"
        inquire(file=trim(jar_file), exist=exists)
        
        if (exists) then
            ! Use the built JAR with VmecRunner main class (full VMEC implementation)
            ! Dependencies are already copied by the build script
            this%executable = "java -cp /home/ert/code/benchmark_vmec/vmec_repos/jvmec/target/jVMEC-1.0.0.jar:" // &
                             "/home/ert/code/benchmark_vmec/vmec_repos/jvmec/target/dependency/* de.labathome.jvmec.VmecRunner"
            this%available = .true.
            success = .true.
            write(output_unit, '(A)') "Successfully built jVMEC JAR at " // trim(jar_file)
        else
            write(error_unit, '(A)') "Build completed but JAR file not found"
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
        
        ! Check if input is JSON format (VMEC++ style)
        is_json = index(input_file, ".json") > 0
        
        if (is_json) then
            ! Convert JSON to VMEC namelist format
            indata_file = trim(output_dir) // "/input." // get_basename(input_file)
            if (.not. this%convert_json_to_indata(input_file, indata_file)) return
        else
            ! Copy input file to output directory and clean it for jVMEC
            indata_file = input_file
        end if
        
        ! Create a cleaned version of the input file for jVMEC
        local_input = trim(output_dir) // "/input_cleaned.txt"
        if (.not. this%clean_input_for_jvmec(indata_file, local_input)) then
            write(error_unit, '(A)') "Failed to clean input file for jVMEC"
            return
        end if
        
        ! Run jVMEC with VmecRunner using the cleaned input file
        cmd = "cd " // trim(output_dir) // " && timeout " // int_to_str(timeout_val) // " " // &
              trim(this%executable) // " " // get_basename(local_input) // " ./ > jvmec.log 2>&1"
        
        ! Debug: print the command being run
        write(output_unit, '(A)') "DEBUG: Running command: " // trim(cmd)
        call execute_command_line(trim(cmd), exitstat=stat)
        
        if (stat == 0) then
            success = .true.
            write(output_unit, '(A)') "jVMEC completed successfully"
        else if (stat == 124) then
            write(error_unit, '(A)') "jVMEC timed out for " // get_basename(input_file)
        else
            write(error_unit, '(A)') "jVMEC failed with exit status: " // int_to_str(stat)
        end if
    end function jvmec_run_case

    subroutine jvmec_extract_results(this, output_dir, results)
        use netcdf
        class(jvmec_t), intent(in) :: this
        character(len=*), intent(in) :: output_dir
        type(vmec_result_t), intent(out) :: results
        character(len=256) :: wout_file, log_file
        integer :: stat, ncid, varid, dimid
        integer :: ns, mnmax, mnmax_nyq
        integer, dimension(2) :: dims
        logical :: exists
        
        call results%clear()
        
        ! Look for VMEC output files (wout.nc or wout_*.nc)
        ! Try common patterns for jVMEC output
        wout_file = trim(output_dir) // "/wout_input_cleaned.nc"
        inquire(file=trim(wout_file), exist=exists)
        if (.not. exists) then
            wout_file = trim(output_dir) // "/wout_input_cleaned.txt.nc"
            inquire(file=trim(wout_file), exist=exists)
        end if
        
        if (exists) then
            ! Open NetCDF file
            stat = nf90_open(trim(wout_file), NF90_NOWRITE, ncid)
            if (stat /= NF90_NOERR) then
                results%error_message = "Failed to open jVMEC NetCDF file"
                return
            end if
            
            ! Read dimensions
            stat = nf90_inq_dimid(ncid, "rmnc_dim0", dimid)
            if (stat == NF90_NOERR) stat = nf90_inquire_dimension(ncid, dimid, len=ns)
            
            stat = nf90_inq_dimid(ncid, "rmnc_dim1", dimid)
            if (stat == NF90_NOERR) stat = nf90_inquire_dimension(ncid, dimid, len=mnmax)
            
            ! Read basic quantities that jVMEC provides
            stat = nf90_get_att(ncid, NF90_GLOBAL, "ns", ns)
            stat = nf90_get_att(ncid, NF90_GLOBAL, "mnmax", mnmax)
            
            ! Allocate arrays
            if (mnmax > 0 .and. ns > 0) then
                allocate(results%rmnc(ns, mnmax))
                allocate(results%zmns(ns, mnmax))
                allocate(results%lmns(ns, mnmax))
                allocate(results%xm(mnmax))
                allocate(results%xn(mnmax))
                
                ! Read Fourier coefficients
                stat = nf90_inq_varid(ncid, "rmnc", varid)
                if (stat == NF90_NOERR) stat = nf90_get_var(ncid, varid, results%rmnc)
                
                stat = nf90_inq_varid(ncid, "zmns", varid)
                if (stat == NF90_NOERR) stat = nf90_get_var(ncid, varid, results%zmns)
                
                stat = nf90_inq_varid(ncid, "lmns", varid)
                if (stat == NF90_NOERR) stat = nf90_get_var(ncid, varid, results%lmns)
                
                ! Read mode numbers
                stat = nf90_inq_varid(ncid, "xm", varid)
                if (stat == NF90_NOERR) stat = nf90_get_var(ncid, varid, results%xm)
                
                stat = nf90_inq_varid(ncid, "xn", varid)
                if (stat == NF90_NOERR) stat = nf90_get_var(ncid, varid, results%xn)
                
                ! Extract R axis from Fourier coefficients (m=0, n=0 mode)
                if (allocated(results%rmnc)) then
                    results%raxis_cc = results%rmnc(ns, 1)  ! Assuming first mode is (0,0)
                end if
            end if
            
            ! Close NetCDF file
            stat = nf90_close(ncid)
            
            results%success = .true.
            results%error_message = "jVMEC data extracted successfully"
        else
            ! No wout file found, check log for convergence
            log_file = trim(output_dir) // "/jvmec.log"
            inquire(file=trim(log_file), exist=exists)
            if (exists) then
                ! Check if VMEC converged by looking for convergence indicators
                call execute_command_line("grep -q -i 'converged' " // trim(log_file), &
                                        exitstat=stat)
                if (stat == 0) then
                    results%success = .true.
                    results%error_message = "jVMEC completed but no NetCDF output found"
                else
                    results%error_message = "jVMEC failed - check log file"
                end if
            else
                results%error_message = "No jVMEC output or log files found"
            end if
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

    ! Automatically fix jVMEC POM SCM issue to enable building
    ! 
    ! Problem: The buildnumber-maven-plugin fails with "The scm url does not contain a valid delimiter"
    ! Root cause: SCM URLs in POM use undefined Maven variables ${minervacentral.git.root} and ${minervacentral.git.url}
    ! Solution: Comment out the SCM section in POM to prevent buildnumber plugin from parsing invalid URLs
    ! This allows the build to proceed with -Dmaven.buildNumber.doCheck=false flags
    subroutine fix_jvmec_pom_scm_issue(jvmec_path)
        character(len=*), intent(in) :: jvmec_path
        character(len=:), allocatable :: pom_file, cmd
        integer :: stat
        logical :: exists
        
        pom_file = trim(jvmec_path) // "/pom.xml"
        inquire(file=trim(pom_file), exist=exists)
        
        if (.not. exists) then
            write(error_unit, '(A)') "POM file not found: " // trim(pom_file)
            return
        end if
        
        write(output_unit, '(A)') "Applying automatic fix for jVMEC buildnumber plugin issue"
        
        ! Comment out problematic SCM section in POM
        ! This fixes the undefined SCM variables that cause buildnumber plugin to fail
        cmd = "cd " // trim(jvmec_path) // " && " // &
              "sed -i 's|<scm>|<!-- <scm>|g' pom.xml && " // &
              "sed -i 's|</scm>|</scm> -->|g' pom.xml"
        call execute_command_line(trim(cmd), exitstat=stat)
        
        if (stat == 0) then
            write(output_unit, '(A)') "Successfully patched POM to disable SCM section"
        else
            write(error_unit, '(A)') "Failed to patch POM file"
        end if
    end subroutine fix_jvmec_pom_scm_issue

    ! Clean input file for jVMEC by removing problematic comments and formatting
    function jvmec_clean_input_for_jvmec(this, input_file, output_file) result(success)
        class(jvmec_t), intent(in) :: this
        character(len=*), intent(in) :: input_file
        character(len=*), intent(in) :: output_file
        logical :: success
        character(len=1000) :: line
        integer :: input_unit, output_unit, stat, comment_pos
        
        success = .false.
        
        ! Use system commands to avoid Fortran I/O issues
        call execute_command_line("cp " // trim(input_file) // " " // trim(output_file), exitstat=stat)
        if (stat /= 0) then
            write(error_unit, '(A)') "Failed to copy input file"
            return
        end if
        
        ! Remove comments using sed
        call execute_command_line("sed -i 's/!.*$//' " // trim(output_file), exitstat=stat)
        if (stat /= 0) then
            write(error_unit, '(A)') "Failed to remove comments"
            return
        end if
        
        ! Remove empty lines
        call execute_command_line("sed -i '/^[[:space:]]*$/d' " // trim(output_file), exitstat=stat)
        if (stat /= 0) then
            write(error_unit, '(A)') "Failed to remove empty lines"
            return
        end if
        
        ! Fix array syntax - remove (:) from variable names
        call execute_command_line("sed -i 's/(:)//' " // trim(output_file), exitstat=stat)
        if (stat /= 0) then
            write(error_unit, '(A)') "Failed to fix array syntax"
            return
        end if
        
        ! Remove trailing commas at end of lines
        call execute_command_line("sed -i 's/,$//' " // trim(output_file), exitstat=stat)
        if (stat /= 0) then
            write(error_unit, '(A)') "Failed to remove trailing commas"
            return
        end if
        
        success = .true.
        write(*, '(A)') "Cleaned input file for jVMEC: " // trim(output_file)
    end function jvmec_clean_input_for_jvmec

end module jvmec_implementation