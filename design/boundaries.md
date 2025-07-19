# Boundaries - Asymmetric Mode Handling

This document analyzes the boundary condition handling for asymmetric mode across the three VMEC implementations.

## Overview

The Boundaries class/module handles the plasma-vacuum interface geometry and is responsible for:
1. Computing boundary harmonics from input coefficients
2. Checking Jacobian sign consistency
3. Triggering axis recovery when needed

## New Functions Added in VMEC++

### 1. `checkSignOfJacobianOriginal()`

**Purpose**: Original method for checking Jacobian sign using cross products

**Implementation**:
```cpp
bool Boundaries::checkSignOfJacobianOriginal() {
    // Compute Jacobian at multiple theta points
    // Check if all have consistent sign
    // Return true if consistent
}
```

### 2. `checkSignOfJacobianPolygonArea()`

**Purpose**: Alternative polygon-based method for Jacobian sign check

**Implementation**:
```cpp
bool Boundaries::checkSignOfJacobianPolygonArea() {
    // Compute polygon area from boundary points
    // Use shoelace formula
    // More robust for highly shaped plasmas
}
```

## Modified Functions

### `RecomputeMagneticAxisToFixJacobianSign()`

**Changes**: Added debug output only (no algorithmic changes)

## Asymmetric Boundary Handling

### Input Arrays

**Symmetric mode** (lasym=false):
- `rbc(n,m)` - R boundary cosine coefficients
- `zbs(n,m)` - Z boundary sine coefficients

**Asymmetric mode** (lasym=true) adds:
- `rbs(n,m)` - R boundary sine coefficients  
- `zbc(n,m)` - Z boundary cosine coefficients

### Educational_VMEC Implementation

In `convert.f90` and `readin.f90`:
```fortran
DO m = 0, mpol
   DO n = -ntor, ntor
      IF (lasym) THEN
         rmn = rbc(n,m)*cosmu + rbs(n,m)*sinmu
         zmn = zbc(n,m)*cosmu + zbs(n,m)*sinmu
      ELSE
         rmn = rbc(n,m)*cosmu
         zmn = zbs(n,m)*sinmu
      END IF
   END DO
END DO
```

### VMEC++ Implementation

The boundary coefficients are handled in:
1. Input parsing (`vmec_indata.cc`)
2. Fourier evaluation (`boundaries.cc`)
3. Axis recovery (`guess_magnetic_axis.cc`)

### jVMEC Implementation

Similar structure to educational_VMEC with object-oriented design.

## Key Differences

### 1. Jacobian Checking Methods

**educational_VMEC**: Single method based on cross products

**VMEC++**: Two methods available:
- Original cross-product method
- Polygon area method (more robust)

**jVMEC**: Similar to educational_VMEC

### 2. Array Storage

**educational_VMEC**: 
- Arrays in modules
- Fixed size allocation

**VMEC++**:
- STL vectors in class
- Dynamic sizing

**jVMEC**:
- Java arrays
- Dynamic allocation

### 3. Symmetry Handling

All three implementations properly handle the additional sine/cosine terms for asymmetric boundaries, but the implementation details differ in terms of where the logic resides.

## Verification Points

1. **Coefficient Mapping**: Ensure rbs/zbc arrays are correctly mapped from input
2. **Fourier Evaluation**: Verify boundary shape is correctly computed
3. **Jacobian Sign**: Both methods should give consistent results
4. **Axis Recovery**: Check that asymmetric boundaries trigger correct recovery

## Known Issues

1. **Polygon Method**: Not extensively tested with asymmetric cases
2. **Debug Output**: Current implementation has extensive debug prints

## Testing Strategy

1. Compare boundary shapes between implementations
2. Test Jacobian sign methods on various asymmetric configurations
3. Verify axis recovery triggers appropriately
4. Check boundary derivatives for force calculations