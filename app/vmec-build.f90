program vmec_build
    use iso_fortran_env, only: error_unit, output_unit
    use M_CLI2, only: set_args, lget, sget
    use repository_manager, only: repository_manager_t
    use educational_vmec_implementation, only: educational_vmec_t
    use jvmec_implementation, only: jvmec_t
    implicit none
    
    character(len=:), allocatable :: help_text(:), version_text(:)
    character(len=:), allocatable :: base_dir
    logical :: help, version, force, verbose
    type(repository_manager_t) :: repo_manager
    integer :: exit_code
    
    ! Initialize CLI
    help_text = [character(len=80) :: &
        'NAME                                                                    ', &
        '   vmec-build - Build VMEC implementations                             ', &
        '                                                                        ']
    version_text = [character(len=80) :: &
        'vmec-build version 1.0.0                                               ']
    
    call set_args('--base-dir "./vmec_repos" --force F --verbose F --help F --version F', &
                  help_text, version_text)
    
    ! Get command line arguments
    help = lget('help')
    version = lget('version')
    base_dir = sget('base-dir')
    force = lget('force')
    verbose = lget('verbose')
    
    if (help) then
        write(output_unit, '(A)') help_text
        write(output_unit, '(A)') ''
        write(output_unit, '(A)') 'SYNOPSIS'
        write(output_unit, '(A)') '   vmec-build [OPTIONS]'
        write(output_unit, '(A)') ''
        write(output_unit, '(A)') 'OPTIONS'
        write(output_unit, '(A)') '   --base-dir DIR      Base directory for repositories (default: ./vmec_repos)'
        write(output_unit, '(A)') '   --force             Force rebuild even if already built'
        write(output_unit, '(A)') '   --verbose           Enable verbose output'
        write(output_unit, '(A)') '   --help              Show this help message'
        write(output_unit, '(A)') '   --version           Show version information'
        write(output_unit, '(A)') ''
        write(output_unit, '(A)') 'DESCRIPTION'
        write(output_unit, '(A)') '   Build all available VMEC implementations in the specified directory.'
        write(output_unit, '(A)') '   This includes Educational VMEC, jVMEC, VMEC2000, and VMEC++.'
        write(output_unit, '(A)') ''
        write(output_unit, '(A)') 'EXAMPLES'
        write(output_unit, '(A)') '   vmec-build'
        write(output_unit, '(A)') '   vmec-build --base-dir /path/to/repos --force'
        stop
    end if
    
    if (version) then
        write(output_unit, '(A)') version_text
        stop
    end if
    
    exit_code = 0
    
    ! Initialize repository manager
    call repo_manager%initialize(base_dir)
    
    ! Build all available implementations
    call build_all_implementations(repo_manager, force, verbose, exit_code)
    
    ! Cleanup
    call repo_manager%finalize()
    
    if (exit_code /= 0) then
        write(error_unit, '(A)') "Some builds failed!"
        stop exit_code
    else
        write(output_unit, '(A)') "All available implementations built successfully"
    end if

contains

    subroutine build_all_implementations(repo_manager, force, verbose, exit_code)
        type(repository_manager_t), intent(in) :: repo_manager
        logical, intent(in) :: force, verbose
        integer, intent(inout) :: exit_code
        character(len=:), allocatable :: repo_path
        type(educational_vmec_t), allocatable :: edu_vmec
        type(jvmec_t), allocatable :: jvmec
        logical :: exists, success
        integer :: n_built, n_total
        
        n_built = 0
        n_total = 0
        
        write(output_unit, '(A)') "Building VMEC implementations..."
        write(output_unit, '(A)') ""
        
        ! Educational VMEC
        if (repo_manager%is_cloned("educational_VMEC")) then
            n_total = n_total + 1
            repo_path = repo_manager%get_repo_path("educational_VMEC")
            
            if (verbose) write(output_unit, '(A)') "Found Educational VMEC at: " // repo_path
            
            allocate(edu_vmec)
            call edu_vmec%initialize("Educational_VMEC", repo_path)
            
            write(output_unit, '(A)', advance='no') "Building Educational VMEC... "
            if (edu_vmec%build()) then
                write(output_unit, '(A)') "✓ SUCCESS"
                n_built = n_built + 1
            else
                write(output_unit, '(A)') "✗ FAILED"
                exit_code = 1
            end if
            deallocate(edu_vmec)
        else
            if (verbose) write(output_unit, '(A)') "Educational VMEC not found"
        end if
        
        ! jVMEC (check for directory presence)
        repo_path = trim(repo_manager%base_path) // "/jvmec"
        inquire(file=trim(repo_path), exist=exists)
        if (exists) then
            n_total = n_total + 1
            
            if (verbose) write(output_unit, '(A)') "Found jVMEC at: " // repo_path
            
            allocate(jvmec)
            call jvmec%initialize("jVMEC", repo_path)
            
            write(output_unit, '(A)', advance='no') "Building jVMEC... "
            if (jvmec%build()) then
                write(output_unit, '(A)') "✓ SUCCESS"
                n_built = n_built + 1
            else
                write(output_unit, '(A)') "✗ FAILED"
                exit_code = 1
            end if
            deallocate(jvmec)
        else
            if (verbose) write(output_unit, '(A)') "jVMEC not found"
        end if
        
        ! TODO: Add VMEC2000 and VMEC++ builds
        
        write(output_unit, '(A)') ""
        write(output_unit, '(A,I0,A,I0,A)') "Built ", n_built, " out of ", n_total, " implementations"
        
    end subroutine build_all_implementations

end program vmec_build