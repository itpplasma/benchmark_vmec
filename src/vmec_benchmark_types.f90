module vmec_benchmark_types
    use iso_fortran_env, only: int32, real64
    implicit none
    private

    public :: repository_config_t, vmec_result_t, string_t

    type :: string_t
        character(len=:), allocatable :: str
    end type string_t

    type :: repository_config_t
        character(len=:), allocatable :: name
        character(len=:), allocatable :: url
        character(len=:), allocatable :: branch
        character(len=:), allocatable :: build_command
        character(len=:), allocatable :: test_data_path
    contains
        procedure :: initialize => repository_config_initialize
    end type repository_config_t

    type :: vmec_result_t
        logical :: success = .false.
        character(len=:), allocatable :: error_message
        real(real64) :: wb = 0.0_real64
        real(real64) :: betatotal = 0.0_real64
        real(real64) :: betapol = 0.0_real64
        real(real64) :: betator = 0.0_real64
        real(real64) :: aspect = 0.0_real64
        real(real64) :: raxis_cc = 0.0_real64
        real(real64) :: volume_p = 0.0_real64
        real(real64) :: iotaf_edge = 0.0_real64
        real(real64) :: itor = 0.0_real64
        real(real64) :: b0 = 0.0_real64
        real(real64) :: rmajor_p = 0.0_real64
        real(real64) :: aminor_p = 0.0_real64
        real(real64), allocatable :: rmnc(:,:)
        real(real64), allocatable :: rmns(:,:)
        real(real64), allocatable :: zmnc(:,:)
        real(real64), allocatable :: zmns(:,:)
        real(real64), allocatable :: lmnc(:,:)
        real(real64), allocatable :: lmns(:,:)
        real(real64), allocatable :: xm(:)
        real(real64), allocatable :: xn(:)
        real(real64), allocatable :: phi(:)
    contains
        procedure :: clear => vmec_result_clear
    end type vmec_result_t

contains

    subroutine repository_config_initialize(this, name, url, branch, build_command, test_data_path)
        class(repository_config_t), intent(inout) :: this
        character(len=*), intent(in) :: name
        character(len=*), intent(in) :: url
        character(len=*), intent(in), optional :: branch
        character(len=*), intent(in), optional :: build_command
        character(len=*), intent(in), optional :: test_data_path

        this%name = trim(name)
        this%url = trim(url)
        
        if (present(branch)) then
            this%branch = trim(branch)
        else
            this%branch = "main"
        end if
        
        if (present(build_command)) then
            this%build_command = trim(build_command)
        else
            this%build_command = ""
        end if
        
        if (present(test_data_path)) then
            this%test_data_path = trim(test_data_path)
        else
            this%test_data_path = ""
        end if
    end subroutine repository_config_initialize

    subroutine vmec_result_clear(this)
        class(vmec_result_t), intent(inout) :: this
        
        this%success = .false.
        if (allocated(this%error_message)) deallocate(this%error_message)
        this%wb = 0.0_real64
        this%betatotal = 0.0_real64
        this%betapol = 0.0_real64
        this%betator = 0.0_real64
        this%aspect = 0.0_real64
        this%raxis_cc = 0.0_real64
        this%volume_p = 0.0_real64
        this%iotaf_edge = 0.0_real64
        this%itor = 0.0_real64
        this%b0 = 0.0_real64
        this%rmajor_p = 0.0_real64
        this%aminor_p = 0.0_real64
        
        if (allocated(this%rmnc)) deallocate(this%rmnc)
        if (allocated(this%rmns)) deallocate(this%rmns)
        if (allocated(this%zmnc)) deallocate(this%zmnc)
        if (allocated(this%zmns)) deallocate(this%zmns)
        if (allocated(this%lmnc)) deallocate(this%lmnc)
        if (allocated(this%lmns)) deallocate(this%lmns)
        if (allocated(this%xm)) deallocate(this%xm)
        if (allocated(this%xn)) deallocate(this%xn)
        if (allocated(this%phi)) deallocate(this%phi)
    end subroutine vmec_result_clear

end module vmec_benchmark_types