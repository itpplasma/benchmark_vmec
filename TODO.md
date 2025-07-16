# TODO.md

## High Priority

- [ ] Implement physics comparison functionality
  - [ ] Compare magnetic field strength profiles
  - [ ] Compare pressure profiles
  - [ ] Compare rotational transform profiles
  - [ ] Calculate relative differences between implementations

- [ ] Generate meaningful comparison reports
  - [ ] Plots of profile comparisons (if plotting library available)
  - [ ] Summary statistics (mean differences, max differences)

## Medium Priority

- [ ] Add support for parallel execution of test cases
- [ ] Add progress bars for long-running benchmarks
- [ ] Implement caching of results to avoid re-running completed cases
- [ ] Add more detailed timing information for performance comparison

## Low Priority

- [ ] Add support for custom test case directories
- [ ] Implement result visualization tools
- [ ] Add support for regression testing against reference results
- [ ] Create a web-based dashboard for results viewing

## Completed

- [x] Fix test case discovery limit=0 bug
- [x] Fix jVMEC main class configuration
- [x] Fix VMEC2000 build and runtime issues
- [x] Fix VMEC++ to use standalone executable
- [x] Exclude jVMEC test cases by default
- [x] Document jVMEC limitations as test framework
- [x] Implement results extraction from output files
  - [x] Read NetCDF wout files for Educational VMEC and VMEC2000
  - [x] Read HDF5 output files for VMEC++
  - [x] Extract key physics quantities (wb, betatotal, aspect ratio, etc.)
  - [x] Handle missing output files gracefully
- [x] Generate tabular comparison of key scalar quantities
- [x] Add HDF5 metapackage support with --link-flag for Arch Linux
- [x] Fix VMEC2000 to handle non-convergent cases gracefully
- [x] Test all implementations with multiple test cases