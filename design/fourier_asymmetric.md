# Fourier Transform Asymmetric Force Computation

This document analyzes the asymmetric force computation implementation across three VMEC codes:
- educational_VMEC: `funct3d.f90` (asymmetric portions)
- jVMEC: `IdealMHDModel.java` (asymmetric methods)
- VMEC++: `fourier_asymmetric.cc` (new dedicated file)

## Overview

The asymmetric force computation extends the stellarator-symmetric force calculations to handle equilibria without up-down symmetry. This requires computing additional Fourier harmonics for sine components of R and cosine components of Z.

## Key Arrays and Variables

### Asymmetric-specific Arrays
- `armn`, `azmn` - Fourier coefficients for vector potential (asymmetric components)
- `brmn_e`, `brmn_o` - Radial magnetic field Fourier coefficients (even/odd)
- `bzmn_e`, `bzmn_o` - Vertical magnetic field Fourier coefficients (even/odd)
- `crmn_e`, `crmn_o` - Current density radial component (even/odd)
- `czmn_e`, `czmn_o` - Current density vertical component (even/odd)

### Force Arrays
- `force_ru_s` - Radial force from R sine terms
- `force_zu_c` - Vertical force from Z cosine terms
- `force_rs_s` - Radial gradient force from R sine terms
- `force_zs_c` - Vertical gradient force from Z cosine terms

## Algorithm Comparison

### 1. Force Computation Structure

**educational_VMEC**:
- `tomnsps` (tomnsp.f90): Transforms symmetric forces (R cosine, Z sine)
- `tomnspa` (tomnsp.f90): Transforms asymmetric forces (R sine, Z cosine)
- `totzsps` (totzsp.f90): Real to Fourier for symmetric geometry
- `totzspa` (totzsp.f90): Real to Fourier for asymmetric geometry

**jVMEC**:
```java
if (!lasym) {
    computeSymmetricForces(...);
} else {
    computeAsymmetricForces(...);
}
```

**VMEC++**:
- `fourier_symmetric.cc`: Symmetric force computation
- `fourier_asymmetric.cc`: NEW FILE - Asymmetric force computation
- `FourierToReal3DAsymmFastPoloidal`: Equivalent to educational_VMEC's `totzspa`
- `RealToFourier3DAsymmFastPoloidal`: Equivalent to educational_VMEC's `tomnspa`

### 2. Key Implementation Details

**Mode Scaling for Odd-m Modes**:

VMEC++ (fourier_asymmetric.cc):
```cpp
if (m % 2 == 1) {  // odd-m modes
    const double sqrtS_min = (jF == r.nsMinF1 && r.nsMaxF1 - r.nsMinF1 > 1)
                                 ? rp.sqrtSF[1]
                                 : sqrtSF;
    modeScale = 1.0 / sqrtS_min;
}
```

This implements Equation (8c) from Hirshman, Schwenn & Nührenberg (1990), scaling odd-m modes by 1/sqrt(s) to handle singularities at the magnetic axis.

**Array Mapping**:
- educational_VMEC: `frcs, frsc, fzcc, fzss` (combined array with index offsets)
- VMEC++: Separate arrays in `RealSpaceGeometryAsym` struct

### 2. Key Differences

**File Organization**:
- educational_VMEC: Integrated in main force routine with conditional blocks
- jVMEC: Separate methods but in same class
- VMEC++: Dedicated file `fourier_asymmetric.cc` (new approach)

**Memory Management**:
- educational_VMEC: Static arrays allocated based on lasym flag
- jVMEC: Dynamic allocation when lasym=true
- VMEC++: Pre-allocated arrays in HandoverStorage

### 3. Force Calculation Steps

**All implementations follow the same general pattern**:
1. Transform R, Z, λ from Fourier to real space
2. Compute metric elements (g_ij) and Jacobian
3. Calculate magnetic field components (B^u, B^v)
4. Compute current density components
5. Calculate force balance: F = J × B - ∇p
6. Transform forces back to Fourier space

### 4. Critical Implementation Details

**Sign Conventions**:
- Need to verify sign conventions match between implementations
- Special attention to sine/cosine term signs

**Normalization**:
- Check if force normalization is consistent
- Verify Fourier transform scaling factors

**Boundary Conditions**:
- Asymmetric mode requires different boundary handling
- Check force filtering at boundaries

## Verification Status

🔄 **To Be Analyzed**:
1. Line-by-line comparison of force calculations
2. Sign convention verification
3. Array indexing and memory layout
4. Fourier transform implementation details
5. Boundary condition handling

## Known Issues

1. **VMEC++ Status**: New file created for asymmetric forces - need to verify it matches reference implementations
2. **Integration**: How this integrates with main force computation needs verification

## Next Steps

1. Extract force calculation formulas from each implementation
2. Create test cases with known analytical solutions
3. Verify intermediate quantities (B field, current, etc.)
4. Check force balance convergence