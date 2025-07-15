module repository_manager
    use iso_fortran_env, only: int32, real64, error_unit
    use vmec_benchmark_types, only: repository_config_t
    implicit none
    private

    public :: repository_manager_t, init_default_repositories

    type :: repository_manager_t
        character(len=:), allocatable :: base_path
        type(repository_config_t), allocatable :: repositories(:)
        integer :: n_repos = 0
    contains
        procedure :: initialize => repository_manager_initialize
        procedure :: add_repository => repository_manager_add_repository
        procedure :: get_repo_path => repository_manager_get_repo_path
        procedure :: is_cloned => repository_manager_is_cloned
        procedure :: clone_repo => repository_manager_clone_repo
        procedure :: update_repo => repository_manager_update_repo
        procedure :: clone_all => repository_manager_clone_all
        procedure :: get_test_data_path => repository_manager_get_test_data_path
        procedure :: finalize => repository_manager_finalize
    end type repository_manager_t

contains

    subroutine init_default_repositories(repos)
        type(repository_config_t), allocatable, intent(out) :: repos(:)
        
        allocate(repos(3))
        
        call repos(1)%initialize( &
            name="educational_VMEC", &
            url="https://github.com/jonathanschilling/educational_VMEC.git", &
            branch="master", &
            build_command="cmake", &
            test_data_path="")
        
        call repos(2)%initialize( &
            name="VMEC2000", &
            url="https://github.com/hiddenSymmetries/VMEC2000.git", &
            branch="master", &
            build_command="pip", &
            test_data_path="")
        
        call repos(3)%initialize( &
            name="VMEC++", &
            url="https://github.com/itpplasma/vmecpp.git", &
            branch="main", &
            build_command="pip", &
            test_data_path="src/vmecpp/test_data")
    end subroutine init_default_repositories

    subroutine repository_manager_initialize(this, base_path)
        class(repository_manager_t), intent(inout) :: this
        character(len=*), intent(in) :: base_path
        integer :: stat
        
        this%base_path = trim(base_path)
        
        ! Create base directory if it doesn't exist
        call execute_command_line("mkdir -p " // this%base_path, exitstat=stat)
        
        ! Initialize with default repositories
        call init_default_repositories(this%repositories)
        this%n_repos = size(this%repositories)
    end subroutine repository_manager_initialize

    subroutine repository_manager_add_repository(this, repo)
        class(repository_manager_t), intent(inout) :: this
        type(repository_config_t), intent(in) :: repo
        type(repository_config_t), allocatable :: temp(:)
        
        if (allocated(this%repositories)) then
            allocate(temp(this%n_repos + 1))
            temp(1:this%n_repos) = this%repositories
            temp(this%n_repos + 1) = repo
            call move_alloc(temp, this%repositories)
        else
            allocate(this%repositories(1))
            this%repositories(1) = repo
        end if
        
        this%n_repos = this%n_repos + 1
    end subroutine repository_manager_add_repository

    function repository_manager_get_repo_path(this, repo_name) result(path)
        class(repository_manager_t), intent(in) :: this
        character(len=*), intent(in) :: repo_name
        character(len=:), allocatable :: path
        
        path = trim(this%base_path) // "/" // trim(repo_name)
    end function repository_manager_get_repo_path

    function repository_manager_is_cloned(this, repo_name) result(is_cloned)
        class(repository_manager_t), intent(in) :: this
        character(len=*), intent(in) :: repo_name
        logical :: is_cloned
        character(len=:), allocatable :: repo_path, git_path
        integer :: stat
        
        repo_path = this%get_repo_path(repo_name)
        git_path = trim(repo_path) // "/.git"
        
        ! Check if directory exists
        inquire(file=trim(repo_path), exist=is_cloned)
        
        if (is_cloned) then
            ! Also check if .git directory exists
            inquire(file=trim(git_path), exist=is_cloned)
        end if
    end function repository_manager_is_cloned

    subroutine repository_manager_clone_repo(this, repo_index, force, success)
        class(repository_manager_t), intent(inout) :: this
        integer, intent(in) :: repo_index
        logical, intent(in) :: force
        logical, intent(out) :: success
        character(len=:), allocatable :: repo_path, cmd, repo_name
        integer :: stat
        
        success = .false.
        
        if (repo_index < 1 .or. repo_index > this%n_repos) then
            write(error_unit, *) "Invalid repository index:", repo_index
            return
        end if
        
        ! Extract repository name from URL
        repo_name = extract_repo_name(this%repositories(repo_index)%url)
        repo_path = this%get_repo_path(repo_name)
        
        if (this%is_cloned(repo_name) .and. .not. force) then
            write(*, '(A)') trim(this%repositories(repo_index)%name) // &
                " already cloned at " // trim(repo_path)
            success = .true.
            return
        end if
        
        if (force) then
            ! Remove existing repository
            cmd = "rm -rf " // trim(repo_path)
            call execute_command_line(trim(cmd), exitstat=stat)
        end if
        
        write(*, '(A)') "Cloning " // trim(this%repositories(repo_index)%name) // &
            " from " // trim(this%repositories(repo_index)%url)
        
        ! Clone the repository with submodules
        cmd = "git clone --recursive --depth 1 -b " // trim(this%repositories(repo_index)%branch) // &
            " " // trim(this%repositories(repo_index)%url) // " " // trim(repo_path)
        
        call execute_command_line(trim(cmd), exitstat=stat)
        
        if (stat == 0) then
            write(*, '(A)') "Successfully cloned " // trim(this%repositories(repo_index)%name)
            success = .true.
        else
            write(error_unit, '(A)') "Failed to clone " // trim(this%repositories(repo_index)%name)
        end if
    end subroutine repository_manager_clone_repo

    subroutine repository_manager_update_repo(this, repo_index, success)
        class(repository_manager_t), intent(in) :: this
        integer, intent(in) :: repo_index
        logical, intent(out) :: success
        character(len=:), allocatable :: repo_path, cmd, repo_name
        integer :: stat
        
        success = .false.
        
        if (repo_index < 1 .or. repo_index > this%n_repos) then
            write(error_unit, *) "Invalid repository index:", repo_index
            return
        end if
        
        repo_name = extract_repo_name(this%repositories(repo_index)%url)
        
        if (.not. this%is_cloned(repo_name)) then
            write(error_unit, '(A)') "Repository " // trim(repo_name) // " is not cloned"
            return
        end if
        
        repo_path = this%get_repo_path(repo_name)
        
        write(*, '(A)') "Updating " // trim(this%repositories(repo_index)%name)
        
        cmd = "cd " // trim(repo_path) // " && git pull"
        call execute_command_line(trim(cmd), exitstat=stat)
        
        if (stat == 0) then
            write(*, '(A)') "Successfully updated " // trim(this%repositories(repo_index)%name)
            success = .true.
        else
            write(error_unit, '(A)') "Failed to update " // trim(this%repositories(repo_index)%name)
        end if
    end subroutine repository_manager_update_repo

    subroutine repository_manager_clone_all(this, force)
        class(repository_manager_t), intent(inout) :: this
        logical, intent(in), optional :: force
        logical :: force_clone, success
        integer :: i
        
        force_clone = .false.
        if (present(force)) force_clone = force
        
        do i = 1, this%n_repos
            call this%clone_repo(i, force_clone, success)
        end do
    end subroutine repository_manager_clone_all

    function repository_manager_get_test_data_path(this, repo_name) result(path)
        class(repository_manager_t), intent(in) :: this
        character(len=*), intent(in) :: repo_name
        character(len=:), allocatable :: path
        integer :: i
        logical :: exists
        
        path = ""
        
        ! Find repository by name
        do i = 1, this%n_repos
            if (extract_repo_name(this%repositories(i)%url) == repo_name) then
                if (len_trim(this%repositories(i)%test_data_path) > 0) then
                    path = trim(this%get_repo_path(repo_name)) // "/" // &
                        trim(this%repositories(i)%test_data_path)
                    
                    ! Check if path exists
                    inquire(file=trim(path), exist=exists)
                    if (.not. exists) path = ""
                end if
                exit
            end if
        end do
    end function repository_manager_get_test_data_path

    subroutine repository_manager_finalize(this)
        class(repository_manager_t), intent(inout) :: this
        
        if (allocated(this%base_path)) deallocate(this%base_path)
        if (allocated(this%repositories)) deallocate(this%repositories)
        this%n_repos = 0
    end subroutine repository_manager_finalize

    function extract_repo_name(url) result(name)
        character(len=*), intent(in) :: url
        character(len=:), allocatable :: name
        integer :: last_slash, dot_git
        
        ! Find last slash
        last_slash = index(url, '/', back=.true.)
        
        if (last_slash > 0) then
            name = url(last_slash+1:)
            
            ! Remove .git extension if present
            dot_git = index(name, '.git')
            if (dot_git > 0) then
                name = name(1:dot_git-1)
            end if
        else
            name = "unknown"
        end if
    end function extract_repo_name

end module repository_manager