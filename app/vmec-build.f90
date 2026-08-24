program vmec_build
    use iso_fortran_env, only: error_unit, output_unit
    use M_CLI2, only: set_args, lget, sget
    use repository_manager, only: repository_manager_t
    use educational_vmec_implementation, only: educational_vmec_t
    use jvmec_implementation, only: jvmec_t
    use external_vmec_implementation, only: vmex_t, desc_t, gvec_t, parvmec_t, spec_t, spectre_t, freegs_t, chease_t
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

    call set_args('--base-dir ".." --force F --verbose F --help F --version F', &
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
        write(output_unit, '(A)') '   --base-dir DIR      Base directory for repositories (default: ..)'
        write(output_unit, '(A)') '   --force             Force rebuild even if already built'
        write(output_unit, '(A)') '   --verbose           Enable verbose output'
        write(output_unit, '(A)') '   --help              Show this help message'
        write(output_unit, '(A)') '   --version           Show version information'
        write(output_unit, '(A)') ''
        write(output_unit, '(A)') 'DESCRIPTION'
        write(output_unit, '(A)') '   Build all available VMEC implementations in the specified directory.'
        write(output_unit, '(A)') '   This includes the VMEC family, DESC, GVEC, PARVMEC, SPEC, SPECTRE,'
        write(output_unit, '(A)') '   FreeGS, and CHEASE when available.'
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
        type(vmex_t), allocatable :: vmex
        type(desc_t), allocatable :: desc
        type(gvec_t), allocatable :: gvec
        type(parvmec_t), allocatable :: parvmec
        type(spec_t), allocatable :: spec
        type(spectre_t), allocatable :: spectre
        type(freegs_t), allocatable :: freegs
        type(chease_t), allocatable :: chease
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
        repo_path = trim(repo_manager%base_path) // "/jVMEC"
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

        ! VMEC2000
        if (repo_manager%is_cloned("VMEC2000")) then
            n_total = n_total + 1
            repo_path = repo_manager%get_repo_path("VMEC2000")

            if (verbose) write(output_unit, '(A)') "Found VMEC2000 at: " // repo_path

            ! Use VMEC2000 implementation
            block
                use vmec2000_implementation, only: vmec2000_t
                type(vmec2000_t), allocatable :: vmec2000
                allocate(vmec2000)
                call vmec2000%initialize("VMEC2000", repo_path)

                write(output_unit, '(A)', advance='no') "Building VMEC2000... "
                if (vmec2000%build()) then
                    write(output_unit, '(A)') "✓ SUCCESS"
                    n_built = n_built + 1
                else
                    write(output_unit, '(A)') "✗ FAILED"
                    exit_code = 1
                end if
                deallocate(vmec2000)
            end block
        else
            if (verbose) write(output_unit, '(A)') "VMEC2000 not found"
        end if

        ! VMEC++
        if (repo_manager%is_cloned("vmecpp")) then
            n_total = n_total + 1
            repo_path = repo_manager%get_repo_path("vmecpp")

            if (verbose) write(output_unit, '(A)') "Found VMEC++ at: " // repo_path

            ! Use VMEC++ implementation
            block
                use vmecpp_implementation, only: vmecpp_t
                type(vmecpp_t), allocatable :: vmecpp
                allocate(vmecpp)
                call vmecpp%initialize("VMEC++", repo_path)

                write(output_unit, '(A)', advance='no') "Building VMEC++... "
                if (vmecpp%build()) then
                    write(output_unit, '(A)') "✓ SUCCESS"
                    n_built = n_built + 1
                else
                    write(output_unit, '(A)') "✗ FAILED"
                    exit_code = 1
                end if
                deallocate(vmecpp)
            end block
        else
            if (verbose) write(output_unit, '(A)') "VMEC++ not found"
        end if

        ! VMEX
        if (repo_manager%is_cloned("VMEX")) then
            n_total = n_total + 1
            repo_path = repo_manager%get_repo_path("VMEX")
            allocate(vmex)
            call vmex%initialize("VMEX", repo_path)
            write(output_unit, '(A)', advance='no') "Checking VMEX... "
            if (vmex%build()) then
                write(output_unit, '(A)') "✓ SUCCESS"
                n_built = n_built + 1
            else
                write(output_unit, '(A)') "✗ FAILED"
                exit_code = 1
            end if
            deallocate(vmex)
        else if (verbose) then
            write(output_unit, '(A)') "VMEX not found"
        end if

        ! DESC
        if (repo_manager%is_cloned("DESC")) then
            n_total = n_total + 1
            repo_path = repo_manager%get_repo_path("DESC")
            allocate(desc)
            call desc%initialize("DESC", repo_path)
            write(output_unit, '(A)', advance='no') "Checking DESC... "
            if (desc%build()) then
                write(output_unit, '(A)') "✓ SUCCESS"
                n_built = n_built + 1
            else
                write(output_unit, '(A)') "✗ FAILED"
                exit_code = 1
            end if
            deallocate(desc)
        else if (verbose) then
            write(output_unit, '(A)') "DESC not found"
        end if

        ! GVEC
        if (repo_manager%is_cloned("gvec")) then
            n_total = n_total + 1
            repo_path = repo_manager%get_repo_path("gvec")
            allocate(gvec)
            call gvec%initialize("GVEC", repo_path)
            write(output_unit, '(A)', advance='no') "Checking GVEC... "
            if (gvec%build()) then
                write(output_unit, '(A)') "✓ SUCCESS"
                n_built = n_built + 1
            else
                write(output_unit, '(A)') "✗ FAILED"
                exit_code = 1
            end if
            deallocate(gvec)
        else if (verbose) then
            write(output_unit, '(A)') "GVEC not found"
        end if

        if (repo_manager%is_cloned("PARVMEC")) then
            n_total = n_total + 1; repo_path = repo_manager%get_repo_path("PARVMEC")
            allocate(parvmec); call parvmec%initialize("PARVMEC", repo_path)
            write(output_unit, '(A)', advance='no') "Checking PARVMEC... "
            if (parvmec%build()) then; write(output_unit, '(A)') "✓ SUCCESS"; n_built=n_built+1
            else; write(output_unit, '(A)') "✗ unavailable"; end if
            deallocate(parvmec)
        end if
        if (repo_manager%is_cloned("SPEC")) then
            n_total = n_total + 1; repo_path = repo_manager%get_repo_path("SPEC")
            allocate(spec); call spec%initialize("SPEC", repo_path)
            write(output_unit, '(A)', advance='no') "Checking SPEC... "
            if (spec%build()) then; write(output_unit, '(A)') "✓ SUCCESS"; n_built=n_built+1
            else; write(output_unit, '(A)') "✗ unavailable"; end if
            deallocate(spec)
        end if
        if (repo_manager%is_cloned("SPECTRE")) then
            n_total = n_total + 1; repo_path = repo_manager%get_repo_path("SPECTRE")
            allocate(spectre); call spectre%initialize("SPECTRE", repo_path)
            write(output_unit, '(A)', advance='no') "Checking SPECTRE... "
            if (spectre%build()) then; write(output_unit, '(A)') "✓ SUCCESS"; n_built=n_built+1
            else; write(output_unit, '(A)') "✗ unavailable"; end if
            deallocate(spectre)
        end if
        if (repo_manager%is_cloned("FreeGS") .or. repo_manager%is_cloned("freegs")) then
            if (repo_manager%is_cloned("FreeGS")) then
                repo_path = repo_manager%get_repo_path("FreeGS")
            else
                repo_path = repo_manager%get_repo_path("freegs")
            end if
            n_total = n_total + 1; allocate(freegs); call freegs%initialize("FreeGS", repo_path)
            write(output_unit, '(A)', advance='no') "Checking FreeGS... "
            if (freegs%build()) then; write(output_unit, '(A)') "✓ SUCCESS"; n_built=n_built+1
            else; write(output_unit, '(A)') "✗ unavailable"; end if
            deallocate(freegs)
        end if
        if (repo_manager%is_cloned("CHEASE")) then
            n_total = n_total + 1; repo_path = repo_manager%get_repo_path("CHEASE")
            allocate(chease); call chease%initialize("CHEASE", repo_path)
            write(output_unit, '(A)', advance='no') "Checking CHEASE... "
            if (chease%build()) then; write(output_unit, '(A)') "✓ SUCCESS"; n_built=n_built+1
            else; write(output_unit, '(A)') "✗ unavailable"; end if
            deallocate(chease)
        end if

        write(output_unit, '(A)') ""
        write(output_unit, '(A,I0,A,I0,A)') "Built ", n_built, " out of ", n_total, " implementations"

    end subroutine build_all_implementations

end program vmec_build
