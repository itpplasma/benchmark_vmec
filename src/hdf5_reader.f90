module hdf5_reader
    use iso_fortran_env, only: real64, error_unit
    use hdf5
    implicit none
    
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
    end type hdf5_data_t
    
contains
    
    function read_hdf5_file(filename, data) result(success)
        character(len=*), intent(in) :: filename
        type(hdf5_data_t), intent(out) :: data
        logical :: success
        
        integer(hid_t) :: file_id, dset_id, dspace_id
        integer :: error
        logical :: exists
        
        success = .false.
        data%valid = .false.
        
        ! Check if file exists
        inquire(file=filename, exist=exists)
        if (.not. exists) then
            write(error_unit, '(A)') "HDF5 file does not exist: " // trim(filename)
            return
        end if
        
        ! Initialize HDF5 library
        call h5open_f(error)
        if (error /= 0) then
            write(error_unit, '(A)') "Failed to initialize HDF5 library"
            return
        end if
        
        ! Open the file
        call h5fopen_f(filename, H5F_ACC_RDONLY_F, file_id, error)
        if (error /= 0) then
            write(error_unit, '(A)') "Failed to open HDF5 file: " // trim(filename)
            call h5close_f(error)
            return
        end if
        
        ! Read scalar quantities from /wout/ group
        call read_hdf5_scalar(file_id, "/wout/wb", data%wb, success)
        
        call read_hdf5_scalar(file_id, "/wout/betatotal", data%betatotal, success)
        call read_hdf5_scalar(file_id, "/wout/betapol", data%betapol, success)
        call read_hdf5_scalar(file_id, "/wout/betator", data%betator, success)
        call read_hdf5_scalar(file_id, "/wout/aspect", data%aspect, success)
        call read_hdf5_scalar(file_id, "/wout/raxis_cc", data%raxis_cc, success)
        call read_hdf5_scalar(file_id, "/wout/volume_p", data%volume_p, success)
        call read_hdf5_scalar(file_id, "/wout/iotaf_edge", data%iotaf_edge, success)
        call read_hdf5_scalar(file_id, "/wout/itor", data%itor, success)
        call read_hdf5_scalar(file_id, "/wout/b0", data%b0, success)
        call read_hdf5_scalar(file_id, "/wout/rmajor_p", data%rmajor_p, success)
        call read_hdf5_scalar(file_id, "/wout/aminor_p", data%aminor_p, success)
        
        ! Close the file
        call h5fclose_f(file_id, error)
        call h5close_f(error)
        
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
    
end module hdf5_reader