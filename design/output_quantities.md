# Output Quantities - Asymmetric Computations

This document analyzes how output quantities are computed for asymmetric equilibria in VMEC++.

## Overview

The Output Quantities module computes derived physical quantities from the converged equilibrium solution. For asymmetric mode, special handling is required for magnetic field components and spectral filtering.

## Modified Functions

### 1. `DecomposeCovariantBBySymmetry()`

**Purpose**: Decompose covariant magnetic field components by symmetry

**Changes for Asymmetric Mode**:
```cpp
// Original symmetric indexing
idx_cc = js * sizes.mnmax + imn;

// Modified for asymmetric arrays
// The indexing now accounts for different array layouts
// when processing asymmetric Fourier components
```

**Issue**: The exact nature of the indexing change needs verification against educational_VMEC.

### 2. `LowPassFilterCovariantB()`

**Purpose**: Apply spectral filtering to magnetic field components

**Changes for Asymmetric Mode**:
```cpp
// Handle additional asymmetric components
if (sizes.lasym) {
    // Filter bsupumnc, bsupvmnc (asymmetric components)
    // These are the cosine components that only exist in asymmetric mode
}
```

## Asymmetric Output Arrays

### Magnetic Field Components

**Symmetric mode**:
- `bsupumns` - B^u sine components
- `bsupvmns` - B^v sine components
- `bmnc` - |B| cosine components

**Asymmetric mode adds**:
- `bsupumnc` - B^u cosine components
- `bsupvmnc` - B^v cosine components
- `bmns` - |B| sine components

### Current Density Components

Similar pattern for current density arrays.

## Comparison with Educational_VMEC

### Educational_VMEC (bcovar.f90)

```fortran
! Symmetric components
DO js = 2, ns
   DO mn = 1, mnmax
      bsubumns(mn,js) = ...
      bsubvmns(mn,js) = ...
   END DO
END DO

! Asymmetric components
IF (lasym) THEN
   DO js = 2, ns
      DO mn = 1, mnmax
         bsubumnc(mn,js) = ...
         bsubvmnc(mn,js) = ...
      END DO
   END DO
END IF
```

### VMEC++ Implementation

The implementation follows a similar pattern but with C++ data structures and different array layouts.

## Key Implementation Details

### 1. Symmetry Decomposition

The magnetic field is decomposed into symmetric and anti-symmetric parts:
- Symmetric: Even under stellarator symmetry operation
- Anti-symmetric: Odd under stellarator symmetry operation

### 2. Spectral Filtering

Low-pass filtering removes high-frequency modes that may be numerical artifacts:
```cpp
if (m > mfilter || n > nfilter) {
    coefficient = 0.0;  // Zero out high modes
}
```

### 3. Array Indexing

**Critical**: The array indexing for asymmetric components must match the convention used in force calculations and input/output routines.

## Verification Points

1. **Index Mapping**: Verify array indices match between implementations
2. **Symmetry Operations**: Check decomposition formulas
3. **Filter Cutoffs**: Ensure same modes are filtered
4. **Sign Conventions**: Validate signs of asymmetric components

## Known Issues

1. **Documentation**: The exact indexing changes are not well documented
2. **Testing**: Limited test coverage for asymmetric output quantities
3. **Performance**: Redundant calculations in symmetry decomposition

## Testing Strategy

1. Compare output arrays between implementations for test cases
2. Verify symmetry properties of decomposed fields
3. Test filtering with known spectral content
4. Check conservation properties (e.g., flux conservation)

## Physical Quantities Affected

1. **Magnetic Field Strength**: |B| now has sine components
2. **Field Line Curvature**: Additional terms from asymmetric B
3. **Current Density**: Full 3D current pattern
4. **Rotational Transform**: Modified by asymmetric shear

## Implementation Notes

The changes in this module are relatively minor compared to the force calculation modules, but they are critical for correct output of physical quantities in asymmetric equilibria.