# Handover Storage - Asymmetric Memory Management

This document analyzes the HandoverStorage class that manages memory for asymmetric arrays in VMEC++.

## Overview

HandoverStorage is a VMEC++-specific class that manages arrays shared between different computational modules. For asymmetric mode, it handles the additional Fourier coefficient arrays.

## New Asymmetric Arrays

### Added Member Variables

```cpp
// Input (from geometry calculation)
std::vector<double> rmnsc_i, rmncs_i;  // R sine terms
std::vector<double> zmncc_i, zmnss_i;  // Z cosine terms  
std::vector<double> lmncc_i, lmnss_i;  // λ cosine terms

// Output (from force calculation)
std::vector<double> rmnsc_o, rmncs_o;  // R sine terms
std::vector<double> zmncc_o, zmnss_o;  // Z cosine terms
std::vector<double> lmncc_o, lmnss_o;  // λ cosine terms
```

### Modified `allocate()` Function

```cpp
void HandoverStorage::allocate(const Sizes& s) {
    // ... existing symmetric allocations ...
    
    // NEW: Asymmetric array allocation
    if (s.lasym) {
        const int size = (s.ns + 1) * s.mnmax;
        
        // Input arrays
        rmnsc_i.resize(size, 0.0);
        rmncs_i.resize(size, 0.0);
        zmncc_i.resize(size, 0.0);
        zmnss_i.resize(size, 0.0);
        lmncc_i.resize(size, 0.0);
        lmnss_i.resize(size, 0.0);
        
        // Output arrays  
        rmnsc_o.resize(size, 0.0);
        rmncs_o.resize(size, 0.0);
        zmncc_o.resize(size, 0.0);
        zmnss_o.resize(size, 0.0);
        lmncc_o.resize(size, 0.0);
        lmnss_o.resize(size, 0.0);
    }
}
```

## Comparison with Other Implementations

### Educational_VMEC

Uses module-level arrays in `xstuff.f90`:
```fortran
MODULE xstuff
  ! Asymmetric arrays
  REAL(rprec), ALLOCATABLE :: rmnsc(:,:,:), zmncc(:,:,:), lmncc(:,:,:)
  REAL(rprec), ALLOCATABLE :: rmncs(:,:,:), zmnss(:,:,:), lmnss(:,:,:)
END MODULE
```

### jVMEC

Arrays are part of the main data structures, allocated dynamically based on `lasym`.

### VMEC++ Design Rationale

HandoverStorage serves as a central memory pool to:
1. Avoid passing many arrays between functions
2. Ensure consistent memory layout
3. Facilitate data sharing with external modules (e.g., NESTOR)

## Memory Layout

### Array Dimensions

- **Size**: `(ns + 1) × mnmax` where `mnmax = (mpol + 1) × (2*ntor + 1)`
- **Indexing**: Flattened 1D with index = `js * mnmax + mn`
- **Initialization**: All arrays zero-initialized

### Input vs Output Arrays

- **Input (_i)**: Used for geometry → force calculations
- **Output (_o)**: Results from force calculations

## Key Design Differences

### 1. Centralized vs Distributed

**educational_VMEC**: Arrays in various modules
**VMEC++**: Centralized in HandoverStorage
**jVMEC**: Object-oriented encapsulation

### 2. Allocation Strategy

**educational_VMEC**: Conditional allocation
**VMEC++**: Always allocate container, conditionally resize
**jVMEC**: Dynamic allocation

### 3. Memory Overhead

VMEC++ approach has slight overhead:
- Empty vectors for symmetric cases
- But simplifies code flow

## Usage Pattern

```cpp
// In force calculation
if (s.lasym) {
    // Read from input arrays
    processAsymmetricGeometry(h.rmnsc_i, h.zmncc_i, ...);
    
    // Write to output arrays
    computeAsymmetricForces(h.rmnsc_o, h.zmncc_o, ...);
}
```

## Verification Points

1. **Size Calculation**: Verify `(ns+1) × mnmax` is correct
2. **Zero Initialization**: Ensure arrays start clean
3. **Index Mapping**: Validate flattened indexing scheme
4. **Memory Access**: Check bounds in debug mode

## Potential Issues

1. **Memory Usage**: All arrays allocated even if not all modes used
2. **Cache Performance**: Flattened layout may not be optimal
3. **Debugging**: Harder to inspect than multi-dimensional arrays

## Testing Strategy

1. Verify allocation sizes match expected values
2. Test with various ns, mpol, ntor combinations
3. Check memory access patterns for efficiency
4. Validate data transfer between modules