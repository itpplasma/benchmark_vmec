module external_vmec_implementation
    use iso_fortran_env, only: error_unit, output_unit, real64
    use vmec_implementation_base, only: vmec_implementation_t, select_python_command
    use vmec_benchmark_types, only: vmec_result_t
    use wout_reader, only: wout_data_t, read_wout_file
    implicit none
    private

    public :: vmex_t, desc_t, gvec_t, parvmec_t, spec_t, spectre_t, freegs_t, chease_t

    ! The three projects below have independent command-line interfaces, but
    ! they all have a Python package and (where a VMEC wout is available) use
    ! the same NetCDF interchange format.  Keep the common lifecycle here so
    ! adding a participant does not duplicate process and output handling.
    type, abstract, extends(vmec_implementation_t) :: external_vmec_base_t
    contains
        procedure :: build => external_vmec_build
        procedure :: run_case => external_vmec_run_case
        procedure :: extract_results => external_vmec_extract_results
    end type external_vmec_base_t

    type, extends(external_vmec_base_t) :: vmex_t
    end type vmex_t

    type, extends(external_vmec_base_t) :: desc_t
    end type desc_t

    type, extends(external_vmec_base_t) :: gvec_t
    end type gvec_t

    type, extends(external_vmec_base_t) :: parvmec_t
    end type parvmec_t

    type, extends(external_vmec_base_t) :: spec_t
    end type spec_t

    type, extends(external_vmec_base_t) :: spectre_t
    end type spectre_t

    type, extends(external_vmec_base_t) :: freegs_t
    end type freegs_t

    type, extends(external_vmec_base_t) :: chease_t
    end type chease_t

contains

    function external_vmec_build(this) result(success)
        class(external_vmec_base_t), intent(inout) :: this
        logical :: success
        character(len=:), allocatable :: python_cmd, module_name, tool_name, env_name, cmd
        character(len=512) :: resolved_tool
        integer :: stat, length, env_status
        logical :: exists

        success = .false.
        inquire(file=trim(this%path), exist=exists)
        if (.not. exists) then
            write(error_unit, '(A)') trim(this%name) // ' path does not exist: ' // trim(this%path)
            return
        end if

        python_cmd = select_python_command(this%path)
        call external_kind(this%name, module_name, tool_name, env_name)

        ! Prefer an executable installed in the repository virtualenv.  This
        ! avoids relying on whichever global Python happens to be first on PATH.
        resolved_tool = ''
        inquire(file=trim(this%path) // '/.venv/bin/' // trim(tool_name), exist=exists)
        if (.not. exists .and. trim(lowercase(this%name)) == 'freegs') then
            tool_name = 'python'
            inquire(file=trim(this%path) // '/.venv/bin/python', exist=exists)
        end if
        if (exists) then
            this%executable = trim(this%path) // '/.venv/bin/' // trim(tool_name)
            this%available = .true.
            success = .true.
            return
        end if

        call get_environment_variable('VMEC_BENCHMARK_' // uppercase(trim(env_name)), &
            resolved_tool, length=length, status=env_status)
        if ((env_status /= 0 .or. length <= 0) .and. trim(env_name) /= trim(tool_name)) then
            call get_environment_variable('VMEC_BENCHMARK_' // uppercase(trim(tool_name)), &
                resolved_tool, length=length, status=env_status)
        end if
        if (env_status == 0 .and. length > 0) then
            inquire(file=trim(resolved_tool(1:length)), exist=exists)
            if (exists) then
                this%executable = trim(resolved_tool(1:length))
                this%available = .true.
                success = .true.
                return
            end if
        end if

        ! Native Fortran/C++ participants do not have Python console scripts.
        ! A checkout is considered available when its conventional build
        ! artifact exists (or the explicit VMEC_BENCHMARK_* override above was
        ! supplied).
        if (trim(lowercase(this%name)) == 'spec' .or. trim(lowercase(this%name)) == 'spectre' .or. &
            trim(lowercase(this%name)) == 'parvmec' .or. trim(lowercase(this%name)) == 'chease') then
            call find_native_executable(this%path, lowercase(this%name), this%executable, exists)
            if (exists) then
                this%available = .true.
                success = .true.
                return
            end if
        end if

        ! A source checkout may be importable without an installed console
        ! script.  Test that condition explicitly and retain the selected
        ! interpreter for the run wrapper.
        cmd = 'cd ' // trim(this%path) // ' && ' // trim(python_cmd) // &
            ' -c "import ' // trim(module_name) // '"'
        call execute_command_line(trim(cmd), exitstat=stat)
        if (stat == 0) then
            this%executable = trim(python_cmd)
            this%available = .true.
            success = .true.
            write(output_unit, '(A)') trim(this%name) // ' Python module is available'
        else
            write(error_unit, '(A)') trim(this%name) // &
                ' is not installed; set VMEC_BENCHMARK_' // uppercase(trim(env_name)) // &
                ' or create ' // trim(this%path) // '/.venv/bin/' // trim(tool_name)
        end if
    end function external_vmec_build

    function external_vmec_run_case(this, input_file, output_dir, timeout) result(success)
        class(external_vmec_base_t), intent(inout) :: this
        character(len=*), intent(in) :: input_file, output_dir
        integer, intent(in), optional :: timeout
        logical :: success
        character(len=:), allocatable :: local_input, input_basename, cmd, python_cmd
        character(len=:), allocatable :: lower_name
        character(len=1024) :: benchmark_root
        integer :: stat, timeout_val, root_length, root_status

        success = .false.
        if (.not. this%validate_input(input_file)) return
        if (.not. this%prepare_output_dir(output_dir)) return
        if (.not. this%available) then
            write(error_unit, '(A)') trim(this%name) // ' is not available'
            return
        end if

        timeout_val = 300
        if (present(timeout)) timeout_val = timeout
        benchmark_root = ''
        call get_environment_variable('BENCHMARK_REPO_ROOT', benchmark_root, length=root_length, status=root_status)
        if (root_status /= 0 .or. root_length <= 0) then
            benchmark_root = trim(parent_dir(this%path)) // '/benchmark_vmec'
        end if
        local_input = trim(output_dir) // '/' // basename(input_file)
        input_basename = basename(local_input)
        cmd = 'cp ' // trim(input_file) // ' ' // trim(local_input)
        call execute_command_line(trim(cmd), exitstat=stat)
        if (stat /= 0) then
            write(error_unit, '(A)') 'Failed to copy input for ' // trim(this%name)
            return
        end if

        lower_name = lowercase(this%name)
        select case (trim(lower_name))
        case ('vmex')
            if (index(trim(this%executable), '/python') > 0 .or. &
                index(trim(this%executable), 'python') == 1) then
                cmd = trim(this%executable) // ' -m vmex ' // basename(local_input)
            else
                cmd = trim(this%executable) // ' ' // basename(local_input)
            end if
        case ('desc')
            if (index(trim(this%executable), 'python') > 0) then
                cmd = trim(this%executable) // ' -m desc ' // basename(local_input) // &
                    ' --output desc_output.h5'
            else
                cmd = trim(this%executable) // ' ' // basename(local_input) // &
                    ' --output desc_output.h5'
            end if
        case ('gvec')
            ! GVEC accepts its own parameter files.  Keep the conversion in
            ! the benchmark output directory so the exact generated input is
            ! retained alongside the run log.
            if (index(lowercase(basename(local_input)), 'input.') == 1) then
                if (index(trim(this%executable), 'python') > 0) then
                    cmd = trim(this%executable) // ' -m gvec.scripts.main convert-params --vmec ' // &
                        basename(local_input) // ' parameter.ini'
                else
                    cmd = trim(this%executable) // ' convert-params --vmec ' // &
                        basename(local_input) // ' parameter.ini'
                end if
                call execute_command_line('cd ' // trim(output_dir) // ' && ' // trim(cmd) // &
                    ' >> gvec.log 2>&1', exitstat=stat)
                if (stat /= 0) then
                    write(error_unit, '(A)') 'GVEC VMEC-to-parameter conversion failed'
                    return
                end if
                local_input = trim(output_dir) // '/parameter.ini'
            end if
            if (index(trim(this%executable), 'python') > 0) then
                cmd = trim(this%executable) // ' -m gvec.scripts.main run ' // basename(local_input)
            else
                cmd = trim(this%executable) // ' run ' // basename(local_input)
            end if
        case ('freegs')
            if (index(lowercase(input_file), '/2d') == 0) then
                write(error_unit, '(A)') 'FreeGS supports only the benchmark 2-D Grad-Shafranov lane'
                return
            end if
            cmd = trim(this%executable) // ' ' // trim(benchmark_root) // &
                '/tools/run_freegs.py ' // trim(local_input) // ' ' // trim(output_dir)
        case ('spec')
            ! SPEC's executable expects its native .sp namelist.  The runner
            ! filters VMEC inputs before this point; keeping the command
            ! literal here prevents an accidental MPI_ABORT from feeding
            ! ``&INDATA`` to xspec.
            cmd = trim(this%executable) // ' ' // basename(local_input)
        case ('spectre')
            python_cmd = select_python_command(this%path)
            if (index(lowercase(basename(local_input)), '.toml') > 0) then
                cmd = 'env PYTHONPATH=' // trim(this%path) // ' ' // trim(python_cmd) // ' ' // &
                    trim(benchmark_root) // &
                    '/tools/run_spectre.py ' // basename(local_input)
            else
                ! VMEC INDATA is converted to a retained TOML artifact before
                ! the SPECTRE minimizer is launched.  This is deliberately a
                ! separate process so converter failures are reported as such
                ! instead of appearing as a solver syntax error.
                cmd = 'env PYTHONPATH=' // trim(this%path) // ' ' // trim(python_cmd) // ' ' // &
                    trim(benchmark_root) // &
                    '/tools/convert_vmec_to_spectre.py ' // basename(local_input) // &
                    ' spectre_input.toml'
                call execute_command_line('cd ' // trim(output_dir) // ' && ' // trim(cmd) // &
                    ' >> spectre.log 2>&1', exitstat=stat)
                if (stat /= 0) then
                    write(error_unit, '(A)') 'SPECTRE VMEC-to-TOML conversion failed'
                    return
                end if
                cmd = 'env PYTHONPATH=' // trim(this%path) // ' ' // trim(python_cmd) // ' ' // &
                    trim(benchmark_root) // &
                    '/tools/run_spectre.py spectre_input.toml'
            end if
        case ('parvmec')
            cmd = trim(this%executable) // ' ' // basename(local_input)
        case ('chease')
            if (index(lowercase(basename(local_input)), '.geqdsk') > 0 .or. &
                index(lowercase(basename(local_input)), '.eqdsk') > 0) then
                cmd = 'env PATH=' // trim(this%path) // '/src-f90:' // trim(this%path) // &
                    '/scripts_for_bin:$PATH ' // trim(this%path) // &
                    '/scripts_for_bin/run.chease.eqdsk ' // basename(local_input) // ' . .'
            else
                write(error_unit, '(A)') 'CHEASE requires a native GEQDSK input'
                return
            end if
        case default
            write(error_unit, '(A)') 'Unknown external VMEC implementation: ' // trim(this%name)
            return
        end select

        cmd = 'cd ' // trim(output_dir) // ' && timeout ' // int_to_str(timeout_val) // &
            ' ' // trim(cmd) // ' > ' // trim(lower_name) // '.log 2>&1'
        call execute_command_line(trim(cmd), exitstat=stat)

        if (stat == 0) then
            ! DESC's native HDF5 output is converted to the shared wout format
            ! when possible.  GVEC may also be configured to write a wout file;
            ! otherwise extraction reports the missing interchange artifact.
            if (trim(lower_name) == 'desc') then
                call write_desc_conversion_script(output_dir)
                cmd = 'cd ' // trim(output_dir) // ' && ' // trim(select_python_command(this%path)) // &
                    ' desc_to_wout.py >> desc.log 2>&1'
                call execute_command_line(trim(cmd), exitstat=stat)
            end if
            if (trim(lower_name) == 'gvec' .and. stat == 0) then
                ! GVEC's native state is a text file rather than VMEC NetCDF.
                ! Retain it and emit the ordinary scalar comparison sidecar.
                cmd = 'cd ' // trim(output_dir) // ' && ' // trim(this%executable) // ' ' // &
                    trim(benchmark_root) // &
                    '/tools/convert_gvec_to_common.py ' // &
                    input_basename // '_State_final.dat gvec_result.json'
                call execute_command_line(trim(cmd), exitstat=stat)
            end if
            if (trim(lower_name) == 'chease' .and. stat == 0) then
                call write_chease_sidecar(output_dir, stat)
            end if
            success = (stat == 0)
        else if (stat == 124) then
            write(error_unit, '(A)') trim(this%name) // ' timed out for ' // basename(input_file)
        else
            write(error_unit, '(A)') trim(this%name) // ' failed for ' // basename(input_file)
        end if
    end function external_vmec_run_case

    subroutine external_vmec_extract_results(this, output_dir, results)
        class(external_vmec_base_t), intent(in) :: this
        character(len=*), intent(in) :: output_dir
        type(vmec_result_t), intent(out) :: results
        character(len=512) :: wout_file
        type(wout_data_t) :: wout_data
        integer :: stat, unit
        logical :: exists, read_success

        call results%clear()
        if (trim(lowercase(this%name)) == 'freegs') then
            call extract_freegs_results(output_dir, results)
            return
        end if
        if (trim(lowercase(this%name)) == 'gvec') then
            call extract_gvec_results(output_dir, results)
            return
        end if
        if (trim(lowercase(this%name)) == 'spectre') then
            call extract_spectre_results(output_dir, results)
            return
        end if
        if (trim(lowercase(this%name)) == 'chease') then
            call extract_chease_results(output_dir, results)
            return
        end if
        call execute_command_line('ls -t ' // trim(output_dir) // &
            '/wout_*.nc 2>/dev/null | head -1 > /tmp/vmec_external_wout.tmp', &
            exitstat=stat)
        if (stat /= 0) then
            results%error_message = 'No wout file found for ' // trim(this%name)
            return
        end if

        open(newunit=unit, file='/tmp/vmec_external_wout.tmp', status='old', action='read', iostat=stat)
        if (stat /= 0) then
            results%error_message = 'Could not inspect ' // trim(this%name) // ' output'
            return
        end if
        read(unit, '(A)', iostat=stat) wout_file
        close(unit)
        if (stat /= 0 .or. len_trim(wout_file) == 0) then
            results%error_message = 'No VMEC NetCDF output produced by ' // trim(this%name)
            return
        end if

        wout_file = trim(adjustl(wout_file))
        inquire(file=trim(wout_file), exist=exists)
        if (.not. exists) then
            results%error_message = 'Missing wout file: ' // trim(wout_file)
            return
        end if
        read_success = read_wout_file(trim(wout_file), wout_data)
        if (.not. read_success .or. .not. wout_data%valid) then
            results%error_message = 'Could not read wout file: ' // trim(wout_file)
            return
        end if

        results%success = .true.
        results%dimension = 3
        results%family = 'vmec_family'
        results%input_format = 'vmec_indata'
        results%output_format = 'wout_netcdf'
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
        call copy_wout_arrays(wout_data, results)
    end subroutine external_vmec_extract_results

    subroutine extract_freegs_results(output_dir, results)
        character(len=*), intent(in) :: output_dir
        type(vmec_result_t), intent(inout) :: results
        character(len=512) :: line
        character(len=:), allocatable :: filename
        integer :: unit, stat
        logical :: exists, success_value
        real(real64) :: value

        filename = trim(output_dir)//'/freegs_result.json'
        inquire(file=filename, exist=exists)
        if (.not. exists) then
            results%error_message = 'FreeGS did not produce freegs_result.json'
            return
        end if
        open(newunit=unit, file=filename, status='old', action='read', iostat=stat)
        if (stat /= 0) then
            results%error_message = 'Could not read FreeGS result sidecar'
            return
        end if
        success_value = .false.
        do
            read(unit, '(A)', iostat=stat) line
            if (stat /= 0) exit
            if (index(line, '"success"') > 0) success_value = index(line, 'true') > 0
            if (json_number(line, 'pressure_axis', value)) results%pressure_axis = value
            if (json_number(line, 'plasma_current', value)) results%plasma_current = value
            if (json_number(line, 'betapol', value)) results%betapol = value
            if (index(line, '"dimension"') > 0) then
                read(line(index(line, ':')+1:), *, iostat=stat) results%dimension
            end if
        end do
        close(unit)
        results%family = 'grad_shafranov'
        results%input_format = 'vmec_indata_or_case'
        results%output_format = 'geqdsk'
        results%success = success_value
        if (.not. success_value) results%error_message = 'FreeGS sidecar reports failure'
    end subroutine extract_freegs_results

    subroutine extract_gvec_results(output_dir, results)
        character(len=*), intent(in) :: output_dir
        type(vmec_result_t), intent(inout) :: results
        character(len=512) :: line
        character(len=:), allocatable :: filename
        integer :: unit, stat
        logical :: exists, success_value
        real(real64) :: value

        filename = trim(output_dir) // '/gvec_result.json'
        inquire(file=filename, exist=exists)
        if (.not. exists) then
            results%error_message = 'GVEC did not produce gvec_result.json'
            return
        end if
        open(newunit=unit, file=filename, status='old', action='read', iostat=stat)
        if (stat /= 0) then
            results%error_message = 'Could not read GVEC result sidecar'
            return
        end if
        success_value = .false.
        do
            read(unit, '(A)', iostat=stat) line
            if (stat /= 0) exit
            if (index(line, '"success"') > 0) success_value = index(line, 'true') > 0
            if (json_number(line, 'pressure_axis', value)) results%pressure_axis = value
            if (json_number(line, 'plasma_current', value)) results%plasma_current = value
            if (json_number(line, 'betapol', value)) results%betapol = value
            if (json_number(line, 'force_residual', value)) results%force_residual = value
            if (json_number(line, 'aspect', value)) results%aspect = value
            if (json_number(line, 'raxis_cc', value)) results%raxis_cc = value
            if (json_number(line, 'volume_p', value)) results%volume_p = value
            if (json_number(line, 'iotaf_edge', value)) results%iotaf_edge = value
            if (json_number(line, 'rmajor_p', value)) results%rmajor_p = value
            if (json_number(line, 'aminor_p', value)) results%aminor_p = value
        end do
        close(unit)
        results%success = success_value
        results%dimension = 3
        results%family = 'vmec_family'
        results%input_format = 'vmec_indata'
        results%output_format = 'gvec_state'
        if (.not. success_value) results%error_message = 'GVEC sidecar reports failure'
    end subroutine extract_gvec_results

    subroutine extract_spectre_results(output_dir, results)
        character(len=*), intent(in) :: output_dir
        type(vmec_result_t), intent(inout) :: results
        integer :: stat, unit
        character(len=512) :: filename
        logical :: exists

        call execute_command_line('ls -t ' // trim(output_dir) // &
            '/*_res.json 2>/dev/null | head -1 > /tmp/spectre_result.tmp', exitstat=stat)
        if (stat /= 0) then
            results%error_message = 'SPECTRE produced no result JSON'
            return
        end if
        open(newunit=unit, file='/tmp/spectre_result.tmp', status='old', action='read', iostat=stat)
        if (stat /= 0) then
            results%error_message = 'Could not inspect SPECTRE result JSON'
            return
        end if
        read(unit, '(A)', iostat=stat) filename
        close(unit)
        filename = trim(adjustl(filename))
        inquire(file=trim(filename), exist=exists)
        if (.not. exists) then
            results%error_message = 'SPECTRE result JSON is missing'
            return
        end if
        results%success = .true.
        results%dimension = 3
        results%family = 'spectre_mhd'
        results%input_format = 'vmec_indata_or_spectre_toml'
        results%output_format = 'spectre_json'
    end subroutine extract_spectre_results

    subroutine extract_chease_results(output_dir, results)
        character(len=*), intent(in) :: output_dir
        type(vmec_result_t), intent(inout) :: results
        character(len=:), allocatable :: filename
        integer :: unit, stat
        logical :: exists, success_value
        character(len=512) :: line

        filename = trim(output_dir) // '/chease_result.json'
        inquire(file=filename, exist=exists)
        if (.not. exists) then
            results%error_message = 'CHEASE did not produce chease_result.json'
            return
        end if
        open(newunit=unit, file=filename, status='old', action='read', iostat=stat)
        if (stat /= 0) then
            results%error_message = 'Could not read CHEASE result sidecar'
            return
        end if
        success_value = .false.
        do
            read(unit, '(A)', iostat=stat) line
            if (stat /= 0) exit
            if (index(line, '"success"') > 0) success_value = index(line, 'true') > 0
        end do
        close(unit)
        results%success = success_value
        results%dimension = 2
        results%family = 'grad_shafranov'
        results%input_format = 'vmec_indata_via_geqdsk'
        results%output_format = 'geqdsk'
        if (.not. success_value) results%error_message = 'CHEASE sidecar reports failure'
    end subroutine extract_chease_results

    subroutine write_chease_sidecar(output_dir, status)
        character(len=*), intent(in) :: output_dir
        integer, intent(out) :: status
        integer :: unit

        ! The CHEASE wrapper appends the input basename to its output name
        ! (EQDSK_COCOS_02.OUT.<case>), so match the documented prefix rather
        ! than one exact filename.
        call execute_command_line('ls -1 ' // trim(output_dir) // &
            '/EQDSK_COCOS_02.OUT* >/dev/null 2>&1', exitstat=status)
        if (status /= 0) return
        open(newunit=unit, file=trim(output_dir) // '/chease_result.json', status='replace', &
            action='write', iostat=status)
        if (status /= 0) return
        write(unit, '(A)') '{"success": true, "dimension": 2, "output_format": "geqdsk"}'
        close(unit)
        status = 0
    end subroutine write_chease_sidecar

    logical function json_number(line, key, value)
        character(len=*), intent(in) :: line, key
        real(real64), intent(out) :: value
        integer :: colon, stat
        character(len=256) :: tail

        json_number = .false.
        value = 0.0_real64
        if (index(line, '"'//trim(key)//'"') == 0) return
        colon = index(line, ':')
        if (colon == 0) return
        tail = adjustl(line(colon+1:))
        read(tail, *, iostat=stat) value
        json_number = stat == 0
    end function json_number

    subroutine copy_wout_arrays(source, target)
        type(wout_data_t), intent(in) :: source
        type(vmec_result_t), intent(inout) :: target

        if (allocated(source%rmnc)) then
            allocate(target%rmnc(size(source%rmnc, 1), size(source%rmnc, 2)))
            target%rmnc = source%rmnc
        end if
        if (allocated(source%rmns)) then
            allocate(target%rmns(size(source%rmns, 1), size(source%rmns, 2)))
            target%rmns = source%rmns
        end if
        if (allocated(source%zmnc)) then
            allocate(target%zmnc(size(source%zmnc, 1), size(source%zmnc, 2)))
            target%zmnc = source%zmnc
        end if
        if (allocated(source%zmns)) then
            allocate(target%zmns(size(source%zmns, 1), size(source%zmns, 2)))
            target%zmns = source%zmns
        end if
        if (allocated(source%lmnc)) then
            allocate(target%lmnc(size(source%lmnc, 1), size(source%lmnc, 2)))
            target%lmnc = source%lmnc
        end if
        if (allocated(source%lmns)) then
            allocate(target%lmns(size(source%lmns, 1), size(source%lmns, 2)))
            target%lmns = source%lmns
        end if
        if (allocated(source%xm)) then
            allocate(target%xm(size(source%xm)))
            target%xm = source%xm
        end if
        if (allocated(source%xn)) then
            allocate(target%xn(size(source%xn)))
            target%xn = source%xn
        end if
    end subroutine copy_wout_arrays

    subroutine write_desc_conversion_script(output_dir)
        character(len=*), intent(in) :: output_dir
        integer :: unit, stat

        open(newunit=unit, file=trim(output_dir) // '/desc_to_wout.py', status='replace', &
            action='write', iostat=stat)
        if (stat /= 0) return
        write(unit, '(A)') 'from desc.io import load'
        write(unit, '(A)') 'from desc.vmec import VMECIO'
        write(unit, '(A)') 'family = load("desc_output.h5")'
        write(unit, '(A)') 'eq = family[-1] if hasattr(family, "__getitem__") else family'
        write(unit, '(A)') 'VMECIO.save(eq, "wout_desc.nc", surfs=eq.L_grid + 1, verbose=0)'
        close(unit)
    end subroutine write_desc_conversion_script

    subroutine find_native_executable(path, kind, executable, found)
        character(len=*), intent(in) :: path, kind
        character(len=:), allocatable, intent(out) :: executable
        logical, intent(out) :: found
        character(len=256) :: candidates(8)
        integer :: i
        logical :: exists

        candidates = ''
        select case (trim(kind))
        case ('spec')
            candidates(1) = trim(path)//'/build/build/bin/xspec'
            candidates(2) = trim(path)//'/build/bin/xspec'
        case ('spectre')
            candidates(1) = trim(path)//'/build/fortran_src/xspec'
            candidates(2) = trim(path)//'/build/bin/xspectre'
            candidates(3) = trim(path)//'/build/bin/spectre'
        case ('parvmec')
            candidates(1) = trim(path)//'/build/bin/xvmec'
            candidates(2) = trim(path)//'/build/bin/parvmec'
            candidates(3) = trim(path)//'/xvmec'
        case ('chease')
            candidates(1) = trim(path)//'/chease'
            candidates(2) = trim(path)//'/bin/chease'
        end select
        found = .false.
        executable = ''
        do i = 1, size(candidates)
            if (len_trim(candidates(i)) == 0) cycle
            inquire(file=trim(candidates(i)), exist=exists)
            if (exists) then
                executable = trim(candidates(i))
                found = .true.
                return
            end if
        end do
    end subroutine find_native_executable

    subroutine external_kind(name, module_name, tool_name, env_name)
        character(len=*), intent(in) :: name
        character(len=:), allocatable, intent(out) :: module_name, tool_name, env_name

        select case (trim(lowercase(name)))
        case ('vmex')
            module_name = 'vmex'
            tool_name = 'vmex'
            env_name = 'vmex'
        case ('desc')
            module_name = 'desc'
            tool_name = 'desc'
            env_name = 'desc'
        case ('gvec')
            module_name = 'gvec'
            tool_name = 'pygvec'
            env_name = 'gvec'
        case ('parvmec')
            module_name = 'parvmec'
            tool_name = 'parvmec'
            env_name = 'parvmec'
        case ('spec')
            module_name = 'spec'
            tool_name = 'xspec'
            env_name = 'spec'
        case ('spectre')
            module_name = 'spectre'
            tool_name = 'spectre'
            env_name = 'spectre'
        case ('freegs')
            module_name = 'freegs'
            tool_name = 'freegs'
            env_name = 'freegs'
        case ('chease')
            module_name = 'chease'
            tool_name = 'chease'
            env_name = 'chease'
        case default
            module_name = trim(name)
            tool_name = trim(name)
            env_name = trim(name)
        end select
    end subroutine external_kind

    function basename(path) result(name)
        character(len=*), intent(in) :: path
        character(len=:), allocatable :: name
        integer :: slash

        slash = index(path, '/', back=.true.)
        if (slash > 0) then
            name = path(slash + 1:)
        else
            name = trim(path)
        end if
    end function basename

    function parent_dir(path) result(name)
        character(len=*), intent(in) :: path
        character(len=:), allocatable :: name
        integer :: slash

        slash = index(trim(path), '/', back=.true.)
        if (slash > 1) then
            name = trim(path(1:slash-1))
        else
            name = '.'
        end if
    end function parent_dir

    function lowercase(text) result(value)
        character(len=*), intent(in) :: text
        character(len=:), allocatable :: value
        integer :: i

        value = text
        do i = 1, len(value)
            if (value(i:i) >= 'A' .and. value(i:i) <= 'Z') then
                value(i:i) = char(ichar(value(i:i)) + 32)
            end if
        end do
    end function lowercase

    function uppercase(text) result(value)
        character(len=*), intent(in) :: text
        character(len=:), allocatable :: value
        integer :: i

        value = text
        do i = 1, len(value)
            if (value(i:i) >= 'a' .and. value(i:i) <= 'z') then
                value(i:i) = char(ichar(value(i:i)) - 32)
            end if
        end do
    end function uppercase

    function int_to_str(value) result(text)
        integer, intent(in) :: value
        character(len=:), allocatable :: text
        character(len=32) :: buffer

        write(buffer, '(I0)') value
        text = trim(buffer)
    end function int_to_str

end module external_vmec_implementation
