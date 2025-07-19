# Ideal MHD Model - Asymmetric Integration

This document analyzes how the asymmetric mode is integrated into the main force computation in the Ideal MHD Model across three VMEC implementations.

## Overview

The Ideal MHD Model is responsible for computing the force balance F = J × B - ∇p in VMEC. For asymmetric equilibria, this requires handling additional Fourier harmonics and symmetry operations.

## Function Modifications for Asymmetric Mode

### 1. Constructor: `IdealMhdModel::IdealMhdModel()`

**VMEC++ Changes**:
```cpp
// Allocate asymmetric arrays if needed
if (s_.lasym) {
    r1_a.assign(nrzt1, 0.0);
    ru_a.assign(nrzt1, 0.0);
    z1_a.assign(nrzt1, 0.0);
    zu_a.assign(nrzt1, 0.0);
    lu_a.assign(nrzt1, 0.0);
    if (s_.lthreed) {
        rv_a.assign(nrzt1, 0.0);
        zv_a.assign(nrzt1, 0.0);
        lv_a.assign(nrzt1, 0.0);
    }
}
```

**educational_VMEC (funct3d.f90)**:
Arrays are allocated in module initialization based on `lasym` flag.

**jVMEC**:
Dynamic allocation in constructor when `lasym=true`.

### 2. Geometry Transformation: `geometryFromFourier()`

**VMEC++ Implementation**:
```cpp
void IdealMhdModel::geometryFromFourier() {
    // Symmetric transforms (always done)
    if (s_.lthreed) {
        dft_FourierToReal_3d_symm(physical_x);
    } else {
        dft_FourierToReal_2d_symm(physical_x);
    }
    
    // Asymmetric transforms (if lasym)
    if (s_.lasym) {
        auto geometry_asym = RealSpaceGeometryAsym{...};
        if (s_.lthreed) {
            FourierToReal3DAsymmFastPoloidal(...);
        } else {
            FourierToReal2DAsymmFastPoloidal(...);
        }
        // Symmetrize geometry
        SymmetrizeRealSpaceGeometry(...);
    }
}
```

**educational_VMEC (funct3d.f90)**:
```fortran
CALL totzsps(...) ! Symmetric transform
IF (lasym) THEN
    CALL totzspa(...) ! Asymmetric transform
    CALL symrzl(...) ! Symmetrize
END IF
```

### 3. Force Transformation: `forcesToFourier()`

**VMEC++ Implementation**:
```cpp
void IdealMhdModel::forcesToFourier() {
    // Transform symmetric forces
    if (s_.lthreed) {
        dft_RealToFourier_3d_symm(...);
    } else {
        dft_RealToFourier_2d_symm(...);
    }
    
    // Transform asymmetric forces
    if (s_.lasym) {
        auto forces_asym = ForcesAsym{...};
        if (s_.lthreed) {
            ForcesToFourier3DAsymmFastPoloidal(...);
        } else {
            ForcesToFourier2DAsymmFastPoloidal(...);
        }
    }
}
```

## New Functions Added

### 1. `dft_FourierToReal_3d_asymm()`
- Performs DFT for asymmetric Fourier coefficients
- Equivalent to part of educational_VMEC's `totzspa`

### 2. `dft_FourierToReal_2d_asymm()`
- 2D (axisymmetric) version of asymmetric DFT
- Handles ntor=0 case

### 3. `symrzl()`
- Applies symmetry operations to combine symmetric and asymmetric geometry
- Direct equivalent of educational_VMEC's `symrzl` subroutine

## Key Implementation Differences

### 1. File Organization
- **educational_VMEC**: All code in `funct3d.f90` with conditional blocks
- **VMEC++**: Asymmetric functions split into `fourier_asymmetric.cc`
- **jVMEC**: Methods in same class but separate implementations

### 2. Array Management
- **educational_VMEC**: Module-level arrays with conditional allocation
- **VMEC++**: Class member arrays allocated in constructor
- **jVMEC**: Dynamic allocation based on mode

### 3. Function Calls
- **educational_VMEC**: Direct subroutine calls with IF blocks
- **VMEC++**: Function pointers/virtual dispatch could be used but aren't
- **jVMEC**: Conditional method calls

## Verification Points

1. **Array Initialization**: Verify all asymmetric arrays are properly zero-initialized
2. **Transform Consistency**: Ensure DFT implementations match between codes
3. **Symmetrization**: Verify `symrzl` logic is identical
4. **Force Handling**: Check that asymmetric forces are correctly integrated

## Known Issues

1. **Memory Overhead**: VMEC++ always allocates HandoverStorage arrays even for symmetric cases
2. **Code Duplication**: Some DFT logic is duplicated between symmetric/asymmetric paths

## Testing Strategy

1. Run symmetric case with lasym=true and zero asymmetric coefficients
2. Compare forces at each iteration between implementations
3. Verify symmetrization produces expected results
4. Test with known asymmetric equilibria