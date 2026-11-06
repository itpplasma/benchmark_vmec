program test_wout_reader
    use iso_fortran_env, only: error_unit, output_unit, real64
    use netcdf
    use wout_reader, only: read_wout_file, wout_data_t
    implicit none

    character(len=*), parameter :: path = "/tmp/benchmark_vmec_test_wout.nc"
    type(wout_data_t) :: data
    integer :: ncid, radius, ctor, presf, iotaf, stat

    stat = nf90_create(path, NF90_CLOBBER, ncid)
    stat = nf90_def_dim(ncid, "radius", 3, radius)
    stat = nf90_def_var(ncid, "ctor", NF90_DOUBLE, ctor)
    stat = nf90_def_var(ncid, "presf", NF90_DOUBLE, [radius], presf)
    stat = nf90_def_var(ncid, "iotaf", NF90_DOUBLE, [radius], iotaf)
    stat = nf90_enddef(ncid)
    stat = nf90_put_var(ncid, ctor, 4.0e4_real64)
    stat = nf90_put_var(ncid, presf, [1600.0_real64, 800.0_real64, 0.0_real64])
    stat = nf90_put_var(ncid, iotaf, [0.3_real64, 0.4_real64, 0.5_real64])
    stat = nf90_close(ncid)

    if (read_wout_file(path, data) .and. data%itor == 4.0e4_real64 .and. &
        data%pres_axis == 1600.0_real64 .and. data%iotaf_edge == 0.5_real64) then
        write(output_unit, '(A)') "✓ test_wout_reader_current_and_axis_pressure"
    else
        write(error_unit, '(A)') "✗ test_wout_reader_current_and_axis_pressure"
        call execute_command_line("rm -f " // path)
        stop 1
    end if
    call execute_command_line("rm -f " // path)
end program test_wout_reader
