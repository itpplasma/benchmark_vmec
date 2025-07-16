program test_netcdf
    use wout_reader
    implicit none
    
    type(wout_data_t) :: data
    logical :: success
    character(len=256) :: filename
    
    filename = "./benchmark_results/input/educational_vmec/wout_cth_like_fixed_bdy.nc"
    
    print *, "Testing NetCDF read..."
    success = read_wout_file(filename, data)
    
    print *, "Read success: ", success
    print *, "Data valid: ", data%valid
    print *, "wb = ", data%wb
    print *, "betatotal = ", data%betatotal
    print *, "aspect = ", data%aspect
    
end program test_netcdf