# Magnetic Axis Guessing Algorithm Comparison

This document compares the magnetic axis guessing algorithms across three VMEC implementations:
- educational_VMEC (Fortran)
- jVMEC (Java)
- VMEC++ (C++)

## Overview

The axis guessing algorithm is triggered when a BAD_JACOBIAN condition is detected. It performs a grid search to find a better magnetic axis position that maximizes the minimum Jacobian value across all theta angles.

## Algorithm Steps

### 1. Input Arrays and Setup

**All implementations use:**
- Boundary surface geometry (R, Z at full radius)
- Half-radius surface geometry
- Theta derivatives (dR/dtheta, dZ/dtheta)
- Current axis position as initial guess

### 2. Grid Search Domain

**All implementations:**
- Create a bounding box from the boundary surface min/max R and Z values
- Use a 61×61 grid (defined as constant)
- Grid spacing: delta_r = (max_r - min_r) / 60, delta_z = (max_z - min_z) / 60

### 3. Jacobian Calculation

**All implementations compute:**
```
tau = sign_of_jacobian * (ru * zs - rs * zu)
```

Where:
- `ru` = dR/dtheta (from boundary)
- `zu` = dZ/dtheta (from boundary)
- `rs` = dR/ds ≈ (R_boundary - R_half) / delta_s + R_axis
- `zs` = dZ/ds ≈ (Z_boundary - Z_half) / delta_s + Z_axis

The static part (tau0) is precomputed before the grid search.

### 4. Grid Search Optimization

**All implementations:**
- Initialize min_tau = 0.0
- For each grid point (r_grid, z_grid):
  - Compute tau for all theta angles
  - Find min_tau_temp = minimum tau across all theta
  - If min_tau_temp > min_tau: update optimal position
  - If min_tau_temp == min_tau: tie-breaking logic

### 5. Tie-Breaking Logic

**All implementations use the same logic:**
```
If min_tau_temp == min_tau:
    If |current_z_axis| > |z_grid|:
        Set z_axis = z_grid  // Prefer Z closer to zero
```

This ensures up-down symmetric equilibria choose Z=0 for the axis.

### 6. Stellarator Symmetry Handling

**For non-asymmetric cases (lasym=false):**
- Only compute first half of toroidal planes (0 to nzeta/2)
- After grid search, mirror the results: axis[nzeta-k] = axis[k]

**For asymmetric cases (lasym=true):**
- Compute all toroidal planes independently

### 7. Fourier Transform

**All implementations:**
1. Apply DFT to convert real-space axis positions to Fourier coefficients
2. Use proper normalization with delta_v = 2/nzeta and nscale factors

**Fourier arrays:**
- Symmetric case: raxis_c (R cosine), zaxis_s (Z sine)
- Asymmetric case adds: raxis_s (R sine), zaxis_c (Z cosine)

### 8. Fourier Coefficient Scaling

**All implementations apply identical scaling:**

For n=0 (DC component) and n=nzeta/2 (Nyquist component):
- `raxis_c[n] *= 0.5` (always)
- `zaxis_c[n] *= 0.5` (only if lasym=true)

No scaling is applied to sine terms (raxis_s, zaxis_s).

This scaling corrects for the DFT normalization of cosine basis functions.

## Key Implementation Differences

### 1. Array Indexing
- educational_VMEC: 1-based Fortran arrays
- jVMEC & VMEC++: 0-based arrays

### 2. Sign Conventions
- educational_VMEC: Uses negative sign for some Fourier coefficients
- VMEC++: Adjusted signs to match expected conventions

### 3. Memory Layout
- educational_VMEC: Fortran column-major ordering
- jVMEC & VMEC++: Row-major ordering

### 4. Optimization
- VMEC++: Can use OpenMP parallelization (currently disabled in axis guess)
- Others: Serial implementation

## Verification Status

✅ **Grid search algorithm**: Identical logic across all three
✅ **Tie-breaking logic**: All prefer Z closest to zero
✅ **Fourier transform**: Same mathematical approach
✅ **Scaling factors**: Identical 0.5 scaling for cosine DC/Nyquist terms
✅ **Symmetry handling**: Same approach for stellarator symmetry

## Current VMEC++ Implementation Status

The VMEC++ implementation has been verified to produce identical results to educational_VMEC for the axis guessing algorithm. The key fixes applied:
1. Corrected min_tau initialization to 0.0 (was incorrectly -1e10)
2. Verified tie-breaking logic matches exactly
3. Confirmed Fourier scaling matches reference implementations

The algorithm now successfully recovers from BAD_JACOBIAN conditions in test cases where it previously failed.