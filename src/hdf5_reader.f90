module hdf5_reader
    use iso_fortran_env, only: real64, error_unit, int32
    use hdf5
    implicit none
    
    integer, parameter :: dp = real64
    
    type :: hdf5_data_t
        logical :: valid = .false.
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
        
        ! Fourier coefficients
        real(real64), allocatable :: rmnc(:,:)
        real(real64), allocatable :: rmns(:,:)
        real(real64), allocatable :: zmnc(:,:)
        real(real64), allocatable :: zmns(:,:)
        real(real64), allocatable :: lmnc(:,:)
        real(real64), allocatable :: lmns(:,:)
        real(real64), allocatable :: xm(:)
        real(real64), allocatable :: xn(:)
        integer :: mnmax
    contains
        procedure :: clear => hdf5_data_clear
    end type hdf5_data_t
    
contains
    
    subroutine hdf5_data_clear(this)
        class(hdf5_data_t), intent(inout) :: this
        
        this%valid = .false.
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
        this%mnmax = 0
        
        if (allocated(this%rmnc)) deallocate(this%rmnc)
        if (allocated(this%rmns)) deallocate(this%rmns)
        if (allocated(this%zmnc)) deallocate(this%zmnc)
        if (allocated(this%zmns)) deallocate(this%zmns)
        if (allocated(this%lmnc)) deallocate(this%lmnc)
        if (allocated(this%lmns)) deallocate(this%lmns)
        if (allocated(this%xm)) deallocate(this%xm)
        if (allocated(this%xn)) deallocate(this%xn)
    end subroutine hdf5_data_clear
    
    
    function read_hdf5_file(filename, data) result(success)
        character(len=*), intent(in) :: filename
        type(hdf5_data_t), intent(inout) :: data
        logical :: success
        
        integer(hid_t) :: file_id, dset_id, dspace_id
        integer :: error
        logical :: exists
        
        ! Initialize values to avoid potential issues
        file_id = -1
        dset_id = -1
        dspace_id = -1
        error = -1
        
        success = .false.
        write(error_unit, '(A)') 'DEBUG: About to call data%clear()'
        call data%clear()
        write(error_unit, '(A)') 'DEBUG: data%clear() completed'
        
        ! Check if file exists
        inquire(file=filename, exist=exists)
        if (.not. exists) then
            write(error_unit, '(A)') "HDF5 file does not exist: " // trim(filename)
            return
        end if
        
        ! Initialize HDF5 library
        write(error_unit, '(A)') 'DEBUG: About to initialize HDF5 library'
        call h5open_f(error)
        if (error /= 0) then
            write(error_unit, '(A)') "Failed to initialize HDF5 library"
            return
        end if
        write(error_unit, '(A)') 'DEBUG: HDF5 library initialized successfully'
        
        ! Open the file
        call h5fopen_f(filename, H5F_ACC_RDONLY_F, file_id, error)
        if (error /= 0) then
            write(error_unit, '(A)') "Failed to open HDF5 file: " // trim(filename)
            call h5close_f(error)
            return
        end if
        
        ! Read scalar quantities from /wout/ group
        call read_hdf5_scalar(file_id, "/wout/wb", data%wb, success)
        
        ! Try betatot (VMEC++ name) first, then betatotal
        call read_hdf5_scalar(file_id, "/wout/betatot", data%betatotal, success)
        if (data%betatotal == 0.0_dp) then
            call read_hdf5_scalar(file_id, "/wout/betatotal", data%betatotal, success)
        end if
        
        call read_hdf5_scalar(file_id, "/wout/betapol", data%betapol, success)
        call read_hdf5_scalar(file_id, "/wout/betator", data%betator, success)
        call read_hdf5_scalar(file_id, "/wout/aspect", data%aspect, success)
        call read_hdf5_scalar(file_id, "/wout/volume_p", data%volume_p, success)
        call read_hdf5_scalar(file_id, "/wout/itor", data%itor, success)
        call read_hdf5_scalar(file_id, "/wout/b0", data%b0, success)
        call read_hdf5_scalar(file_id, "/wout/Rmajor_p", data%rmajor_p, success)
        call read_hdf5_scalar(file_id, "/wout/Aminor_p", data%aminor_p, success)
        
        ! Read raxis_c array (VMEC++ format) and get first element
        call read_raxis_from_array(file_id, data%raxis_cc)
        
        ! Read iota_full array and get edge value
        call read_iotaf_edge_from_array(file_id, data%iotaf_edge)
        
        ! Read Fourier coefficients
        call read_hdf5_fourier_coefficients(file_id, data)
        
        ! Close the file
        call h5fclose_f(file_id, error)
        if (error /= 0) then
            write(error_unit, '(A)') "Warning: Failed to close HDF5 file properly"
        end if
        
        call h5close_f(error)
        if (error /= 0) then
            write(error_unit, '(A)') "Warning: Failed to close HDF5 library properly"
        end if
        
        data%valid = .true.
        success = .true.
    end function read_hdf5_file
    
    subroutine read_hdf5_scalar(file_id, var_name, value, success)
        integer(hid_t), intent(in) :: file_id
        character(len=*), intent(in) :: var_name
        real(real64), intent(out) :: value
        logical, intent(inout) :: success
        
        integer(hid_t) :: dset_id, dspace_id
        integer :: error
        
        ! Try to open the dataset
        call h5dopen_f(file_id, var_name, dset_id, error)
        if (error /= 0) then
            ! Variable not found - set to zero and continue
            value = 0.0_real64
            return
        end if
        
        ! Read the scalar value
        call h5dread_f(dset_id, H5T_NATIVE_DOUBLE, value, (/1_hsize_t/), error)
        if (error /= 0) then
            write(error_unit, '(A)') "Failed to read " // trim(var_name)
            value = 0.0_real64
        end if
        
        ! Close the dataset
        call h5dclose_f(dset_id, error)
    end subroutine read_hdf5_scalar
    
    subroutine read_raxis_from_array(file_id, raxis_cc)
        integer(hid_t), intent(in) :: file_id
        real(dp), intent(out) :: raxis_cc
        
        integer(hid_t) :: dset_id, dspace_id
        integer :: error, rank
        integer(hsize_t), dimension(1) :: dims, maxdims
        real(dp), allocatable :: raxis_c(:)
        
        raxis_cc = 0.0_dp
        
        ! Try to open raxis_c dataset
        call h5dopen_f(file_id, "/wout/raxis_c", dset_id, error)
        if (error /= 0) return
        
        ! Get dataspace
        call h5dget_space_f(dset_id, dspace_id, error)
        if (error /= 0) then
            call h5dclose_f(dset_id, error)
            return
        end if
        
        ! Get dimensions
        call h5sget_simple_extent_ndims_f(dspace_id, rank, error)
        if (error == 0 .and. rank == 1) then
            call h5sget_simple_extent_dims_f(dspace_id, dims, maxdims, error)
            if (error >= 0 .and. dims(1) > 0) then
                allocate(raxis_c(dims(1)))
                call h5dread_f(dset_id, H5T_NATIVE_DOUBLE, raxis_c, dims, error)
                if (error == 0) then
                    raxis_cc = raxis_c(1)
                end if
                deallocate(raxis_c)
            end if
        end if
        
        call h5sclose_f(dspace_id, error)
        call h5dclose_f(dset_id, error)
    end subroutine read_raxis_from_array
    
    subroutine read_iotaf_edge_from_array(file_id, iotaf_edge)
        integer(hid_t), intent(in) :: file_id
        real(dp), intent(out) :: iotaf_edge
        
        integer(hid_t) :: dset_id, dspace_id
        integer :: error, rank
        integer(hsize_t), dimension(1) :: dims, maxdims
        real(dp), allocatable :: iota_full(:)
        
        iotaf_edge = 0.0_dp
        
        ! Try to open iota_full dataset
        call h5dopen_f(file_id, "/wout/iota_full", dset_id, error)
        if (error /= 0) return
        
        ! Get dataspace
        call h5dget_space_f(dset_id, dspace_id, error)
        if (error /= 0) then
            call h5dclose_f(dset_id, error)
            return
        end if
        
        ! Get dimensions
        call h5sget_simple_extent_ndims_f(dspace_id, rank, error)
        if (error == 0 .and. rank == 1) then
            call h5sget_simple_extent_dims_f(dspace_id, dims, maxdims, error)
            if (error >= 0 .and. dims(1) > 0) then
                allocate(iota_full(dims(1)))
                call h5dread_f(dset_id, H5T_NATIVE_DOUBLE, iota_full, dims, error)
                if (error == 0) then
                    iotaf_edge = iota_full(dims(1))
                end if
                deallocate(iota_full)
            end if
        end if
        
        call h5sclose_f(dspace_id, error)
        call h5dclose_f(dset_id, error)
    end subroutine read_iotaf_edge_from_array
    
    subroutine read_hdf5_fourier_coefficients(file_id, data)
        integer(hid_t), intent(in) :: file_id
        type(hdf5_data_t), intent(inout) :: data
        
        integer :: ns, mnmax
        
        ! Get dimensions from rmnc dataset
        call get_hdf5_2d_dims(file_id, "/wout/rmnc", ns, mnmax)
        
        ! Add bounds checking to prevent memory corruption
        if (ns > 0 .and. mnmax > 0 .and. ns < 10000 .and. mnmax < 10000) then
            data%mnmax = mnmax
            
            ! Read main Fourier coefficients with error checking
            if (dataset_exists(file_id, "/wout/rmnc")) then
                allocate(data%rmnc(ns, mnmax))
                call read_hdf5_2d_array(file_id, "/wout/rmnc", data%rmnc, ns, mnmax)
            end if
            
            if (dataset_exists(file_id, "/wout/zmns")) then
                allocate(data%zmns(ns, mnmax))
                call read_hdf5_2d_array(file_id, "/wout/zmns", data%zmns, ns, mnmax)
            end if
            
            if (dataset_exists(file_id, "/wout/lmns")) then
                allocate(data%lmns(ns, mnmax))
                call read_hdf5_2d_array(file_id, "/wout/lmns", data%lmns, ns, mnmax)
            end if
            
            ! Read mode numbers
            if (dataset_exists(file_id, "/wout/xm")) then
                allocate(data%xm(mnmax))
                call read_hdf5_1d_array(file_id, "/wout/xm", data%xm, mnmax)
            end if
            
            if (dataset_exists(file_id, "/wout/xn")) then
                allocate(data%xn(mnmax))
                call read_hdf5_1d_array(file_id, "/wout/xn", data%xn, mnmax)
            end if
            
            ! Read optional arrays (may be zero-sized for stellarator symmetry)
            if (dataset_exists(file_id, "/wout/rmns")) then
                allocate(data%rmns(ns, mnmax))
                call read_hdf5_2d_array(file_id, "/wout/rmns", data%rmns, ns, mnmax)
            end if
            
            if (dataset_exists(file_id, "/wout/zmnc")) then
                allocate(data%zmnc(ns, mnmax))
                call read_hdf5_2d_array(file_id, "/wout/zmnc", data%zmnc, ns, mnmax)
            end if
            
            if (dataset_exists(file_id, "/wout/lmnc")) then
                allocate(data%lmnc(ns, mnmax))
                call read_hdf5_2d_array(file_id, "/wout/lmnc", data%lmnc, ns, mnmax)
            end if
        end if
    end subroutine read_hdf5_fourier_coefficients
    
    subroutine get_hdf5_2d_dims(file_id, dataset_name, dim1, dim2)
        integer(hid_t), intent(in) :: file_id
        character(len=*), intent(in) :: dataset_name
        integer, intent(out) :: dim1, dim2
        
        integer(hid_t) :: dset_id, dspace_id
        integer :: error, rank
        integer(hsize_t), dimension(2) :: dims, maxdims
        
        dim1 = 0
        dim2 = 0
        
        call h5dopen_f(file_id, dataset_name, dset_id, error)
        if (error == 0) then
            call h5dget_space_f(dset_id, dspace_id, error)
            if (error == 0) then
                call h5sget_simple_extent_ndims_f(dspace_id, rank, error)
                if (error == 0 .and. rank == 2) then
                    call h5sget_simple_extent_dims_f(dspace_id, dims, maxdims, error)
                    if (error >= 0) then
                        dim1 = int(dims(1))
                        dim2 = int(dims(2))
                    end if
                end if
                call h5sclose_f(dspace_id, error)
            end if
            call h5dclose_f(dset_id, error)
        end if
    end subroutine get_hdf5_2d_dims
    
    subroutine read_hdf5_2d_array(file_id, dataset_name, array, dim1, dim2)
        integer(hid_t), intent(in) :: file_id
        character(len=*), intent(in) :: dataset_name
        integer, intent(in) :: dim1, dim2
        real(dp), intent(out) :: array(dim1, dim2)
        
        integer(hid_t) :: dset_id
        integer :: error
        integer(hsize_t), dimension(2) :: dims
        
        dims = [dim1, dim2]
        array = 0.0_dp
        
        call h5dopen_f(file_id, dataset_name, dset_id, error)
        if (error == 0) then
            call h5dread_f(dset_id, H5T_NATIVE_DOUBLE, array, dims, error)
            if (error /= 0) then
                write(error_unit, '(A)') "Warning: Failed to read HDF5 dataset " // trim(dataset_name)
                array = 0.0_dp
            end if
            call h5dclose_f(dset_id, error)
        else
            write(error_unit, '(A)') "Warning: Failed to open HDF5 dataset " // trim(dataset_name)
        end if
    end subroutine read_hdf5_2d_array
    
    subroutine read_hdf5_1d_array(file_id, dataset_name, array, dim1)
        integer(hid_t), intent(in) :: file_id
        character(len=*), intent(in) :: dataset_name
        integer, intent(in) :: dim1
        real(dp), intent(out) :: array(dim1)
        
        integer(hid_t) :: dset_id
        integer :: error
        integer(hsize_t), dimension(1) :: dims
        
        dims = [dim1]
        array = 0.0_dp
        
        call h5dopen_f(file_id, dataset_name, dset_id, error)
        if (error == 0) then
            call h5dread_f(dset_id, H5T_NATIVE_DOUBLE, array, dims, error)
            if (error /= 0) then
                write(error_unit, '(A)') "Warning: Failed to read HDF5 dataset " // trim(dataset_name)
                array = 0.0_dp
            end if
            call h5dclose_f(dset_id, error)
        else
            write(error_unit, '(A)') "Warning: Failed to open HDF5 dataset " // trim(dataset_name)
        end if
    end subroutine read_hdf5_1d_array
    
    function dataset_exists(file_id, dataset_name) result(exists)
        integer(hid_t), intent(in) :: file_id
        character(len=*), intent(in) :: dataset_name
        logical :: exists
        
        integer(hid_t) :: dset_id
        integer :: error
        
        call h5dopen_f(file_id, dataset_name, dset_id, error)
        exists = (error == 0)
        if (exists) then
            call h5dclose_f(dset_id, error)
        end if
    end function dataset_exists
    
end module hdf5_reader