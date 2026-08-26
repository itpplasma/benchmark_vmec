program test_runner_reporting
    use iso_fortran_env, only: error_unit, output_unit, real64
    use benchmark_runner, only: benchmark_runner_t, freegs_case_supported, gvec_case_supported, &
        chease_case_supported, &
        geqdsk_case_supported, &
        spec_case_supported, spectre_case_supported, native_gvec_case, native_desc_case
    use repository_manager, only: repository_manager_t
    use results_comparator, only: results_comparator_t
    use vmec_benchmark_types, only: vmec_result_t
    implicit none

    integer :: n_tests, n_passed

    n_tests = 0
    n_passed = 0

    write(output_unit, '(A)') "Running benchmark runner/reporting tests..."

    call test_case_name_normalization(n_tests, n_passed)
    call test_case_match_filter(n_tests, n_passed)
    call test_free_boundary_cases_are_discovered(n_tests, n_passed)
    call test_gvec_parameter_cases_are_discovered(n_tests, n_passed)
    call test_empty_case_match_does_not_filter(n_tests, n_passed)
    call test_literal_empty_case_match_does_not_filter(n_tests, n_passed)
    call test_freegs_case_filter(n_tests, n_passed)
    call test_external_case_filters(n_tests, n_passed)
    call test_custom_output_dir_for_jvmec_reports(n_tests, n_passed)
    call test_report_uses_successful_reference(n_tests, n_passed)
    call test_report_prefers_educational_reference_over_jvmec(n_tests, n_passed)
    call test_report_separates_physical_domains(n_tests, n_passed)

    write(output_unit, '(/,A,I0,A,I0,A)') "Tests passed: ", n_passed, "/", n_tests, " tests"

    if (n_passed /= n_tests) then
        write(error_unit, '(A)') "Some tests failed!"
        stop 1
    end if

contains

    subroutine test_freegs_case_filter(n_tests, n_passed)
        integer, intent(inout) :: n_tests, n_passed

        n_tests = n_tests + 1
        if (freegs_case_supported('/repo/cases/analytic/2d_solovev/input.solovev') .and. &
            .not. freegs_case_supported('/repo/cases/numerical/3d_w7x/input.w7x') .and. &
            .not. freegs_case_supported('/repo/educational_VMEC/from_DESC/W7X/input.W7X')) then
            n_passed = n_passed + 1
            write(output_unit, '(A)') "✓ test_freegs_case_filter"
        else
            write(error_unit, '(A)') "✗ test_freegs_case_filter"
        end if
    end subroutine test_freegs_case_filter

    subroutine test_external_case_filters(n_tests, n_passed)
        integer, intent(inout) :: n_tests, n_passed

        n_tests = n_tests + 1
        if (gvec_case_supported('/repo/cases/analytic/2d_solovev/input.solovev') .and. &
            gvec_case_supported('/repo/cases/numerical/3d_w7x/input.w7x') .and. &
            .not. gvec_case_supported('/repo/cases/numerical/1d_profile/input.profile_1d') .and. &
            chease_case_supported('/repo/cases/analytic/2d_solovev/solovev.geqdsk') .and. &
            geqdsk_case_supported('/repo/cases/generated/2d_chease/input.geqdsk') .and. &
            .not. geqdsk_case_supported('/repo/cases/analytic/2d_solovev/input.solovev') .and. &
            .not. chease_case_supported('/repo/cases/numerical/3d_w7x/input.w7x') .and. &
            .not. chease_case_supported('/repo/cases/analytic/2d_solovev/input.solovev') .and. &
            spec_case_supported('/repo/SPEC/ci/G1V03L3Fi/G1V03L3Fi.sp') .and. &
            .not. spec_case_supported('/repo/cases/numerical/3d_w7x/input.w7x') .and. &
            spectre_case_supported('/repo/cases/numerical/3d_w7x/input.w7x') .and. &
            spectre_case_supported('/repo/SPECTRE/tests/file_io/input.toml') .and. &
            .not. spectre_case_supported('/repo/cases/numerical/3d_w7x/w7x.nc') .and. &
            native_gvec_case('/repo/gvec/test-CI/examples/case/parameter.ini') .and. &
            native_gvec_case('/repo/gvec/python/examples/case/parameter.toml') .and. &
            .not. native_gvec_case('/repo/cases/analytic/2d_solovev/parameter.ini') .and. &
            native_desc_case('/repo/DESC/inputs/DSHAPE_desc') .and. &
            native_desc_case('/repo/DESC/inputs/QSC_r2_5.5_desc') .and. &
            .not. native_desc_case('/repo/educational_VMEC/from_DESC/NCSX/input.NCSX')) then
            n_passed = n_passed + 1
            write(output_unit, '(A)') "✓ test_external_case_filters"
        else
            write(error_unit, '(A)') "✗ test_external_case_filters"
        end if
    end subroutine test_external_case_filters

    subroutine test_case_name_normalization(n_tests, n_passed)
        integer, intent(inout) :: n_tests, n_passed
        type(benchmark_runner_t) :: runner
        character(len=256), allocatable :: names(:)

        n_tests = n_tests + 1

        allocate(runner%test_cases(2))
        runner%n_test_cases = 2
        runner%test_cases(1)%str = "/tmp/repos/educational_VMEC/test/from_vmec_multiple_readin/input.li383_low_res"
        runner%test_cases(2)%str = "/tmp/repos/jVMEC/src/test/resources/input.li383_low_res"

        names = runner%get_test_case_names()

        if (size(names) == 2 .and. &
            trim(names(1)) == "educational_VMEC/from_vmec_multiple_readin/li383_low_res" .and. &
            trim(names(2)) == "jVMEC/li383_low_res") then
            n_passed = n_passed + 1
            write(output_unit, '(A)') "✓ test_case_name_normalization"
        else
            write(error_unit, '(A)') "✗ test_case_name_normalization"
        end if

        call runner%finalize()
    end subroutine test_case_name_normalization

    subroutine test_case_match_filter(n_tests, n_passed)
        integer, intent(inout) :: n_tests, n_passed
        type(repository_manager_t) :: repo_manager
        type(benchmark_runner_t) :: runner
        character(len=256), allocatable :: names(:)
        character(len=*), parameter :: base_dir = "/tmp/benchmark_vmec_case_match"
        integer :: stat

        n_tests = n_tests + 1

        call execute_command_line("rm -rf " // base_dir, exitstat=stat)
        call execute_command_line("mkdir -p " // base_dir // "/educational_VMEC/.git", exitstat=stat)
        call execute_command_line("mkdir -p " // base_dir // "/educational_VMEC/test/examples", exitstat=stat)
        call execute_command_line("mkdir -p " // base_dir // "/VMEC2000/.git", exitstat=stat)
        call execute_command_line("mkdir -p " // base_dir // "/VMEC2000/test/examples", exitstat=stat)
        call execute_command_line("touch " // base_dir // &
            "/educational_VMEC/test/examples/input.circular_tokamak", exitstat=stat)
        call execute_command_line("touch " // base_dir // &
            "/VMEC2000/test/examples/input.li383_low_res", exitstat=stat)

        call repo_manager%initialize(base_dir)
        call runner%initialize(base_dir // "/results", repo_manager)
        call runner%discover_test_cases(case_match="tokamak")
        names = runner%get_test_case_names()

        if (size(names) == 1 .and. &
            trim(names(1)) == "educational_VMEC/circular_tokamak") then
            n_passed = n_passed + 1
            write(output_unit, '(A)') "✓ test_case_match_filter"
        else
            write(error_unit, '(A)') "✗ test_case_match_filter"
        end if

        call runner%finalize()
        call repo_manager%finalize()
        call execute_command_line("rm -rf " // base_dir, exitstat=stat)
    end subroutine test_case_match_filter

    subroutine test_free_boundary_cases_are_discovered(n_tests, n_passed)
        integer, intent(inout) :: n_tests, n_passed
        type(repository_manager_t) :: repo_manager
        type(benchmark_runner_t) :: runner
        character(len=256), allocatable :: names(:)
        character(len=*), parameter :: base_dir = "/tmp/benchmark_vmec_free_boundary"
        integer :: stat, unit
        logical :: case_matches

        n_tests = n_tests + 1
        call execute_command_line("rm -rf " // base_dir, exitstat=stat)
        call execute_command_line("mkdir -p " // base_dir // "/VMEX/.git", exitstat=stat)
        call execute_command_line("mkdir -p " // base_dir // "/VMEX/tests", exitstat=stat)
        open(newunit=unit, file=base_dir // "/VMEX/tests/input.free_boundary", &
            status="replace", action="write")
        write(unit, '(A)') "&INDATA"
        write(unit, '(A)') "  LFREEB = T"
        write(unit, '(A)') "/"
        close(unit)

        call repo_manager%initialize(base_dir)
        call runner%initialize(base_dir // "/results", repo_manager)
        call runner%discover_test_cases()
        names = runner%get_test_case_names()

        case_matches = .false.
        if (size(names) == 1) case_matches = trim(names(1)) == "VMEX/free_boundary"
        if (case_matches) then
            n_passed = n_passed + 1
            write(output_unit, '(A)') "✓ test_free_boundary_cases_are_discovered"
        else
            write(error_unit, '(A)') "✗ test_free_boundary_cases_are_discovered"
        end if

        call runner%finalize()
        call repo_manager%finalize()
        call execute_command_line("rm -rf " // base_dir, exitstat=stat)
    end subroutine test_free_boundary_cases_are_discovered

    subroutine test_gvec_parameter_cases_are_discovered(n_tests, n_passed)
        integer, intent(inout) :: n_tests, n_passed
        type(repository_manager_t) :: repo_manager
        type(benchmark_runner_t) :: runner
        character(len=256), allocatable :: names(:)
        character(len=*), parameter :: base_dir = "/tmp/benchmark_vmec_gvec_cases"
        integer :: stat, unit
        logical :: case_matches

        n_tests = n_tests + 1
        call execute_command_line("rm -rf " // base_dir, exitstat=stat)
        call execute_command_line("mkdir -p " // base_dir // "/gvec/.git", exitstat=stat)
        call execute_command_line("mkdir -p " // base_dir // "/gvec/test-CI/examples/case", exitstat=stat)
        open(newunit=unit, file=base_dir // "/gvec/test-CI/examples/case/parameter.ini", &
            status="replace", action="write")
        write(unit, '(A)') "ProjectName = test"
        close(unit)

        call repo_manager%initialize(base_dir)
        call runner%initialize(base_dir // "/results", repo_manager)
        call runner%discover_test_cases()
        names = runner%get_test_case_names()

        case_matches = .false.
        if (size(names) == 1) case_matches = trim(names(1)) == "gvec/case/parameter"
        if (case_matches) then
            n_passed = n_passed + 1
            write(output_unit, '(A)') "✓ test_gvec_parameter_cases_are_discovered"
        else
            write(error_unit, '(A)') "✗ test_gvec_parameter_cases_are_discovered"
        end if

        call runner%finalize()
        call repo_manager%finalize()
        call execute_command_line("rm -rf " // base_dir, exitstat=stat)
    end subroutine test_gvec_parameter_cases_are_discovered

    subroutine test_empty_case_match_does_not_filter(n_tests, n_passed)
        integer, intent(inout) :: n_tests, n_passed
        type(repository_manager_t) :: repo_manager
        type(benchmark_runner_t) :: runner
        character(len=256), allocatable :: names(:)
        character(len=*), parameter :: base_dir = "/tmp/benchmark_vmec_empty_match"
        integer :: stat

        n_tests = n_tests + 1

        call execute_command_line("rm -rf " // base_dir, exitstat=stat)
        call execute_command_line("mkdir -p " // base_dir // "/educational_VMEC/.git", exitstat=stat)
        call execute_command_line("mkdir -p " // base_dir // "/educational_VMEC/test/examples", exitstat=stat)
        call execute_command_line("mkdir -p " // base_dir // "/VMEC2000/.git", exitstat=stat)
        call execute_command_line("mkdir -p " // base_dir // "/VMEC2000/test/examples", exitstat=stat)
        call execute_command_line("touch " // base_dir // &
            "/educational_VMEC/test/examples/input.circular_tokamak", exitstat=stat)
        call execute_command_line("touch " // base_dir // &
            "/VMEC2000/test/examples/input.li383_low_res", exitstat=stat)

        call repo_manager%initialize(base_dir)
        call runner%initialize(base_dir // "/results", repo_manager)
        call runner%discover_test_cases(case_match="")
        names = runner%get_test_case_names()

        if (size(names) == 2 .and. &
            trim(names(1)) == "educational_VMEC/circular_tokamak" .and. &
            trim(names(2)) == "VMEC2000/li383_low_res") then
            n_passed = n_passed + 1
            write(output_unit, '(A)') "✓ test_empty_case_match_does_not_filter"
        else
            write(error_unit, '(A)') "✗ test_empty_case_match_does_not_filter"
        end if

        call runner%finalize()
        call repo_manager%finalize()
        call execute_command_line("rm -rf " // base_dir, exitstat=stat)
    end subroutine test_empty_case_match_does_not_filter

    subroutine test_literal_empty_case_match_does_not_filter(n_tests, n_passed)
        integer, intent(inout) :: n_tests, n_passed
        type(repository_manager_t) :: repo_manager
        type(benchmark_runner_t) :: runner
        character(len=256), allocatable :: names(:)
        character(len=*), parameter :: base_dir = "/tmp/benchmark_vmec_literal_empty_match"
        integer :: stat

        n_tests = n_tests + 1

        call execute_command_line("rm -rf " // base_dir, exitstat=stat)
        call execute_command_line("mkdir -p " // base_dir // "/educational_VMEC/.git", exitstat=stat)
        call execute_command_line("mkdir -p " // base_dir // "/educational_VMEC/test/examples", exitstat=stat)
        call execute_command_line("touch " // base_dir // &
            "/educational_VMEC/test/examples/input.circular_tokamak", exitstat=stat)

        call repo_manager%initialize(base_dir)
        call runner%initialize(base_dir // "/results", repo_manager)
        call runner%discover_test_cases(case_match='""')
        names = runner%get_test_case_names()

        if (size(names) == 1 .and. trim(names(1)) == "educational_VMEC/circular_tokamak") then
            n_passed = n_passed + 1
            write(output_unit, '(A)') "✓ test_literal_empty_case_match_does_not_filter"
        else
            write(error_unit, '(A)') "✗ test_literal_empty_case_match_does_not_filter"
        end if

        call runner%finalize()
        call repo_manager%finalize()
        call execute_command_line("rm -rf " // base_dir, exitstat=stat)
    end subroutine test_literal_empty_case_match_does_not_filter

    subroutine test_custom_output_dir_for_jvmec_reports(n_tests, n_passed)
        integer, intent(inout) :: n_tests, n_passed
        type(results_comparator_t) :: comparator
        type(vmec_result_t) :: result
        character(len=*), parameter :: output_dir = "/tmp/benchmark_vmec_results_comparator"
        character(len=*), parameter :: report_file = output_dir // "/comparison_report.md"
        character(len=*), parameter :: jvmec_report = output_dir // &
            "/jvmec_reports/jvmec_quantitative_educational_VMEC__from_vmec_multiple_readin__li383_low_res.md"
        logical :: report_exists, jvmec_report_exists
        integer :: stat

        n_tests = n_tests + 1

        call execute_command_line("rm -rf " // output_dir, exitstat=stat)
        call comparator%initialize(2, output_dir)

        call result%clear()
        result%success = .true.
        result%raxis_cc = 1.0_real64

        call comparator%add_result("educational_VMEC/from_vmec_multiple_readin/li383_low_res", &
            "educational_vmec", result)
        call comparator%generate_report(report_file)

        inquire(file=report_file, exist=report_exists)
        inquire(file=jvmec_report, exist=jvmec_report_exists)

        if (report_exists .and. jvmec_report_exists) then
            n_passed = n_passed + 1
            write(output_unit, '(A)') "✓ test_custom_output_dir_for_jvmec_reports"
        else
            write(error_unit, '(A)') "✗ test_custom_output_dir_for_jvmec_reports"
        end if

        call comparator%finalize()
        call execute_command_line("rm -rf " // output_dir, exitstat=stat)
    end subroutine test_custom_output_dir_for_jvmec_reports

    subroutine test_report_uses_successful_reference(n_tests, n_passed)
        integer, intent(inout) :: n_tests, n_passed
        type(results_comparator_t) :: comparator
        type(vmec_result_t) :: failed_result, success_result
        character(len=*), parameter :: output_dir = "/tmp/benchmark_vmec_reporting_reference"
        character(len=*), parameter :: report_file = output_dir // "/comparison_report.md"
        character(len=*), parameter :: case_name = &
            "educational_VMEC/from_booz_xform/LandremanSenguptaPlunk_section5p3"
        integer :: stat

        n_tests = n_tests + 1

        call execute_command_line("rm -rf " // output_dir, exitstat=stat)
        call comparator%initialize(2, output_dir)

        call failed_result%clear()
        failed_result%success = .false.
        failed_result%error_message = "failed"

        call success_result%clear()
        success_result%success = .true.
        success_result%wb = 1.0_real64
        success_result%betatotal = 2.0_real64

        call comparator%add_result(case_name, "educational_vmec", failed_result)
        call comparator%add_result(case_name, "vmec2000", success_result)
        call comparator%generate_report(report_file)

        if (file_contains(report_file, case_name) .and. &
            file_contains(report_file, "Reference implementation: vmec2000") .and. &
            .not. file_contains(report_file, "Reference implementation: educational_vmec")) then
            n_passed = n_passed + 1
            write(output_unit, '(A)') "✓ test_report_uses_successful_reference"
        else
            write(error_unit, '(A)') "✗ test_report_uses_successful_reference"
        end if

        call comparator%finalize()
        call execute_command_line("rm -rf " // output_dir, exitstat=stat)
    end subroutine test_report_uses_successful_reference

    subroutine test_report_prefers_educational_reference_over_jvmec(n_tests, n_passed)
        integer, intent(inout) :: n_tests, n_passed
        type(results_comparator_t) :: comparator
        type(vmec_result_t) :: educational_result, jvmec_result, vmecpp_result
        character(len=*), parameter :: output_dir = "/tmp/benchmark_vmec_reporting_priority"
        character(len=*), parameter :: report_file = output_dir // "/comparison_report.md"
        character(len=*), parameter :: case_name = &
            "educational_VMEC/from_booz_xform/up_down_asymmetric_tokamak"
        integer :: stat

        n_tests = n_tests + 1

        call execute_command_line("rm -rf " // output_dir, exitstat=stat)
        call comparator%initialize(3, output_dir)

        call educational_result%clear()
        educational_result%success = .true.
        educational_result%wb = 10.0_real64

        call jvmec_result%clear()
        jvmec_result%success = .true.
        jvmec_result%wb = 11.0_real64

        call vmecpp_result%clear()
        vmecpp_result%success = .true.
        vmecpp_result%wb = 10.1_real64

        call comparator%add_result(case_name, "jvmec", jvmec_result)
        call comparator%add_result(case_name, "educational_vmec", educational_result)
        call comparator%add_result(case_name, "vmecpp", vmecpp_result)
        call comparator%generate_report(report_file)

        if (file_contains(report_file, "Reference priority: educational_vmec, vmec2000, vmex, jvmec, vmecpp, desc, gvec") .and. &
            file_contains(report_file, "Reference implementation: educational_vmec") .and. &
            .not. file_contains(report_file, "Reference implementation: jvmec")) then
            n_passed = n_passed + 1
            write(output_unit, '(A)') "✓ test_report_prefers_educational_reference_over_jvmec"
        else
            write(error_unit, '(A)') "✗ test_report_prefers_educational_reference_over_jvmec"
        end if

        call comparator%finalize()
        call execute_command_line("rm -rf " // output_dir, exitstat=stat)
    end subroutine test_report_prefers_educational_reference_over_jvmec

    subroutine test_report_separates_physical_domains(n_tests, n_passed)
        integer, intent(inout) :: n_tests, n_passed
        type(results_comparator_t) :: comparator
        type(vmec_result_t) :: vmec_result, freegs_result
        character(len=*), parameter :: output_dir = "/tmp/benchmark_vmec_reporting_domains"
        character(len=*), parameter :: report_file = output_dir // "/comparison_report.md"
        integer :: stat

        n_tests = n_tests + 1
        call execute_command_line("rm -rf " // output_dir, exitstat=stat)
        call comparator%initialize(1, output_dir)

        call vmec_result%clear()
        vmec_result%success = .true.
        vmec_result%family = "vmec_family"
        vmec_result%dimension = 3
        vmec_result%wb = 1.0_real64
        call freegs_result%clear()
        freegs_result%success = .true.
        freegs_result%family = "grad_shafranov"
        freegs_result%dimension = 2
        freegs_result%pressure_axis = 1000.0_real64

        call comparator%add_result("cases/analytic/2d_solovev", "educational_vmec", vmec_result)
        call comparator%add_result("cases/analytic/2d_solovev", "freegs", freegs_result)
        call comparator%generate_report(report_file)

        if (file_contains(report_file, "freegs | n/a") .and. &
            .not. file_contains(report_file, "**freegs**:")) then
            n_passed = n_passed + 1
            write(output_unit, '(A)') "✓ test_report_separates_physical_domains"
        else
            write(error_unit, '(A)') "✗ test_report_separates_physical_domains"
        end if

        call comparator%finalize()
        call execute_command_line("rm -rf " // output_dir, exitstat=stat)
    end subroutine test_report_separates_physical_domains

    logical function file_contains(path, needle)
        character(len=*), intent(in) :: path
        character(len=*), intent(in) :: needle
        character(len=512) :: line
        integer :: unit, stat

        file_contains = .false.

        open(newunit=unit, file=path, status='old', action='read', iostat=stat)
        if (stat /= 0) return

        do
            read(unit, '(A)', iostat=stat) line
            if (stat /= 0) exit
            if (index(line, needle) > 0) then
                file_contains = .true.
                exit
            end if
        end do

        close(unit)
    end function file_contains

end program test_runner_reporting
