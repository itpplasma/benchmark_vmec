module benchmark_runner
    use iso_fortran_env, only: error_unit, output_unit
    use vmec_benchmark_types, only: vmec_result_t, string_t
    use vmec_implementation_base, only: vmec_implementation_t
    use educational_vmec_implementation, only: educational_vmec_t
    use jvmec_implementation, only: jvmec_t
    use vmec2000_implementation, only: vmec2000_t
    use vmecpp_implementation, only: vmecpp_t
    use external_vmec_implementation, only: vmex_t, desc_t, gvec_t, parvmec_t, spec_t, spectre_t, freegs_t, chease_t
    use repository_manager, only: repository_manager_t
    use results_comparator, only: results_comparator_t
    implicit none
    private

    public :: benchmark_runner_t, freegs_case_supported, chease_case_supported
    public :: spec_case_supported, spectre_case_supported

    type :: implementation_entry_t
        character(len=:), allocatable :: key
        class(vmec_implementation_t), allocatable :: impl
    end type implementation_entry_t

    type :: benchmark_runner_t
        character(len=:), allocatable :: output_dir
        type(repository_manager_t) :: repo_manager
        type(implementation_entry_t), allocatable :: implementations(:)
        integer :: n_implementations = 0
        type(string_t), allocatable :: test_cases(:)
        integer :: n_test_cases = 0
    contains
        procedure :: initialize => benchmark_runner_initialize
        procedure :: setup_implementations => benchmark_runner_setup_implementations
        procedure :: discover_test_cases => benchmark_runner_discover_test_cases
        procedure :: discover_from_all_repos => discover_from_all_repos
        procedure :: run_single_case => benchmark_runner_run_single_case
        procedure :: run_all_cases => benchmark_runner_run_all_cases
        procedure :: get_implementation_names => benchmark_runner_get_implementation_names
        procedure :: get_test_case_names => benchmark_runner_get_test_case_names
        procedure :: finalize => benchmark_runner_finalize
        procedure, private :: is_duplicate_json => benchmark_runner_is_duplicate_json
        procedure, private :: is_duplicate_case => benchmark_runner_is_duplicate_case
        procedure, private :: is_free_boundary => benchmark_runner_is_free_boundary
        procedure, private :: is_symmetric_case => benchmark_runner_is_symmetric_case
    end type benchmark_runner_t

contains

    subroutine benchmark_runner_initialize(this, output_dir, repo_manager)
        class(benchmark_runner_t), intent(inout) :: this
        character(len=*), intent(in) :: output_dir
        type(repository_manager_t), intent(in) :: repo_manager
        integer :: stat

        this%output_dir = trim(output_dir)
        this%repo_manager = repo_manager

        ! Create output directory
        call execute_command_line("mkdir -p " // trim(this%output_dir), exitstat=stat)
    end subroutine benchmark_runner_initialize

    subroutine benchmark_runner_setup_implementations(this)
        class(benchmark_runner_t), intent(inout) :: this
        character(len=:), allocatable :: repo_path
        type(educational_vmec_t), allocatable :: edu_vmec
        type(jvmec_t), allocatable :: jvmec
        type(vmec2000_t), allocatable :: vmec2000
        type(vmecpp_t), allocatable :: vmecpp
        type(vmex_t), allocatable :: vmex
        type(desc_t), allocatable :: desc
        type(gvec_t), allocatable :: gvec
        type(parvmec_t), allocatable :: parvmec
        type(spec_t), allocatable :: spec
        type(spectre_t), allocatable :: spectre
        type(freegs_t), allocatable :: freegs
        type(chease_t), allocatable :: chease
        logical :: is_cloned, build_success, exists

        write(output_unit, '(A)') "Setting up VMEC implementations..."

        ! Allocate space for implementations
        allocate(this%implementations(16))
        this%n_implementations = 0

        ! Educational VMEC
        if (this%repo_manager%is_cloned("educational_VMEC")) then
            repo_path = this%repo_manager%get_repo_path("educational_VMEC")

            allocate(edu_vmec)
            call edu_vmec%initialize("Educational_VMEC", repo_path)

            ! Check if already built, if so skip build step
            if (edu_vmec%is_available()) then
                this%n_implementations = this%n_implementations + 1
                this%implementations(this%n_implementations)%key = "educational_vmec"
                call move_alloc(edu_vmec, this%implementations(this%n_implementations)%impl)
                write(output_unit, '(A)') "✓ Educational VMEC is ready (already built)"
            else if (edu_vmec%build()) then
                this%n_implementations = this%n_implementations + 1
                this%implementations(this%n_implementations)%key = "educational_vmec"
                call move_alloc(edu_vmec, this%implementations(this%n_implementations)%impl)
                write(output_unit, '(A)') "✓ Educational VMEC is ready"
            else
                write(error_unit, '(A)') "✗ Educational VMEC setup failed"
                deallocate(edu_vmec)
            end if
        end if

        ! jVMEC (check for directory presence)
        repo_path = trim(this%repo_manager%base_path) // "/jVMEC"
        inquire(file=trim(repo_path), exist=exists)
        if (exists) then
            allocate(jvmec)
            call jvmec%initialize("jVMEC", repo_path)

            ! Check if already built, if so skip build step
            if (jvmec%is_available()) then
                this%n_implementations = this%n_implementations + 1
                this%implementations(this%n_implementations)%key = "jvmec"
                call move_alloc(jvmec, this%implementations(this%n_implementations)%impl)
                write(output_unit, '(A)') "✓ jVMEC is ready (already built)"
            else if (jvmec%build()) then
                this%n_implementations = this%n_implementations + 1
                this%implementations(this%n_implementations)%key = "jvmec"
                call move_alloc(jvmec, this%implementations(this%n_implementations)%impl)
                write(output_unit, '(A)') "✓ jVMEC is ready"
            else
                write(error_unit, '(A)') "✗ jVMEC setup failed"
                deallocate(jvmec)
            end if
        end if

        ! VMEC2000
        if (this%repo_manager%is_cloned("VMEC2000")) then
            repo_path = this%repo_manager%get_repo_path("VMEC2000")

            allocate(vmec2000)
            call vmec2000%initialize("VMEC2000", repo_path)

            ! Check if already built, if so skip build step
            if (vmec2000%is_available()) then
                this%n_implementations = this%n_implementations + 1
                this%implementations(this%n_implementations)%key = "vmec2000"
                call move_alloc(vmec2000, this%implementations(this%n_implementations)%impl)
                write(output_unit, '(A)') "✓ VMEC2000 is ready (already built)"
            else if (vmec2000%build()) then
                this%n_implementations = this%n_implementations + 1
                this%implementations(this%n_implementations)%key = "vmec2000"
                call move_alloc(vmec2000, this%implementations(this%n_implementations)%impl)
                write(output_unit, '(A)') "✓ VMEC2000 is ready"
            else
                write(error_unit, '(A)') "✗ VMEC2000 setup failed"
                deallocate(vmec2000)
            end if
        end if

        ! VMEC++
        if (this%repo_manager%is_cloned("vmecpp")) then
            repo_path = this%repo_manager%get_repo_path("vmecpp")

            allocate(vmecpp)
            call vmecpp%initialize("VMEC++", repo_path)

            ! Check if already built, if so skip build step
            if (vmecpp%is_available()) then
                this%n_implementations = this%n_implementations + 1
                this%implementations(this%n_implementations)%key = "vmecpp"
                call move_alloc(vmecpp, this%implementations(this%n_implementations)%impl)
                write(output_unit, '(A)') "✓ VMEC++ is ready (already built)"
            else if (vmecpp%build()) then
                this%n_implementations = this%n_implementations + 1
                this%implementations(this%n_implementations)%key = "vmecpp"
                call move_alloc(vmecpp, this%implementations(this%n_implementations)%impl)
                write(output_unit, '(A)') "✓ VMEC++ is ready"
            else
                write(error_unit, '(A)') "✗ VMEC++ setup failed"
                deallocate(vmecpp)
            end if
        end if

        ! VMEX
        if (this%repo_manager%is_cloned("VMEX")) then
            repo_path = this%repo_manager%get_repo_path("VMEX")
            allocate(vmex)
            call vmex%initialize("VMEX", repo_path)
            if (vmex%build()) then
                this%n_implementations = this%n_implementations + 1
                this%implementations(this%n_implementations)%key = "vmex"
                call move_alloc(vmex, this%implementations(this%n_implementations)%impl)
                write(output_unit, '(A)') "✓ VMEX is ready"
            else
                write(error_unit, '(A)') "✗ VMEX setup failed"
                deallocate(vmex)
            end if
        end if

        ! DESC
        if (this%repo_manager%is_cloned("DESC")) then
            repo_path = this%repo_manager%get_repo_path("DESC")
            allocate(desc)
            call desc%initialize("DESC", repo_path)
            if (desc%build()) then
                this%n_implementations = this%n_implementations + 1
                this%implementations(this%n_implementations)%key = "desc"
                call move_alloc(desc, this%implementations(this%n_implementations)%impl)
                write(output_unit, '(A)') "✓ DESC is ready"
            else
                write(error_unit, '(A)') "✗ DESC setup failed"
                deallocate(desc)
            end if
        end if

        ! GVEC
        if (this%repo_manager%is_cloned("gvec")) then
            repo_path = this%repo_manager%get_repo_path("gvec")
            allocate(gvec)
            call gvec%initialize("GVEC", repo_path)
            if (gvec%build()) then
                this%n_implementations = this%n_implementations + 1
                this%implementations(this%n_implementations)%key = "gvec"
                call move_alloc(gvec, this%implementations(this%n_implementations)%impl)
                write(output_unit, '(A)') "✓ GVEC is ready"
            else
                write(error_unit, '(A)') "✗ GVEC setup failed"
                deallocate(gvec)
            end if
        end if

        ! PARVMEC, SPEC and SPECTRE are retained as native participants.  They
        ! only enter the run when a checkout has a usable executable; their
        ! native outputs are reported separately from VMEC WOUT quantities.
        if (this%repo_manager%is_cloned("PARVMEC")) then
            repo_path = this%repo_manager%get_repo_path("PARVMEC")
            allocate(parvmec); call parvmec%initialize("PARVMEC", repo_path)
            if (parvmec%build()) then
                this%n_implementations = this%n_implementations + 1
                this%implementations(this%n_implementations)%key = "parvmec"
                call move_alloc(parvmec, this%implementations(this%n_implementations)%impl)
                write(output_unit, '(A)') "✓ PARVMEC is ready"
            else
                deallocate(parvmec)
            end if
        end if
        if (this%repo_manager%is_cloned("SPEC")) then
            repo_path = this%repo_manager%get_repo_path("SPEC")
            allocate(spec); call spec%initialize("SPEC", repo_path)
            if (spec%build()) then
                this%n_implementations = this%n_implementations + 1
                this%implementations(this%n_implementations)%key = "spec"
                call move_alloc(spec, this%implementations(this%n_implementations)%impl)
                write(output_unit, '(A)') "✓ SPEC is ready"
            else
                deallocate(spec)
            end if
        end if
        if (this%repo_manager%is_cloned("SPECTRE")) then
            repo_path = this%repo_manager%get_repo_path("SPECTRE")
            allocate(spectre); call spectre%initialize("SPECTRE", repo_path)
            if (spectre%build()) then
                this%n_implementations = this%n_implementations + 1
                this%implementations(this%n_implementations)%key = "spectre"
                call move_alloc(spectre, this%implementations(this%n_implementations)%impl)
                write(output_unit, '(A)') "✓ SPECTRE is ready"
            else
                deallocate(spectre)
            end if
        end if
        if (this%repo_manager%is_cloned("FreeGS") .or. this%repo_manager%is_cloned("freegs")) then
            repo_path = this%repo_manager%get_repo_path("FreeGS")
            inquire(file=trim(repo_path), exist=exists)
            if (.not. exists) repo_path = this%repo_manager%get_repo_path("freegs")
            allocate(freegs); call freegs%initialize("FreeGS", repo_path)
            if (freegs%build()) then
                this%n_implementations = this%n_implementations + 1
                this%implementations(this%n_implementations)%key = "freegs"
                call move_alloc(freegs, this%implementations(this%n_implementations)%impl)
                write(output_unit, '(A)') "✓ FreeGS is ready (2-D only)"
            else
                deallocate(freegs)
            end if
        end if
        if (this%repo_manager%is_cloned("CHEASE")) then
            repo_path = this%repo_manager%get_repo_path("CHEASE")
            allocate(chease); call chease%initialize("CHEASE", repo_path)
            if (chease%build()) then
                this%n_implementations = this%n_implementations + 1
                this%implementations(this%n_implementations)%key = "chease"
                call move_alloc(chease, this%implementations(this%n_implementations)%impl)
                write(output_unit, '(A)') "✓ CHEASE is ready (2-D only)"
            else
                deallocate(chease)
            end if
        end if
    end subroutine benchmark_runner_setup_implementations

    subroutine benchmark_runner_discover_test_cases(this, limit, symmetric_only, case_match)
        class(benchmark_runner_t), intent(inout) :: this
        integer, intent(in), optional :: limit
        logical, intent(in), optional :: symmetric_only
        character(len=*), intent(in), optional :: case_match
        integer :: max_cases

        write(output_unit, '(A)') "Discovering test cases..."

        ! A zero limit means the complete discovered corpus.  Keep enough
        ! room for all bundled cases; callers can still cap this explicitly.
        max_cases = 10000
        if (present(limit)) then
            if (limit > 0) max_cases = limit
        end if

        ! Allocate space for test cases
        allocate(this%test_cases(max_cases))
        this%n_test_cases = 0

        ! Discover test cases from all available repositories
        call this%discover_from_all_repos(max_cases, symmetric_only, case_match)

        write(output_unit, '(A,I0)') "Total test cases found: ", this%n_test_cases
    end subroutine benchmark_runner_discover_test_cases

    subroutine discover_from_all_repos(this, max_cases, symmetric_only, case_match)
        class(benchmark_runner_t), intent(inout) :: this
        integer, intent(in) :: max_cases
        logical, intent(in), optional :: symmetric_only
        character(len=*), intent(in), optional :: case_match
        character(len=:), allocatable :: cmd, search_roots, repo_path, temp_file
        character(len=:), allocatable :: parameter_temp_file
        character(len=256) :: line, env_value
        integer :: stat, unit, env_stat
        logical :: include_jvmec, filter_symmetric, exists, filter_match

        ! Check if jVMEC tests should be included
        call get_environment_variable("BENCHMARK_INCLUDE_JVMEC", env_value, status=env_stat)
        include_jvmec = (env_stat == 0 .and. trim(env_value) == "1")

        ! Check if symmetric-only filtering is requested
        filter_symmetric = .false.
        if (present(symmetric_only)) filter_symmetric = symmetric_only

        filter_match = present(case_match)
        if (filter_match) then
            filter_match = len_trim(case_match) > 0 .and. trim(case_match) /= '""'
        end if

        search_roots = ""

        ! The benchmark-owned corpus is always discoverable, even when no
        ! external checkout is installed.  Its path taxonomy encodes the
        ! analytical/numerical and 1-D/2-D/3-D matrix.
        repo_path = trim(this%repo_manager%base_path) // "/benchmark_vmec/cases"
        search_roots = trim(repo_path)

        if (this%repo_manager%is_cloned("educational_VMEC")) then
            repo_path = this%repo_manager%get_repo_path("educational_VMEC")
            call append_search_root(search_roots, repo_path)
        end if

        if (this%repo_manager%is_cloned("VMEC2000")) then
            repo_path = this%repo_manager%get_repo_path("VMEC2000")
            if (len_trim(search_roots) == 0) then
                search_roots = trim(repo_path)
            else
                search_roots = trim(search_roots) // " " // trim(repo_path)
            end if
        end if

        if (this%repo_manager%is_cloned("vmecpp")) then
            repo_path = this%repo_manager%get_repo_path("vmecpp")
            if (len_trim(search_roots) == 0) then
                search_roots = trim(repo_path)
            else
                search_roots = trim(search_roots) // " " // trim(repo_path)
            end if
        end if

        if (this%repo_manager%is_cloned("VMEX")) then
            repo_path = this%repo_manager%get_repo_path("VMEX")
            call append_search_root(search_roots, repo_path)
        end if

        if (this%repo_manager%is_cloned("DESC")) then
            repo_path = this%repo_manager%get_repo_path("DESC")
            call append_search_root(search_roots, repo_path)
        end if

        if (this%repo_manager%is_cloned("gvec")) then
            repo_path = this%repo_manager%get_repo_path("gvec")
            call append_search_root(search_roots, repo_path)
        end if

        if (include_jvmec) then
            repo_path = trim(this%repo_manager%base_path) // "/jVMEC"
            inquire(file=trim(repo_path), exist=exists)
            if (exists) then
                if (len_trim(search_roots) == 0) then
                    search_roots = trim(repo_path)
                else
                    search_roots = trim(search_roots) // " " // trim(repo_path)
                end if
            end if
            write(output_unit, '(A)') "  (Including jVMEC test cases)"
        else
            write(output_unit, '(A)') "  (Excluding jVMEC test cases - set BENCHMARK_INCLUDE_JVMEC=1 to include)"
        end if

        if (len_trim(search_roots) == 0) then
            write(output_unit, '(A)') "  No repository directories available for test discovery"
            return
        end if

        temp_file = "/tmp/benchmark_vmec_test_files.tmp"
        cmd = "find " // trim(search_roots) // " -follow -name 'input.*' -type f 2>/dev/null | " // &
            "grep -E '/(tests?|examples?|cases)/' | grep -v results | grep -v debug | grep -v bazel"
        call execute_command_line(trim(cmd) // " > " // trim(temp_file), exitstat=stat)

        if (stat == 0) then
            open(newunit=unit, file=trim(temp_file), status="old", action="read", iostat=stat)
            if (stat == 0) then
                do
                    read(unit, '(A)', iostat=stat) line
                    if (stat /= 0) exit

                    ! Skip non-symmetric cases if symmetric_only filter is active
                    if (filter_symmetric .and. .not. this%is_symmetric_case(trim(line))) then
                        write(output_unit, '(A)') "  Skipping asymmetric case: " // trim(line)
                        cycle
                    end if

                    if (filter_match) then
                        if (index(trim(line), trim(case_match)) == 0) cycle
                    end if

                    if (.not. this%is_duplicate_case(trim(line)) .and. &
                        this%n_test_cases < max_cases) then
                        this%n_test_cases = this%n_test_cases + 1
                        this%test_cases(this%n_test_cases)%str = trim(line)
                        write(output_unit, '(A)') "  Found: " // trim(line)
                    end if
                end do
                close(unit)
            end if
        end if

        ! GVEC's native cases are parameter files rather than VMEC INDATA
        ! files.  Keep them in the same case inventory so the adapter can run
        ! them without pretending that every code consumes the same syntax.
        parameter_temp_file = "/tmp/benchmark_vmec_parameter_files.tmp"
        cmd = "find " // trim(search_roots) // &
            " -follow -type f \( -name 'parameter.ini' -o -name 'parameter.toml' -o -name 'parameter.yaml' \) " // &
            "2>/dev/null | grep -v results"
        call execute_command_line(trim(cmd) // " > " // trim(parameter_temp_file), exitstat=stat)
        if (stat == 0) then
            open(newunit=unit, file=trim(parameter_temp_file), status="old", action="read", iostat=stat)
            if (stat == 0) then
                do
                    read(unit, '(A)', iostat=stat) line
                    if (stat /= 0) exit
                    if (filter_match) then
                        if (index(trim(line), trim(case_match)) == 0) cycle
                    end if
                    if (.not. this%is_duplicate_case(trim(line)) .and. &
                        this%n_test_cases < max_cases) then
                        this%n_test_cases = this%n_test_cases + 1
                        this%test_cases(this%n_test_cases)%str = trim(line)
                        write(output_unit, '(A)') "  Found: " // trim(line)
                    end if
                end do
                close(unit)
            end if
        end if

        call execute_command_line("rm -f " // trim(temp_file))
        call execute_command_line("rm -f " // trim(parameter_temp_file))

        ! SPEC/SPECTRE use native .sp files rather than VMEC INDATA. Keep a
        ! small native inventory when those repositories are provisioned.
        parameter_temp_file = "/tmp/benchmark_vmec_native_files.tmp"
        cmd = "find " // trim(search_roots) // " -follow -type f -name '*.sp' " // &
            "2>/dev/null | grep -E '/(ci|examples?|tests?)/' | grep -v results"
        call execute_command_line(trim(cmd) // " > " // trim(parameter_temp_file), exitstat=stat)
        if (stat == 0) then
            open(newunit=unit, file=trim(parameter_temp_file), status="old", action="read", iostat=stat)
            if (stat == 0) then
                do
                    read(unit, '(A)', iostat=stat) line
                    if (stat /= 0) exit
                    if (filter_match .and. index(trim(line), trim(case_match)) == 0) cycle
                    if (.not. this%is_duplicate_case(trim(line)) .and. this%n_test_cases < max_cases) then
                        this%n_test_cases = this%n_test_cases + 1
                        this%test_cases(this%n_test_cases)%str = trim(line)
                        write(output_unit, '(A)') "  Found native: " // trim(line)
                    end if
                end do
                close(unit)
            end if
        end if
        call execute_command_line("rm -f " // trim(parameter_temp_file))
    end subroutine discover_from_all_repos

    function benchmark_runner_run_single_case(this, test_case_idx, impl_idx, timeout) result(results)
        class(benchmark_runner_t), intent(inout) :: this
        integer, intent(in) :: test_case_idx
        integer, intent(in) :: impl_idx
        integer, intent(in), optional :: timeout
        type(vmec_result_t) :: results
        character(len=:), allocatable :: case_name, case_slug, output_dir
        logical :: success

        call results%clear()

        if (test_case_idx < 1 .or. test_case_idx > this%n_test_cases) then
            results%error_message = "Invalid test case index"
            return
        end if

        if (impl_idx < 1 .or. impl_idx > this%n_implementations) then
            results%error_message = "Invalid implementation index"
            return
        end if

        case_name = get_case_name(this%test_cases(test_case_idx)%str)
        case_slug = get_case_slug(this%test_cases(test_case_idx)%str)
        output_dir = trim(this%output_dir) // "/" // trim(case_slug) // "/" // &
            trim(this%implementations(impl_idx)%key)

        write(output_unit, '(A)') "Running " // trim(case_name) // " on " // &
            trim(this%implementations(impl_idx)%key)

        ! Run the case
        success = this%implementations(impl_idx)%impl%run_case( &
            this%test_cases(test_case_idx)%str, output_dir, timeout)

        if (success) then
            ! Extract results
            call this%implementations(impl_idx)%impl%extract_results(output_dir, results)
            if (results%success) then
                results%dimension = case_dimension(this%test_cases(test_case_idx)%str)
                if (.not. allocated(results%family)) results%family = 'vmec_family'
                if (.not. allocated(results%input_format)) results%input_format = 'vmec_indata'
                if (.not. allocated(results%output_format)) results%output_format = 'wout_netcdf'
                write(output_unit, '(A)') "  ✓ " // trim(this%implementations(impl_idx)%key) // " completed"
            else
                if (.not. allocated(results%error_message)) results%error_message = "Result extraction failed"
                write(output_unit, '(A)') "  ✗ " // trim(this%implementations(impl_idx)%key) // &
                    " produced no comparable result: " // trim(results%error_message)
            end if
        else
            results%error_message = "Run failed"
            write(output_unit, '(A)') "  ✗ " // trim(this%implementations(impl_idx)%key) // " failed"
        end if
    end function benchmark_runner_run_single_case

    subroutine benchmark_runner_run_all_cases(this, comparator, timeout)
        class(benchmark_runner_t), intent(inout) :: this
        class(results_comparator_t), intent(inout) :: comparator
        integer, intent(in), optional :: timeout
        type(vmec_result_t) :: results
        character(len=:), allocatable :: case_name
        integer :: i, j

        do i = 1, this%n_test_cases
            case_name = get_case_name(this%test_cases(i)%str)
            write(output_unit, '(/,A)') "Running test case: " // trim(case_name)

            do j = 1, this%n_implementations
                if (trim(this%implementations(j)%key) == 'freegs' .and. &
                    .not. freegs_case_supported(this%test_cases(i)%str)) then
                    call results%clear()
                    results%error_message = 'Unsupported: FreeGS is restricted to 2-D Grad-Shafranov cases'
                    write(output_unit, '(A)') '  - freegs skipped (not a 2-D Grad-Shafranov case)'
                else if (trim(this%implementations(j)%key) == 'chease' .and. &
                        .not. chease_case_supported(this%test_cases(i)%str)) then
                    call results%clear()
                    results%error_message = 'Unsupported: CHEASE requires a 2-D GEQDSK input'
                    write(output_unit, '(A)') '  - chease skipped (not a 2-D GEQDSK case)'
                else if (trim(this%implementations(j)%key) == 'spec' .and. &
                        .not. spec_case_supported(this%test_cases(i)%str)) then
                    call results%clear()
                    results%error_message = 'Unsupported: SPEC requires a native .sp input'
                    write(output_unit, '(A)') '  - spec skipped (VMEC input is not a SPEC namelist)'
                else if (trim(this%implementations(j)%key) == 'spectre' .and. &
                        .not. spectre_case_supported(this%test_cases(i)%str)) then
                    call results%clear()
                    results%error_message = 'Unsupported: SPECTRE requires VMEC input or native TOML'
                    write(output_unit, '(A)') '  - spectre skipped (input format is not supported)'
                else if (spec_case_supported(this%test_cases(i)%str) .and. &
                        trim(this%implementations(j)%key) /= 'spec') then
                    call results%clear()
                    results%error_message = 'Unsupported: native SPEC cases are not VMEC inputs'
                    write(output_unit, '(A)') '  - ' // trim(this%implementations(j)%key) // &
                        ' skipped (native SPEC case)'
                else if (native_spectre_case(this%test_cases(i)%str) .and. &
                        trim(this%implementations(j)%key) /= 'spectre') then
                    call results%clear()
                    results%error_message = 'Unsupported: native SPECTRE cases are not VMEC inputs'
                    write(output_unit, '(A)') '  - ' // trim(this%implementations(j)%key) // &
                        ' skipped (native SPECTRE case)'
                else
                    results = this%run_single_case(i, j, timeout)
                end if

                ! Add results to comparator
                call comparator%add_result(case_name, &
                    this%implementations(j)%key, &
                    results)
            end do
        end do

        write(output_unit, '(/,A)') "Benchmark run complete!"
    end subroutine benchmark_runner_run_all_cases

    function benchmark_runner_get_implementation_names(this) result(names)
        class(benchmark_runner_t), intent(in) :: this
        character(len=32), allocatable :: names(:)
        integer :: i

        allocate(names(this%n_implementations))
        do i = 1, this%n_implementations
            names(i) = this%implementations(i)%key
        end do
    end function benchmark_runner_get_implementation_names

    function benchmark_runner_get_test_case_names(this) result(names)
        class(benchmark_runner_t), intent(in) :: this
        character(len=256), allocatable :: names(:)
        integer :: i

        allocate(names(this%n_test_cases))
        do i = 1, this%n_test_cases
            names(i) = get_case_name(this%test_cases(i)%str)
        end do
    end function benchmark_runner_get_test_case_names

    subroutine benchmark_runner_finalize(this)
        class(benchmark_runner_t), intent(inout) :: this
        integer :: i

        if (allocated(this%output_dir)) deallocate(this%output_dir)

        if (allocated(this%implementations)) then
            do i = 1, this%n_implementations
                if (allocated(this%implementations(i)%key)) &
                    deallocate(this%implementations(i)%key)
                if (allocated(this%implementations(i)%impl)) &
                    deallocate(this%implementations(i)%impl)
            end do
            deallocate(this%implementations)
        end if

        if (allocated(this%test_cases)) deallocate(this%test_cases)

        this%n_implementations = 0
        this%n_test_cases = 0
    end subroutine benchmark_runner_finalize

    function benchmark_runner_is_duplicate_json(this, json_file) result(is_duplicate)
        class(benchmark_runner_t), intent(in) :: this
        character(len=*), intent(in) :: json_file
        logical :: is_duplicate
        character(len=:), allocatable :: base_file
        integer :: i, json_pos

        is_duplicate = .false.

        ! Get the base filename without .json extension
        json_pos = index(json_file, '.json', back=.true.)
        if (json_pos > 0) then
            base_file = json_file(1:json_pos-1)

            ! Check if we already have this test case without .json
            do i = 1, this%n_test_cases
                if (trim(this%test_cases(i)%str) == trim(base_file)) then
                    is_duplicate = .true.
                    return
                end if
            end do
        end if
    end function benchmark_runner_is_duplicate_json

    function benchmark_runner_is_duplicate_case(this, filepath) result(is_duplicate)
        class(benchmark_runner_t), intent(in) :: this
        character(len=*), intent(in) :: filepath
        logical :: is_duplicate
        integer :: i
        character(len=:), allocatable :: candidate_name

        is_duplicate = .false.
        candidate_name = get_case_name(filepath)
        do i = 1, this%n_test_cases
            if (trim(get_case_name(this%test_cases(i)%str)) == trim(candidate_name)) then
                is_duplicate = .true.
                return
            end if
        end do
    end function benchmark_runner_is_duplicate_case

    subroutine append_search_root(roots, root)
        character(len=:), allocatable, intent(inout) :: roots
        character(len=*), intent(in) :: root

        if (len_trim(roots) == 0) then
            roots = trim(root)
        else
            roots = trim(roots) // " " // trim(root)
        end if
    end subroutine append_search_root

    function benchmark_runner_is_free_boundary(this, filepath) result(is_free)
        class(benchmark_runner_t), intent(in) :: this
        character(len=*), intent(in) :: filepath
        logical :: is_free
        character(len=256) :: line
        integer :: unit, stat
        logical :: file_exists

        is_free = .false.

        ! Check if file exists
        inquire(file=filepath, exist=file_exists)
        if (.not. file_exists) return

        ! Check VMEC input files for LFREEB = T
        open(newunit=unit, file=filepath, status='old', action='read', iostat=stat)
        if (stat == 0) then
            do
                read(unit, '(A)', iostat=stat) line
                if (stat /= 0) exit
                ! Convert to uppercase for comparison
                call to_upper(line)
                ! Check for LFREEB = T
                if (index(line, 'LFREEB') > 0 .and. &
                    (index(line, '= T') > 0 .or. index(line, '=T') > 0)) then
                    is_free = .true.
                    exit
                end if
            end do
            close(unit)
        end if
    end function benchmark_runner_is_free_boundary

    function benchmark_runner_is_symmetric_case(this, filepath) result(is_symmetric)
        class(benchmark_runner_t), intent(in) :: this
        character(len=*), intent(in) :: filepath
        logical :: is_symmetric
        character(len=256) :: line
        integer :: unit, stat
        logical :: file_exists

        is_symmetric = .true. ! Default to symmetric (LASYM = F is default)

        ! Check if file exists
        inquire(file=filepath, exist=file_exists)
        if (.not. file_exists) return

        ! Check VMEC input files for LASYM = T
        open(newunit=unit, file=filepath, status='old', action='read', iostat=stat)
        if (stat == 0) then
            do
                read(unit, '(A)', iostat=stat) line
                if (stat /= 0) exit
                ! Convert to uppercase for comparison
                call to_upper(line)
                ! Check for LASYM = T (only mark as asymmetric if explicitly set to T)
                if (index(line, 'LASYM') > 0) then
                    if (index(line, '= T') > 0 .or. index(line, '=T') > 0) then
                        is_symmetric = .false.
                    end if
                    exit
                end if
            end do
            close(unit)
        end if
    end function benchmark_runner_is_symmetric_case

    ! Utility function
    function get_case_name(filepath) result(name)
        character(len=*), intent(in) :: filepath
        character(len=:), allocatable :: name
        character(len=:), allocatable :: repo_name, relative_path
        character(len=:), allocatable :: directory_name, basename
        integer :: last_slash, last_dot

        call split_case_path(filepath, repo_name, relative_path)

        last_slash = index(relative_path, '/', back=.true.)
        if (last_slash > 0) then
            directory_name = relative_path(1:last_slash-1)
            basename = relative_path(last_slash+1:)
        else
            directory_name = ""
            basename = relative_path
        end if

        if (index(basename, "input.") == 1) then
            basename = basename(7:)
        else
            last_dot = index(basename, '.', back=.true.)
            if (last_dot > 0) then
                basename = basename(1:last_dot-1)
            end if
        end if

        last_dot = index(basename, '.', back=.true.)
        if (last_dot > 0) then
            select case (basename(last_dot:))
            case (".json", ".vmec", ".txt", ".namelist")
                basename = basename(1:last_dot-1)
            case (".sp", ".toml", ".ini", ".yaml", ".geqdsk")
                basename = basename(1:last_dot-1)
            end select
        end if

        if (len_trim(repo_name) > 0) then
            if (len_trim(directory_name) > 0) then
                name = trim(repo_name) // "/" // trim(directory_name) // "/" // trim(basename)
            else
                name = trim(repo_name) // "/" // trim(basename)
            end if
        else if (len_trim(directory_name) > 0) then
            name = trim(directory_name) // "/" // trim(basename)
        else
            name = trim(basename)
        end if
    end function get_case_name

    function get_case_slug(filepath) result(slug)
        character(len=*), intent(in) :: filepath
        character(len=:), allocatable :: slug
        character(len=:), allocatable :: case_name
        integer :: i
        character(len=1) :: ch

        case_name = get_case_name(filepath)
        slug = ""
        do i = 1, len_trim(case_name)
            ch = case_name(i:i)
            select case (ch)
            case ('A':'Z', 'a':'z', '0':'9', '-', '_', '.')
                slug = slug // ch
            case ('/')
                slug = slug // "__"
            case default
                slug = slug // "_"
            end select
        end do
    end function get_case_slug

    integer function case_dimension(filepath) result(dimension)
        character(len=*), intent(in) :: filepath
        character(len=:), allocatable :: lowered

        lowered = filepath
        call to_lower(lowered)
        dimension = 3
        if (index(lowered, '/1d') > 0) then
            dimension = 1
        else if (index(lowered, '/2d') > 0) then
            dimension = 2
        else if (index(lowered, '/3d') > 0) then
            dimension = 3
        end if
    end function case_dimension

    logical function freegs_case_supported(filepath)
        character(len=*), intent(in) :: filepath
        character(len=:), allocatable :: lowered

        lowered = filepath
        call to_lower(lowered)
        freegs_case_supported = index(lowered, '/2d') > 0
    end function freegs_case_supported

    logical function chease_case_supported(filepath)
        character(len=*), intent(in) :: filepath
        character(len=:), allocatable :: lowered

        lowered = filepath
        call to_lower(lowered)
        ! CHEASE's supported interchange is EQDSK; a VMEC INDATA file is not
        ! a valid CHEASE input even when it comes from a 2-D directory.
        chease_case_supported = index(lowered, '/2d') > 0 .and. &
            (path_has_suffix(lowered, '.geqdsk') .or. path_has_suffix(lowered, '.eqdsk'))
    end function chease_case_supported

    logical function spec_case_supported(filepath)
        character(len=*), intent(in) :: filepath
        character(len=:), allocatable :: lowered

        lowered = filepath
        call to_lower(lowered)
        spec_case_supported = path_has_suffix(lowered, '.sp')
    end function spec_case_supported

    logical function spectre_case_supported(filepath)
        character(len=*), intent(in) :: filepath
        character(len=:), allocatable :: lowered

        lowered = filepath
        call to_lower(lowered)
        ! Native SPECTRE inputs are TOML files.  VMEC INDATA files are also
        ! accepted because the external adapter converts them before launch.
        spectre_case_supported = path_has_suffix(lowered, '.toml') .or. &
            index(lowered, '/input.') > 0
    end function spectre_case_supported

    logical function native_spectre_case(filepath)
        character(len=*), intent(in) :: filepath
        character(len=:), allocatable :: lowered

        lowered = filepath
        call to_lower(lowered)
        native_spectre_case = path_has_suffix(lowered, '.toml') .and. &
            index(lowered, '/spectre/') > 0
    end function native_spectre_case

    logical function path_has_suffix(path, suffix)
        character(len=*), intent(in) :: path, suffix
        integer :: start

        path_has_suffix = .false.
        if (len_trim(path) < len_trim(suffix)) return
        start = len_trim(path) - len_trim(suffix) + 1
        path_has_suffix = path(start:) == trim(suffix)
    end function path_has_suffix

    subroutine split_case_path(filepath, repo_name, relative_path)
        character(len=*), intent(in) :: filepath
        character(len=:), allocatable, intent(out) :: repo_name, relative_path

        call extract_repo_relative_path(filepath, repo_name, relative_path)
        call trim_case_root(relative_path)
    end subroutine split_case_path

    subroutine extract_repo_relative_path(filepath, repo_name, relative_path)
        character(len=*), intent(in) :: filepath
        character(len=:), allocatable, intent(out) :: repo_name, relative_path
        integer :: marker_pos

        repo_name = ""
        relative_path = trim(filepath)

        marker_pos = index(filepath, "/educational_VMEC/")
        if (marker_pos > 0) then
            repo_name = "educational_VMEC"
            relative_path = filepath(marker_pos + len("/educational_VMEC/"):)
            return
        end if

        marker_pos = index(filepath, "/VMEC2000/")
        if (marker_pos > 0) then
            repo_name = "VMEC2000"
            relative_path = filepath(marker_pos + len("/VMEC2000/"):)
            return
        end if

        marker_pos = index(filepath, "/vmecpp/")
        if (marker_pos > 0) then
            repo_name = "vmecpp"
            relative_path = filepath(marker_pos + len("/vmecpp/"):)
            return
        end if

        marker_pos = index(filepath, "/VMEX/")
        if (marker_pos > 0) then
            repo_name = "VMEX"
            relative_path = filepath(marker_pos + len("/VMEX/"):)
            return
        end if

        marker_pos = index(filepath, "/DESC/")
        if (marker_pos > 0) then
            repo_name = "DESC"
            relative_path = filepath(marker_pos + len("/DESC/"):)
            return
        end if

        marker_pos = index(filepath, "/gvec/")
        if (marker_pos > 0) then
            repo_name = "gvec"
            relative_path = filepath(marker_pos + len("/gvec/"):)
            return
        end if

        marker_pos = index(filepath, "/jVMEC/")
        if (marker_pos > 0) then
            repo_name = "jVMEC"
            relative_path = filepath(marker_pos + len("/jVMEC/"):)
            return
        end if

        marker_pos = index(filepath, "/PARVMEC/")
        if (marker_pos > 0) then
            repo_name = "PARVMEC"
            relative_path = filepath(marker_pos + len("/PARVMEC/"):)
            return
        end if
        marker_pos = index(filepath, "/SPEC/")
        if (marker_pos > 0) then
            repo_name = "SPEC"
            relative_path = filepath(marker_pos + len("/SPEC/"):)
            return
        end if
        marker_pos = index(filepath, "/SPECTRE/")
        if (marker_pos > 0) then
            repo_name = "SPECTRE"
            relative_path = filepath(marker_pos + len("/SPECTRE/"):)
            return
        end if

        marker_pos = index(filepath, "/benchmark_vmec/cases/")
        if (marker_pos > 0) then
            repo_name = "benchmark_vmec"
            relative_path = filepath(marker_pos + len("/benchmark_vmec/"):)
        end if
    end subroutine extract_repo_relative_path

    subroutine trim_case_root(relative_path)
        character(len=:), allocatable, intent(inout) :: relative_path

        call remove_prefix(relative_path, "src/test/resources/")
        call remove_prefix(relative_path, "tests/")
        call remove_prefix(relative_path, "test/")
        call remove_prefix(relative_path, "examples/")
        call remove_prefix(relative_path, "example/")
        call remove_prefix(relative_path, "test-CI/examples/")
    end subroutine trim_case_root

    subroutine remove_prefix(text, prefix)
        character(len=:), allocatable, intent(inout) :: text
        character(len=*), intent(in) :: prefix

        if (index(text, prefix) == 1) then
            text = text(len_trim(prefix)+1:)
        end if
    end subroutine remove_prefix

    ! Convert string to uppercase
    subroutine to_upper(str)
        character(len=*), intent(inout) :: str
        integer :: i

        do i = 1, len_trim(str)
            if (str(i:i) >= 'a' .and. str(i:i) <= 'z') then
                str(i:i) = char(ichar(str(i:i)) - 32)
            end if
        end do
    end subroutine to_upper

    subroutine to_lower(str)
        character(len=*), intent(inout) :: str
        integer :: i

        do i = 1, len_trim(str)
            if (str(i:i) >= 'A' .and. str(i:i) <= 'Z') then
                str(i:i) = char(ichar(str(i:i)) + 32)
            end if
        end do
    end subroutine to_lower

end module benchmark_runner
