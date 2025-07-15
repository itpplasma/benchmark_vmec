module benchmark_runner
    use iso_fortran_env, only: int32, real64, error_unit, output_unit
    use vmec_benchmark_types, only: vmec_result_t, string_t
    use vmec_implementation_base, only: vmec_implementation_t
    use educational_vmec_implementation, only: educational_vmec_t
    use jvmec_implementation, only: jvmec_t
    use vmec2000_implementation, only: vmec2000_t
    use vmecpp_implementation, only: vmecpp_t
    use repository_manager, only: repository_manager_t
    implicit none
    private

    public :: benchmark_runner_t

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
        logical :: is_cloned, build_success, exists
        
        write(output_unit, '(A)') "Setting up VMEC implementations..."
        
        ! Allocate space for implementations
        allocate(this%implementations(10))
        this%n_implementations = 0
        
        ! Educational VMEC
        if (this%repo_manager%is_cloned("educational_VMEC")) then
            repo_path = this%repo_manager%get_repo_path("educational_VMEC")
            
            allocate(edu_vmec)
            call edu_vmec%initialize("Educational_VMEC", repo_path)
            
            if (edu_vmec%build()) then
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
        repo_path = trim(this%repo_manager%base_path) // "/jvmec"
        inquire(file=trim(repo_path), exist=exists)
        if (exists) then
            allocate(jvmec)
            call jvmec%initialize("jVMEC", repo_path)
            
            if (jvmec%build()) then
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
            
            if (vmec2000%build()) then
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
            
            if (vmecpp%build()) then
                this%n_implementations = this%n_implementations + 1
                this%implementations(this%n_implementations)%key = "vmecpp"
                call move_alloc(vmecpp, this%implementations(this%n_implementations)%impl)
                write(output_unit, '(A)') "✓ VMEC++ is ready"
            else
                write(error_unit, '(A)') "✗ VMEC++ setup failed"
                deallocate(vmecpp)
            end if
        end if
    end subroutine benchmark_runner_setup_implementations

    subroutine benchmark_runner_discover_test_cases(this, limit)
        class(benchmark_runner_t), intent(inout) :: this
        integer, intent(in), optional :: limit
        character(len=:), allocatable :: test_path, cmd, file_list
        character(len=256) :: line
        integer :: stat, unit, n_found, max_cases
        logical :: exists
        
        write(output_unit, '(A)') "Discovering test cases..."
        
        max_cases = 100
        if (present(limit)) max_cases = limit
        
        ! Allocate space for test cases
        allocate(this%test_cases(max_cases))
        this%n_test_cases = 0
        
        ! Discover test cases from all available repositories
        call this%discover_from_all_repos(max_cases)
        
        write(output_unit, '(A,I0)') "Total test cases found: ", this%n_test_cases
    end subroutine benchmark_runner_discover_test_cases

    subroutine discover_from_all_repos(this, max_cases)
        class(benchmark_runner_t), intent(inout) :: this
        integer, intent(in) :: max_cases
        character(len=:), allocatable :: cmd
        character(len=256) :: line
        integer :: stat, unit
        
        ! Search for input files in all repositories
        cmd = "find " // trim(this%repo_manager%base_path) // " -name 'input.*' -type f 2>/dev/null"
        call execute_command_line(trim(cmd) // " > test_files.tmp", exitstat=stat)
        
        if (stat == 0) then
            open(newunit=unit, file="test_files.tmp", status="old", action="read", iostat=stat)
            if (stat == 0) then
                do
                    read(unit, '(A)', iostat=stat) line
                    if (stat /= 0) exit
                    if (this%n_test_cases < max_cases) then
                        this%n_test_cases = this%n_test_cases + 1
                        this%test_cases(this%n_test_cases)%str = trim(line)
                        write(output_unit, '(A)') "  Found: " // trim(line)
                    end if
                end do
                close(unit)
            end if
        end if
        
        call execute_command_line("rm -f test_files.tmp")
    end subroutine discover_from_all_repos

    function benchmark_runner_run_single_case(this, test_case_idx, impl_idx, timeout) result(results)
        class(benchmark_runner_t), intent(inout) :: this
        integer, intent(in) :: test_case_idx
        integer, intent(in) :: impl_idx
        integer, intent(in), optional :: timeout
        type(vmec_result_t) :: results
        character(len=:), allocatable :: case_name, output_dir
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
        output_dir = trim(this%output_dir) // "/" // trim(case_name) // "/" // &
                    trim(this%implementations(impl_idx)%key)
        
        write(output_unit, '(A)') "Running " // trim(case_name) // " on " // &
                                 trim(this%implementations(impl_idx)%key)
        
        ! Run the case
        success = this%implementations(impl_idx)%impl%run_case( &
            this%test_cases(test_case_idx)%str, output_dir, timeout)
        
        if (success) then
            ! Extract results
            call this%implementations(impl_idx)%impl%extract_results(output_dir, results)
            write(output_unit, '(A)') "  ✓ " // trim(this%implementations(impl_idx)%key) // " completed"
        else
            results%error_message = "Run failed"
            write(output_unit, '(A)') "  ✗ " // trim(this%implementations(impl_idx)%key) // " failed"
        end if
    end function benchmark_runner_run_single_case

    subroutine benchmark_runner_run_all_cases(this, timeout)
        class(benchmark_runner_t), intent(inout) :: this
        integer, intent(in), optional :: timeout
        type(vmec_result_t) :: results
        integer :: i, j
        
        do i = 1, this%n_test_cases
            write(output_unit, '(/,A)') "Running test case: " // &
                                       trim(get_case_name(this%test_cases(i)%str))
            
            do j = 1, this%n_implementations
                results = this%run_single_case(i, j, timeout)
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
        character(len=64), allocatable :: names(:)
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

    ! Utility function
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
        
        ! Remove extension
        last_dot = index(name, '.', back=.true.)
        if (last_dot > 0) then
            name = name(1:last_dot-1)
        end if
        
        ! Remove "input." prefix if present
        if (index(name, "input.") == 1) then
            name = name(7:)
        end if
    end function get_case_name

end module benchmark_runner