program vmec_benchmark
    use iso_fortran_env, only: int32, real64, error_unit, output_unit
    use M_CLI2, only: set_args, sget, lget, iget, unnamed, specified
    use repository_manager, only: repository_manager_t
    use benchmark_runner, only: benchmark_runner_t
    use results_comparator, only: results_comparator_t
    implicit none

    character(len=:), allocatable :: help_text(:)
    character(len=:), allocatable :: version_text(:)
    character(len=256) :: base_dir, output_dir
    logical :: force_clone, show_version, show_help, symmetric_only
    integer :: timeout, limit, i
    character(len=32) :: command
    
    ! Set up help text
    help_text = [character(len=80) :: &
        'NAME                                                                    ', &
        '   vmec-benchmark - Compare different VMEC implementations             ', &
        '                                                                        ', &
        'SYNOPSIS                                                                ', &
        '   vmec-benchmark [COMMAND] [OPTIONS]                                   ', &
        '                                                                        ', &
        'COMMANDS                                                                ', &
        '   setup       Clone and setup VMEC repositories                       ', &
        '   run         Run benchmarks on VMEC implementations                  ', &
        '   update      Update all cloned repositories                          ', &
        '   hard-reset  Force delete and reclone all repositories               ', &
        '   list-repos  List available repositories and their status            ', &
        '   list-cases  List available test cases                               ', &
        '                                                                        ', &
        'OPTIONS                                                                 ', &
        '   --base-dir DIR      Base directory for repositories (default: ./vmec_repos)', &
        '   --output-dir DIR    Output directory for results (default: ./benchmark_results)', &
        '   --force             Force reclone repositories                      ', &
        '   --timeout SECONDS   Timeout per case in seconds (default: 300)     ', &
        '   --limit N           Limit number of test cases                      ', &
        '   --symmetric-only    Only run symmetric cases (lasym=F)              ', &
        '   --version           Show version information                        ', &
        '   --help              Show this help message                          ', &
        '                                                                        ', &
        'EXAMPLES                                                                ', &
        '   vmec-benchmark setup                                                 ', &
        '   vmec-benchmark run --limit 5                                         ', &
        '   vmec-benchmark run --symmetric-only                                  ', &
        '   vmec-benchmark hard-reset                                            ', &
        '   vmec-benchmark list-cases                                            ', &
        '']

    version_text = [character(len=80) :: &
        'vmec-benchmark version 0.1.0 (Fortran)                                  ', &
        'VMEC Benchmark Suite                                                    ', &
        '']

    ! Parse command line arguments
    call set_args('--base-dir "./vmec_repos" --output-dir "./benchmark_results" &
                  &--force F --timeout 300 --limit 0 --symmetric-only F --version F --help F', &
                  help_text, version_text)
    
    base_dir = sget('base-dir')
    output_dir = sget('output-dir')
    force_clone = lget('force')
    timeout = iget('timeout')
    limit = iget('limit')
    symmetric_only = lget('symmetric-only')
    show_version = lget('version')
    show_help = lget('help')
    
    ! Get command from unnamed arguments
    if (size(unnamed) > 0) then
        command = unnamed(1)
    else
        command = ""
    end if
    
    ! Show version if requested
    if (show_version) then
        write(output_unit, '(A)') trim(version_text(1))
        stop
    end if
    
    ! Show help if requested or no command given
    if (show_help .or. len_trim(command) == 0) then
        do i = 1, size(help_text)
            write(output_unit, '(A)') trim(help_text(i))
        end do
        stop
    end if
    
    ! Execute command
    select case (trim(command))
    case ('setup')
        call cmd_setup(base_dir, force_clone)
    case ('run')
        call cmd_run(base_dir, output_dir, timeout, limit, symmetric_only)
    case ('update')
        call cmd_update(base_dir)
    case ('hard-reset')
        call cmd_hard_reset(base_dir)
    case ('list-repos')
        call cmd_list_repos(base_dir)
    case ('list-cases')
        call cmd_list_cases(base_dir)
    case default
        write(error_unit, '(A)') 'Unknown command: ' // trim(command)
        write(error_unit, '(A)') 'Run "vmec-benchmark --help" for usage information'
        stop 1
    end select

contains

    subroutine cmd_setup(base_dir, force)
        character(len=*), intent(in) :: base_dir
        logical, intent(in) :: force
        type(repository_manager_t) :: repo_manager
        
        write(output_unit, '(A)') 'Setting up repositories in ' // trim(base_dir)
        
        call repo_manager%initialize(base_dir)
        call repo_manager%clone_all(force)
        
        write(output_unit, '(/,A)') 'Repository setup complete'
        call repo_manager%finalize()
    end subroutine cmd_setup

    subroutine cmd_run(base_dir, output_dir, timeout, limit, symmetric_only)
        character(len=*), intent(in) :: base_dir
        character(len=*), intent(in) :: output_dir
        integer, intent(in) :: timeout
        integer, intent(in) :: limit
        logical, intent(in) :: symmetric_only
        type(repository_manager_t) :: repo_manager
        type(benchmark_runner_t) :: runner
        type(results_comparator_t) :: comparator
        character(len=:), allocatable :: report_file
        
        write(output_unit, '(A)') 'Starting VMEC benchmark run'
        
        ! Initialize components
        call repo_manager%initialize(base_dir)
        call runner%initialize(output_dir, repo_manager)
        
        ! Setup implementations
        call runner%setup_implementations()
        
        if (runner%n_implementations == 0) then
            write(error_unit, '(A)') 'No implementations available!'
            write(error_unit, '(A)') 'Run "vmec-benchmark setup" first to clone repositories'
            stop 1
        end if
        
        write(output_unit, '(/,A,I0,A)') 'Available implementations: ', &
            runner%n_implementations, ' found'
        
        ! Discover test cases
        call runner%discover_test_cases(limit, symmetric_only)
        
        if (runner%n_test_cases == 0) then
            write(error_unit, '(A)') 'No test cases found!'
            stop 1
        end if
        
        write(output_unit, '(A,I0,A)') 'Found ', runner%n_test_cases, ' test cases'
        
        ! Initialize comparator before running benchmarks
        call comparator%initialize(100)
        
        ! Run benchmarks
        call runner%run_all_cases(comparator, timeout)
        
        ! Generate comparison report
        report_file = trim(output_dir) // '/comparison_report.md'
        call comparator%generate_report(report_file)
        call comparator%export_to_csv(output_dir)
        
        write(output_unit, '(/,A)') '✅ Benchmark complete!'
        write(output_unit, '(A)') '📁 Results saved to: ' // trim(output_dir)
        write(output_unit, '(A)') '📖 Read the report: ' // trim(report_file)
        
        call runner%finalize()
        call comparator%finalize()
        call repo_manager%finalize()
    end subroutine cmd_run

    subroutine cmd_update(base_dir)
        character(len=*), intent(in) :: base_dir
        type(repository_manager_t) :: repo_manager
        integer :: i
        logical :: success
        
        write(output_unit, '(A)') 'Updating repositories in ' // trim(base_dir)
        
        call repo_manager%initialize(base_dir)
        
        do i = 1, repo_manager%n_repos
            call repo_manager%update_repo(i, success)
        end do
        
        write(output_unit, '(A)') 'Update complete'
        call repo_manager%finalize()
    end subroutine cmd_update

    subroutine cmd_list_repos(base_dir)
        character(len=*), intent(in) :: base_dir
        type(repository_manager_t) :: repo_manager
        integer :: i
        character(len=:), allocatable :: repo_name
        
        call repo_manager%initialize(base_dir)
        
        write(output_unit, '(A)') 'Repository status:'
        do i = 1, repo_manager%n_repos
            repo_name = extract_repo_name(repo_manager%repositories(i)%url)
            if (repo_manager%is_cloned(repo_name)) then
                write(output_unit, '(A)') '  ' // trim(repo_name) // ': ✓ Cloned'
            else
                write(output_unit, '(A)') '  ' // trim(repo_name) // ': ✗ Not cloned'
            end if
            write(output_unit, '(A)') '    Name: ' // trim(repo_manager%repositories(i)%name)
            write(output_unit, '(A)') '    URL: ' // trim(repo_manager%repositories(i)%url)
        end do
        
        call repo_manager%finalize()
    end subroutine cmd_list_repos

    subroutine cmd_list_cases(base_dir)
        character(len=*), intent(in) :: base_dir
        type(repository_manager_t) :: repo_manager
        type(benchmark_runner_t) :: runner
        character(len=64), allocatable :: case_names(:)
        integer :: i
        
        call repo_manager%initialize(base_dir)
        call runner%initialize("temp", repo_manager)
        call runner%discover_test_cases()
        
        write(output_unit, '(A)') 'Available test cases:'
        
        case_names = runner%get_test_case_names()
        do i = 1, min(10, size(case_names))
            write(output_unit, '(A)') '  - ' // trim(case_names(i))
        end do
        
        if (size(case_names) > 10) then
            write(output_unit, '(A,I0,A)') '  ... and ', size(case_names) - 10, ' more'
        end if
        
        call runner%finalize()
        call repo_manager%finalize()
    end subroutine cmd_list_cases

    subroutine cmd_hard_reset(base_dir)
        character(len=*), intent(in) :: base_dir
        character(len=:), allocatable :: cmd
        integer :: stat
        logical :: exists
        
        write(output_unit, '(A)') 'WARNING: Hard reset will delete ALL repositories and data!'
        write(output_unit, '(A)') 'This includes:'
        write(output_unit, '(A)') '  - All cloned VMEC repositories'
        write(output_unit, '(A)') '  - Any manually added implementations (like jVMEC)'
        write(output_unit, '(A)') '  - Build outputs and intermediate files'
        write(output_unit, '(A)') ''
        write(output_unit, '(A)') 'Proceeding with hard reset...'
        
        ! Check if directory exists
        inquire(file=trim(base_dir), exist=exists)
        if (exists) then
            write(output_unit, '(A)') 'Removing directory: ' // trim(base_dir)
            cmd = "rm -rf " // trim(base_dir)
            call execute_command_line(trim(cmd), exitstat=stat)
            
            if (stat /= 0) then
                write(error_unit, '(A)') 'Failed to remove directory'
                return
            end if
        else
            write(output_unit, '(A)') 'Directory does not exist: ' // trim(base_dir)
        end if
        
        write(output_unit, '(A)') 'Hard reset complete'
        write(output_unit, '(A)') 'Run "vmec-benchmark setup" to reinitialize repositories'
        
    end subroutine cmd_hard_reset

    function extract_repo_name(url) result(name)
        character(len=*), intent(in) :: url
        character(len=:), allocatable :: name
        integer :: last_slash, dot_git
        
        last_slash = index(url, '/', back=.true.)
        if (last_slash > 0) then
            name = url(last_slash+1:)
            dot_git = index(name, '.git')
            if (dot_git > 0) then
                name = name(1:dot_git-1)
            end if
        else
            name = "unknown"
        end if
    end function extract_repo_name

end program vmec_benchmark