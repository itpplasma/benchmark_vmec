# Fourier Coefficients - Asymmetric Array Handling

This document analyzes how Fourier coefficient arrays are managed for asymmetric mode across the three VMEC implementations.

## Overview

The Fourier Coefficients module/class manages the spectral representation of the equilibrium quantities. In asymmetric mode, additional arrays are needed for sine terms of R and cosine terms of Z.

## Array Structure

### Symmetric Mode Arrays

**Always present**:
- `rmncc` - R(s,m,n) cosine-cosine coefficients
- `zmnsc` - Z(s,m,n) sine-cosine coefficients  
- `lmnsc` - λ(s,m,n) sine-cosine coefficients
- `rmnss` - R(s,m,n) sine-sine coefficients (3D only)
- `zmncs` - Z(s,m,n) cosine-sine coefficients (3D only)
- `lmncs` - λ(s,m,n) cosine-sine coefficients (3D only)

### Asymmetric Mode Arrays

**Additional arrays when lasym=true**:
- `rmnsc` - R(s,m,n) sine-cosine coefficients
- `zmncc` - Z(s,m,n) cosine-cosine coefficients
- `lmncc` - λ(s,m,n) cosine-cosine coefficients
- `rmncs` - R(s,m,n) cosine-sine coefficients (3D only)
- `zmnss` - Z(s,m,n) sine-sine coefficients (3D only)
- `lmnss` - λ(s,m,n) sine-sine coefficients (3D only)

## Implementation Comparison

### Educational_VMEC (xstuff.f90)

```fortran
MODULE xstuff
  REAL(rprec), DIMENSION(:,:,:), ALLOCATABLE :: &
     rmncc, zmnsc, lmnsc  ! Symmetric arrays
  
  ! Asymmetric arrays (allocated if lasym)
  REAL(rprec), DIMENSION(:,:,:), ALLOCATABLE :: &
     rmnsc, zmncc, lmncc  ! Anti-symmetric arrays
END MODULE
```

Allocation in `allocate_ns`:
```fortran
IF (lasym) THEN
   ALLOCATE(rmnsc(ns,0:ntor,0:mpol1), &
            zmncc(ns,0:ntor,0:mpol1), &
            lmncc(ns,0:ntor,0:mpol1))
END IF
```

### VMEC++ Implementation

**Modified in constructor**:
```cpp
FourierCoeffs::FourierCoeffs(const Sizes& s, ...) {
    // Symmetric arrays - always allocated
    rmncc.resize(nRadialTotal * nFourierTotal);
    zmnsc.resize(nRadialTotal * nFourierTotal);
    lmnsc.resize(nRadialTotal * nFourierTotal);
    
    // CHANGE: Initialize to zero (was uninitialized before)
    std::fill(rmncc.begin(), rmncc.end(), 0.0);
    std::fill(zmnsc.begin(), zmnsc.end(), 0.0);
    std::fill(lmnsc.begin(), lmnsc.end(), 0.0);
    
    // Asymmetric arrays handled in HandoverStorage
}
```

**Key Change**: Arrays are now zero-initialized instead of left uninitialized.

### jVMEC Implementation

```java
public class FourierCoefficients {
    double[][][] rmncc, zmnsc, lmnsc;  // Symmetric
    double[][][] rmnsc, zmncc, lmncc;  // Asymmetric (if lasym)
    
    public FourierCoefficients(Sizes sizes) {
        // Allocate based on lasym flag
        if (sizes.lasym) {
            rmnsc = new double[ns][ntor+1][mpol+1];
            // etc.
        }
    }
}
```

## Key Differences

### 1. Memory Management

**educational_VMEC**: 
- Conditional allocation based on `lasym`
- Module-level arrays

**VMEC++**:
- Asymmetric arrays in HandoverStorage, not FourierCoeffs
- Always zero-initialized (bug fix)

**jVMEC**:
- Conditional allocation in constructor
- Java manages memory

### 2. Array Layout

**educational_VMEC**: Fortran column-major `(ns, 0:ntor, 0:mpol1)`

**VMEC++**: Flattened 1D array with index calculation

**jVMEC**: Java 3D arrays `[ns][ntor+1][mpol+1]`

### 3. Initialization

**educational_VMEC**: Arrays not explicitly initialized (compiler-dependent)

**VMEC++**: Now explicitly zero-initialized (important fix!)

**jVMEC**: Java zero-initializes by default

## Important Bug Fix

The change to zero-initialize arrays in VMEC++ is critical:
```cpp
// OLD: Uninitialized memory could contain garbage
rmncc.resize(size);

// NEW: Proper initialization
rmncc.resize(size);
std::fill(rmncc.begin(), rmncc.end(), 0.0);
```

This prevents undefined behavior from uninitialized memory.

## Verification Points

1. **Array Allocation**: Verify asymmetric arrays are allocated when needed
2. **Initialization**: Ensure all arrays start at zero
3. **Index Mapping**: Confirm flattened index calculation is correct
4. **Memory Layout**: Check compatibility with Fortran ordering

## Testing Strategy

1. Check array values after allocation
2. Verify asymmetric arrays are only allocated when lasym=true
3. Test index mapping between implementations
4. Monitor for memory access violations