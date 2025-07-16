module wout_reader
    use iso_fortran_env, only: int32, real64, error_unit
    use netcdf
    implicit none
    private

    public :: read_wout_file

    type, public :: wout_data_t
        ! Scalar quantities
        real(real64) :: wb          ! Magnetic energy
        real(real64) :: betatotal   ! Total beta
        real(real64) :: betapol     ! Poloidal beta
        real(real64) :: betator     ! Toroidal beta
        real(real64) :: betaxis     ! Beta on axis
        real(real64) :: aspect      ! Aspect ratio
        real(real64) :: raxis_cc    ! Major radius
        real(real64) :: rmin_surf   ! Minor radius
        real(real64) :: rmajor_p    ! Pressure-weighted major radius
        real(real64) :: volume_p    ! Plasma volume
        real(real64) :: iotaf_edge  ! Rotational transform at edge
        real(real64) :: itor        ! Toroidal current
        real(real64) :: aminor_p    ! Pressure-weighted minor radius
        real(real64) :: b0          ! Magnetic field on axis
        
        ! Profile arrays (simplified - just store edge values for now)
        integer :: ns               ! Number of flux surfaces
        logical :: valid = .false.
    contains
        procedure :: clear => wout_data_clear
    end type wout_data_t

contains

    subroutine wout_data_clear(this)
        class(wout_data_t), intent(out) :: this
        
        this%wb = 0.0_real64
        this%betatotal = 0.0_real64
        this%betapol = 0.0_real64
        this%betator = 0.0_real64
        this%betaxis = 0.0_real64
        this%aspect = 0.0_real64
        this%raxis_cc = 0.0_real64
        this%rmin_surf = 0.0_real64
        this%rmajor_p = 0.0_real64
        this%volume_p = 0.0_real64
        this%iotaf_edge = 0.0_real64
        this%itor = 0.0_real64
        this%aminor_p = 0.0_real64
        this%b0 = 0.0_real64
        this%ns = 0
        this%valid = .false.
    end subroutine wout_data_clear

    function read_wout_file(filename, data) result(success)
        character(len=*), intent(in) :: filename
        type(wout_data_t), intent(out) :: data
        logical :: success
        
        integer :: ncid, varid, status
        real(real64), allocatable :: iotaf(:)
        logical :: exists
        
        success = .false.
        call data%clear()
        
        ! Check if file exists
        inquire(file=filename, exist=exists)
        if (.not. exists) then
            write(error_unit, '(A)') "wout file not found: " // trim(filename)
            return
        end if
        
        ! Open NetCDF file
        status = nf90_open(filename, NF90_NOWRITE, ncid)
        if (status /= NF90_NOERR) then
            write(error_unit, '(A)') "Error opening wout file: " // trim(nf90_strerror(status))
            return
        end if
        
        ! Read scalar quantities
        call read_scalar(ncid, "wb", data%wb)
        call read_scalar(ncid, "betatotal", data%betatotal)
        call read_scalar(ncid, "betapol", data%betapol)
        call read_scalar(ncid, "betator", data%betator)
        call read_scalar(ncid, "betaxis", data%betaxis)
        call read_scalar(ncid, "aspect", data%aspect)
        call read_array_first(ncid, "raxis_cc", data%raxis_cc)
        call read_scalar(ncid, "rmin_surf", data%rmin_surf)
        call read_scalar(ncid, "rmajor_p", data%rmajor_p)
        call read_scalar(ncid, "volume_p", data%volume_p)
        call read_scalar(ncid, "itor", data%itor)
        call read_scalar(ncid, "aminor_p", data%aminor_p)
        call read_scalar(ncid, "b0", data%b0)
        
        ! Read radius dimension for iotaf array
        call read_dimension(ncid, "radius", data%ns)
        
        ! Read iotaf array and get edge value
        if (data%ns > 0) then
            allocate(iotaf(data%ns))
            status = nf90_inq_varid(ncid, "iotaf", varid)
            if (status == NF90_NOERR) then
                status = nf90_get_var(ncid, varid, iotaf)
                if (status == NF90_NOERR) then
                    data%iotaf_edge = iotaf(data%ns)
                end if
            end if
            deallocate(iotaf)
        end if
        
        ! Close file
        status = nf90_close(ncid)
        
        data%valid = .true.
        success = .true.
        
    end function read_wout_file
    
    subroutine read_scalar(ncid, varname, value)
        integer, intent(in) :: ncid
        character(len=*), intent(in) :: varname
        real(real64), intent(out) :: value
        
        integer :: varid, status
        
        status = nf90_inq_varid(ncid, varname, varid)
        if (status == NF90_NOERR) then
            status = nf90_get_var(ncid, varid, value)
            if (status /= NF90_NOERR) then
                value = 0.0_real64
            end if
        else
            value = 0.0_real64
        end if
    end subroutine read_scalar
    
    subroutine read_dimension(ncid, dimname, dimsize)
        integer, intent(in) :: ncid
        character(len=*), intent(in) :: dimname
        integer, intent(out) :: dimsize
        
        integer :: dimid, status
        
        status = nf90_inq_dimid(ncid, dimname, dimid)
        if (status == NF90_NOERR) then
            status = nf90_inquire_dimension(ncid, dimid, len=dimsize)
            if (status /= NF90_NOERR) then
                dimsize = 0
            end if
        else
            dimsize = 0
        end if
    end subroutine read_dimension
    
    subroutine read_array_first(ncid, varname, value)
        integer, intent(in) :: ncid
        character(len=*), intent(in) :: varname
        real(real64), intent(out) :: value
        
        integer :: varid, status
        real(real64) :: temp_array(1)
        
        status = nf90_inq_varid(ncid, varname, varid)
        if (status == NF90_NOERR) then
            status = nf90_get_var(ncid, varid, temp_array, start=(/1/), count=(/1/))
            if (status == NF90_NOERR) then
                value = temp_array(1)
            else
                value = 0.0_real64
            end if
        else
            value = 0.0_real64
        end if
    end subroutine read_array_first

end module wout_reader