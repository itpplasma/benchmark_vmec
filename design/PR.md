# PR 360 vs PR 359 Comparison and Analysis

This document analyzes the differences between PR 359 and PR 360 on proximafusion/vmecpp, and compares our current implementation with both.

## Overview of PRs

- **PR 359**: Base asymmetric implementation (what we originally analyzed)
- **PR 360**: Improved asymmetric implementation with fixes and enhancements

## Key Changes from PR 359 to PR 360

### 1. Python Wrapper Improvements (`vmec_indata_pywrapper.cc`)

**Major Bug Fix**: PR 360 fixes a critical initialization issue in the Python wrapper.

**PR 359 Problem**:
```cpp
// Conditional allocation with fallback to zeros
if (indata.rbs.size() == static_cast<size_t>(mpol * (2 * ntor + 1))) {
  rbs = ToEigenMatrix(indata.rbs, mpol, 2 * ntor + 1);
} else {
  // Initialize with zeros if not properly allocated
  rbs = RowMatrixXd::Zero(mpol, 2 * ntor + 1);
}
```

**PR 360 Fix**:
```cpp
// Direct assignment - assumes proper allocation
rbs = ToEigenMatrix(indata.rbs, mpol, 2 * ntor + 1);
zbc = ToEigenMatrix(indata.zbc, mpol, 2 * ntor + 1);
```

**Improved SetMpolNtor Logic**:
- Better handling of array initialization when `lasym=true`
- Proper detection when asymmetric arrays need initialization
- More robust resize logic

### 2. Output Quantities Fix (`output_quantities.cc`)

**Bug Fix**: Corrected array indexing in covariant B field computation.

**PR 359 Bug**:
```cpp
bsubsmn3 += tcosi1 * decomposed_bcov.bsubs_a(jF, kl);  // Wrong indexing
bsubsmn4 += tcosi2 * decomposed_bcov.bsubs_a(jF, kl);  // Wrong indexing
```

**PR 360 Fix**:
```cpp
bsubsmn3 += tcosi1 * decomposed_bcov.bsubs_a(source_index);  // Correct
bsubsmn4 += tcosi2 * decomposed_bcov.bsubs_a(source_index);  // Correct
```

### 3. Example Input File

**PR 360 Added**: Complete asymmetric input file `examples/data/input.up_down_asymmetric_tokamak`

**Features**:
- Properly formatted INDATA namelist
- Asymmetric boundary coefficients (`RBS` terms)
- Comments explaining the test case
- Convergence parameters tuned for asymmetric mode

### 4. Python Interface (`__init__.py`)

**Added**: Version information and imports for asymmetric support.

### 5. Test Suite

**PR 360 Added**: `tests/test_asymmetric_loading.py`
- Tests for asymmetric array loading
- Python wrapper validation
- Input/output consistency checks

## Our Current Implementation vs PR 360

### Major Differences

1. **Debug Output**: We added extensive debug output to `guess_magnetic_axis.cc` that's not in PR 360
2. **Input File**: Our input file has different formatting/comments
3. **Additional Files**: We have many debugging and analysis files not in PR 360

### Critical Analysis

**PR 360 is Superior Because**:
1. **Cleaner Code**: No debug output cluttering the implementation
2. **Better Testing**: Includes proper test suite for asymmetric mode
3. **Bug Fixes**: Fixes the array indexing bug in output quantities
4. **Robust Python Interface**: Better initialization logic

**Our Changes That Should Be Preserved**:
1. **Axis Recovery Debug**: Our debug output helped identify the tie-breaking issue
2. **Analysis Infrastructure**: Our documentation and analysis files

## Recommended Action Plan

### 1. Rebase onto PR 360
PR 360 should be our base since it has important bug fixes and improvements that PR 359 lacks.

### 2. Selective Cherry-picking
From our current work, preserve only:
- Debug output from `guess_magnetic_axis.cc` (temporarily, for development)
- Documentation files in `benchmark_vmec/design/`
- Analysis scripts (if needed for verification)

### 3. What to Discard
- Duplicate input files with different formatting
- Temporary debugging files
- Any changes that are already fixed in PR 360

## Summary of Key Findings

1. **PR 360 has critical bug fixes** that PR 359 lacks, especially in:
   - Python wrapper initialization
   - Output quantities array indexing
   
2. **Our work was based on PR 359**, so we may have worked around bugs that are already fixed in PR 360

3. **We should rebase on PR 360** to get the latest fixes and improvements

4. **Our debug output in guess_magnetic_axis.cc** was valuable for identifying the tie-breaking issue but should be cleaned up

5. **The documentation work we did** is valuable and should be preserved

## Next Steps

1. **Fetch PR 360** as the new base
2. **Identify which of our changes are still needed** after PR 360's fixes
3. **Clean up debug output** to only essential items
4. **Test convergence** on the asymmetric test case with PR 360 base
5. **Preserve our analysis documentation**