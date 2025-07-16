# TODO.md

## High Priority

- [ ] Implement results extraction from output files
  - [ ] Read NetCDF wout files for Educational VMEC and VMEC2000
  - [ ] Read HDF5 output files for VMEC++
  - [ ] Extract key physics quantities (wb, betatotal, aspect ratio, etc.)
  - [ ] Handle missing output files gracefully

- [ ] Implement physics comparison functionality
  - [ ] Compare magnetic field strength profiles
  - [ ] Compare pressure profiles
  - [ ] Compare rotational transform profiles
  - [ ] Calculate relative differences between implementations

- [ ] Generate meaningful comparison reports
  - [ ] Tabular comparison of key scalar quantities
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