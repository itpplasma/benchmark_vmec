module jvmec_implementation
    use iso_fortran_env, only: real64, error_unit, output_unit
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
            this%executable = "java -cp " // trim(this%path) // "/target/jVMEC-1.0.0.jar:" // &
                             trim(this%path) // "/target/dependency/* de.labathome.jvmec.VmecRunner"
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
            this%executable = "java -cp " // trim(this%path) // "/target/classes:" // &
                             trim(this%path) // "/target/dependency/* de.labathome.jvmec.VmecRunner"
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
            this%executable = "java -cp " // trim(this%path) // "/target/jVMEC-1.0.0.jar:" // &
                             trim(this%path) // "/target/dependency/* de.labathome.jvmec.VmecRunner"
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
        integer :: stat, ncid, varid, dimid, i, nfp_val
        integer :: ns, mnmax
        real(real64), allocatable :: iotas_temp(:)
        real(real64), allocatable :: rmns_local(:,:), zmnc_local(:,:)
        logical :: have_aspect, have_volume, have_rmajor, have_aminor, scalar_found
        logical :: exists
        
        call results%clear()
        
        ! Look for VMEC output files (wout.nc or wout_*.nc)
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
                results%error_message = "Failed to open jVMEC NetCDF file: " // trim(nf90_strerror(stat))
                return
            end if
            
            ! Read actual array dimensions from NetCDF file
            stat = nf90_inq_dimid(ncid, "rmnc_dim0", dimid)
            if (stat == NF90_NOERR) then
                stat = nf90_inquire_dimension(ncid, dimid, len=ns)
            else
                ns = 0
            end if
            
            stat = nf90_inq_dimid(ncid, "rmnc_dim1", dimid)  
            if (stat == NF90_NOERR) then
                stat = nf90_inquire_dimension(ncid, dimid, len=mnmax)
            else
                mnmax = 0
            end if
            
            if (ns <= 0 .or. mnmax <= 0) then
                results%error_message = "Invalid dimensions in jVMEC output: ns=" // &
                                      trim(int_to_str(ns)) // ", mnmax=" // trim(int_to_str(mnmax))
                stat = nf90_close(ncid)
                return
            end if
            
            ! Store dimensions locally for array allocation
            
            ! Read number of field periods for calculations
            stat = nf90_inq_varid(ncid, "nfp", varid)
            if (stat == NF90_NOERR) then
                stat = nf90_get_var(ncid, varid, nfp_val)
            else
                nfp_val = 1
            end if
            
            ! Allocate arrays with correct dimensions
            allocate(results%rmnc(ns, mnmax))
            allocate(results%zmns(ns, mnmax))
            allocate(results%lmns(ns, mnmax))
            allocate(results%xm(mnmax))
            allocate(results%xn(mnmax))
            allocate(rmns_local(ns, mnmax))
            allocate(zmnc_local(ns, mnmax))
            
            ! Initialize arrays to zero
            results%rmnc = 0.0_real64
            results%zmns = 0.0_real64
            results%lmns = 0.0_real64
            results%xm = 0
            results%xn = 0
            rmns_local = 0.0_real64
            zmnc_local = 0.0_real64

            ! Prefer quantities computed by jVMEC itself.  The Fourier
            ! geometry below remains a fallback for older wout files.
            have_aspect = read_jvmec_scalar(ncid, "aspect", results%aspect)
            have_volume = read_jvmec_scalar(ncid, "volume_p", results%volume_p)
            have_rmajor = read_jvmec_scalar(ncid, "Rmajor_p", results%rmajor_p)
            have_aminor = read_jvmec_scalar(ncid, "Aminor_p", results%aminor_p)
            scalar_found = read_jvmec_scalar(ncid, "wb", results%wb)
            scalar_found = read_jvmec_scalar(ncid, "betatotal", results%betatotal)
            scalar_found = read_jvmec_scalar(ncid, "betapol", results%betapol)
            scalar_found = read_jvmec_scalar(ncid, "betator", results%betator)
            scalar_found = read_jvmec_scalar(ncid, "b0", results%b0)
            scalar_found = read_jvmec_scalar(ncid, "ctor", results%itor)
            
            ! Read Fourier coefficients
            stat = nf90_inq_varid(ncid, "rmnc", varid)
            if (stat == NF90_NOERR) then
                block
                    real(real64), allocatable :: rmnc_temp(:,:)
                    allocate(rmnc_temp(mnmax, ns))
                    stat = nf90_get_var(ncid, varid, rmnc_temp, start=[1,1], count=[mnmax,ns])
                    if (stat == NF90_NOERR) then
                        results%rmnc = transpose(rmnc_temp)
                    else
                        write(error_unit, '(A)') "Warning: Failed to read rmnc: " // trim(nf90_strerror(stat))
                    end if
                    deallocate(rmnc_temp)
                end block
            end if
            
            stat = nf90_inq_varid(ncid, "zmns", varid)
            if (stat == NF90_NOERR) then
                block
                    real(real64), allocatable :: zmns_temp(:,:)
                    allocate(zmns_temp(mnmax, ns))
                    stat = nf90_get_var(ncid, varid, zmns_temp, start=[1,1], count=[mnmax,ns])
                    if (stat == NF90_NOERR) then
                        results%zmns = transpose(zmns_temp)
                    else
                        write(error_unit, '(A)') "Warning: Failed to read zmns: " // trim(nf90_strerror(stat))
                    end if
                    deallocate(zmns_temp)
                end block
            end if
            
            stat = nf90_inq_varid(ncid, "lmns", varid)
            if (stat == NF90_NOERR) then
                block
                    real(real64), allocatable :: lmns_temp(:,:)
                    allocate(lmns_temp(mnmax, ns))
                    stat = nf90_get_var(ncid, varid, lmns_temp, start=[1,1], count=[mnmax,ns])
                    if (stat == NF90_NOERR) then
                        results%lmns = transpose(lmns_temp)
                    else
                        write(error_unit, '(A)') "Warning: Failed to read lmns: " // trim(nf90_strerror(stat))
                    end if
                    deallocate(lmns_temp)
                end block
            end if

            call read_jvmec_fourier(ncid, "rmns", ns, mnmax, results%rmns)
            call read_jvmec_fourier(ncid, "zmnc", ns, mnmax, results%zmnc)
            if (allocated(results%rmns)) rmns_local = results%rmns
            if (allocated(results%zmnc)) zmnc_local = results%zmnc
            
            ! Read mode numbers (convert from integer to real) - use actual xm dimension 
            stat = nf90_inq_varid(ncid, "xm", varid)
            if (stat == NF90_NOERR) then
                block
                    integer, allocatable :: xm_temp(:)
                    integer :: xm_len
                    
                    ! Get actual dimension of xm array
                    stat = nf90_inq_dimid(ncid, "xm_dim0", dimid)
                    if (stat == NF90_NOERR) then
                        stat = nf90_inquire_dimension(ncid, dimid, len=xm_len)
                        allocate(xm_temp(xm_len))
                        stat = nf90_get_var(ncid, varid, xm_temp)
                        if (stat == NF90_NOERR) then
                            results%xm(1:min(mnmax,xm_len)) = real(xm_temp(1:min(mnmax,xm_len)), real64)
                        else
                            write(error_unit, '(A)') "Warning: Failed to read xm: " // trim(nf90_strerror(stat))
                        end if
                        deallocate(xm_temp)
                    else
                        write(error_unit, '(A)') "Warning: Failed to get xm dimension"
                    end if
                end block
            end if
            
            stat = nf90_inq_varid(ncid, "xn", varid)
            if (stat == NF90_NOERR) then
                block
                    integer, allocatable :: xn_temp(:)
                    integer :: xn_len
                    
                    ! Get actual dimension of xn array
                    stat = nf90_inq_dimid(ncid, "xn_dim0", dimid)
                    if (stat == NF90_NOERR) then
                        stat = nf90_inquire_dimension(ncid, dimid, len=xn_len)
                        allocate(xn_temp(xn_len))
                        stat = nf90_get_var(ncid, varid, xn_temp)
                        if (stat == NF90_NOERR) then
                            results%xn(1:min(mnmax,xn_len)) = real(xn_temp(1:min(mnmax,xn_len)), real64)
                        else
                            write(error_unit, '(A)') "Warning: Failed to read xn: " // trim(nf90_strerror(stat))
                        end if
                        deallocate(xn_temp)
                    else
                        write(error_unit, '(A)') "Warning: Failed to get xn dimension"
                    end if
                end block
            end if
            
            ! Calculate geometry-derived quantities only when older output did
            ! not contain the corresponding scalar.  Do not use the edge m=0
            ! coefficient as a proxy for the major radius.
            if (allocated(results%rmnc) .and. allocated(results%xm) .and. allocated(results%xn)) then
                ! Find the (m=0, n=0) mode for magnetic axis
                do i = 1, mnmax
                    if (abs(results%xm(i)) < 1e-12_real64 .and. abs(results%xn(i)) < 1e-12_real64) then
                        ! Only overwrite if we don't already have a valid value from direct read
                        if (abs(results%raxis_cc) < 1e-12_real64) then
                            results%raxis_cc = results%rmnc(1, i)  ! Axis value
                        end if
                        write(output_unit, '(A,I0,A,F12.6,A,F12.6)') "Found (0,0) mode at index ", i, &
                                                                    ", rmnc(1,i)=", results%rmnc(1, i), &
                                                                    ", using raxis_cc=", results%raxis_cc
                        exit
                    end if
                end do
            else
                write(output_unit, '(A)') "rmnc arrays not successfully loaded, using direct read values"
            end if

            if (.not. have_aspect .or. .not. have_volume .or. .not. have_rmajor .or. .not. have_aminor) then
                call derive_jvmec_geometry(results%rmnc, rmns_local, zmnc_local, results%zmns, &
                                           results%xm, results%xn, real(nfp_val, real64), &
                                           results%raxis_cc, results%rmajor_p, results%aminor_p, &
                                           results%aspect, results%volume_p)
            end if
            
            ! Read rotational transform (iota)
            stat = nf90_inq_varid(ncid, "iotas", varid)
            if (stat == NF90_NOERR) then
                allocate(iotas_temp(ns))
                stat = nf90_get_var(ncid, varid, iotas_temp)
                if (stat == NF90_NOERR .and. ns > 0) then
                    results%iotaf_edge = iotas_temp(ns)  ! Edge value
                end if
                deallocate(iotas_temp)
            end if
            
            ! Close NetCDF file
            stat = nf90_close(ncid)
            
            results%success = .true.
            results%error_message = "jVMEC data extracted successfully"
            
            ! Debug output
            write(output_unit, '(A)') "jVMEC extraction successful:"
            write(output_unit, '(A,I0)') "  ns = ", ns
            write(output_unit, '(A,I0)') "  mnmax = ", mnmax
            write(output_unit, '(A,F12.6)') "  raxis_cc = ", results%raxis_cc
            write(output_unit, '(A,F12.6)') "  aspect = ", results%aspect
            write(output_unit, '(A,F12.6)') "  volume_p = ", results%volume_p
            write(output_unit, '(A,F12.6)') "  iotaf_edge = ", results%iotaf_edge
            
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

    logical function read_jvmec_scalar(ncid, name, value)
        use netcdf
        integer, intent(in) :: ncid
        character(len=*), intent(in) :: name
        real(real64), intent(out) :: value
        integer :: varid, status

        value = 0.0_real64
        read_jvmec_scalar = .false.
        status = nf90_inq_varid(ncid, trim(name), varid)
        if (status /= NF90_NOERR) return
        status = nf90_get_var(ncid, varid, value)
        if (status == NF90_NOERR) read_jvmec_scalar = .true.
    end function read_jvmec_scalar

    subroutine read_jvmec_fourier(ncid, name, ns, mnmax, values)
        use netcdf
        integer, intent(in) :: ncid, ns, mnmax
        character(len=*), intent(in) :: name
        real(real64), allocatable, intent(out) :: values(:,:)
        integer :: varid, status
        real(real64), allocatable :: temporary(:,:)

        status = nf90_inq_varid(ncid, trim(name), varid)
        if (status /= NF90_NOERR) return
        allocate(temporary(mnmax, ns))
        status = nf90_get_var(ncid, varid, temporary, start=[1, 1], count=[mnmax, ns])
        if (status == NF90_NOERR) then
            allocate(values(ns, mnmax))
            values = transpose(temporary)
        end if
        deallocate(temporary)
    end subroutine read_jvmec_fourier

    subroutine derive_jvmec_geometry(rmnc, rmns, zmnc, zmns, xm, xn, nfp, &
                                     raxis, rmajor, aminor, aspect, volume)
        integer, parameter :: ntheta = 128, nphi = 64
        real(real64), parameter :: two_pi = 2.0_real64 * acos(-1.0_real64)
        real(real64), intent(in) :: rmnc(:,:), rmns(:,:), zmnc(:,:), zmns(:,:)
        real(real64), intent(in) :: xm(:), xn(:), nfp
        real(real64), intent(out) :: raxis, rmajor, aminor, aspect, volume
        integer :: itheta, iphi, imode, ns, mnmax, mode00
        real(real64) :: theta, phi, phase, radius, height_theta
        real(real64) :: rmin, rmax, volume_sum

        ns = size(rmnc, 1)
        mnmax = size(rmnc, 2)
        mode00 = 1
        do imode = 1, mnmax
            if (abs(xm(imode)) < 1.0e-12_real64) then
                if (abs(xn(imode)) < 1.0e-12_real64) then
                    mode00 = imode
                    exit
                end if
            end if
        end do
        raxis = rmnc(1, mode00)
        rmin = huge(1.0_real64)
        rmax = -huge(1.0_real64)
        volume_sum = 0.0_real64
        do iphi = 1, nphi
            phi = two_pi * real(iphi - 1, real64) / real(nphi, real64)
            do itheta = 1, ntheta
                theta = two_pi * real(itheta - 1, real64) / real(ntheta, real64)
                radius = 0.0_real64
                height_theta = 0.0_real64
                do imode = 1, mnmax
                    phase = xm(imode) * theta - xn(imode) * phi / nfp
                    radius = radius + rmnc(ns, imode) * cos(phase) + &
                             rmns(ns, imode) * sin(phase)
                    height_theta = height_theta - xm(imode) * zmnc(ns, imode) * sin(phase) + &
                                   xm(imode) * zmns(ns, imode) * cos(phase)
                end do
                rmin = min(rmin, radius)
                rmax = max(rmax, radius)
                volume_sum = volume_sum + radius * radius * height_theta
            end do
        end do
        rmajor = 0.5_real64 * (rmax + rmin)
        aminor = 0.5_real64 * (rmax - rmin)
        if (aminor > 0.0_real64) then
            aspect = rmajor / aminor
        else
            aspect = 0.0_real64
        end if
        volume = abs(0.5_real64 * volume_sum / real(ntheta * nphi, real64) * two_pi**2)
    end subroutine derive_jvmec_geometry

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
