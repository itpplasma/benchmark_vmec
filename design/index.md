# VMEC++ Asymmetric Mode Implementation Analysis

This directory contains detailed analysis of the asymmetric mode implementation in VMEC++, comparing it with educational_VMEC and jVMEC to ensure consistency and correctness.

## Modified Functions and Classes

### New Core Algorithm Files

1. [Fourier Transform Asymmetric](fourier_asymmetric.md) - NEW FILE - Force computation for asymmetric equilibria
   - **Files**: `fourier_asymmetric.cc`, `fourier_asymmetric.h`
   - **New Functions**:
     - `FourierToReal3DAsymmFastPoloidal()` - Transform Fourier to real space (3D)
     - `FourierToReal2DAsymmFastPoloidal()` - Transform Fourier to real space (2D/axisymmetric)
     - `SymmetrizeRealSpaceGeometry()` - Apply symmetry operations
     - `RealToFourier3DAsymmFastPoloidal()` - Transform forces to Fourier (3D)
     - `RealToFourier2DAsymmFastPoloidal()` - Transform forces to Fourier (2D)
     - `SymmetrizeForces()` - Apply symmetry to forces
   - **Status**: 🔄 To be analyzed

### Modified Core Algorithm Functions

2. [Magnetic Axis Recovery](guess_axis.md) - Grid search algorithm for fixing BAD_JACOBIAN conditions
   - **File**: `guess_magnetic_axis.cc`
   - **Modified**: `RecomputeMagneticAxisToFixJacobianSign()` - Debug output added
   - **Status**: ✅ Verified against educational_VMEC and jVMEC

3. [Ideal MHD Model](ideal_mhd_model.md) - Integration of asymmetric force calculations
   - **Files**: `ideal_mhd_model.cc`, `ideal_mhd_model.h`
   - **Modified Functions**:
     - `IdealMhdModel::IdealMhdModel()` - Added asymmetric array allocation
     - `geometryFromFourier()` - Added asymmetric DFT calls
     - `forcesToFourier()` - Added asymmetric force handling
   - **New Functions**:
     - `dft_FourierToReal_3d_asymm()` - Asymmetric 3D DFT
     - `dft_FourierToReal_2d_asymm()` - Asymmetric 2D DFT
     - `symrzl()` - Symmetrization operation
   - **Status**: 🔄 To be analyzed

### Modified Support Infrastructure

4. [Boundaries](boundaries.md) - Boundary condition handling
   - **Files**: `boundaries.cc`, `boundaries.h`
   - **New Functions**:
     - `checkSignOfJacobianOriginal()` - Original Jacobian check
     - `checkSignOfJacobianPolygonArea()` - Polygon-based Jacobian check
   - **Modified**: `RecomputeMagneticAxisToFixJacobianSign()` - Debug output
   - **Status**: 🔄 To be analyzed

5. [Fourier Coefficients](fourier_coefficients.md) - Handling of asymmetric Fourier arrays
   - **File**: `fourier_coefficients.cc`
   - **Modified**: `FourierCoeffs::FourierCoeffs()` - Zero initialization for arrays
   - **Status**: 🔄 To be analyzed

6. [Handover Storage](handover_storage.md) - Memory management for asymmetric arrays
   - **Files**: `handover_storage.cc`, `handover_storage.h`
   - **Modified**: `allocate()` - Added asymmetric array allocation
   - **New Arrays**: `rmnsc_i/o`, `rmncs_i/o`, `zmncc_i/o`, `zmnss_i/o`, `lmncc_i/o`, `lmnss_i/o`
   - **Status**: 🔄 To be analyzed

7. [Output Quantities](output_quantities.md) - Computing quantities for asymmetric equilibria
   - **File**: `output_quantities.cc`
   - **Modified Functions**:
     - `DecomposeCovariantBBySymmetry()` - Asymmetric array indexing
     - `LowPassFilterCovariantB()` - Asymmetric component handling
   - **Status**: 🔄 To be analyzed

### Modified Input/Output Handling

8. [VMEC Input Data](vmec_indata.md) - Parsing asymmetric input parameters
   - **File**: `vmec_indata.cc`
   - **Modified**: Logic in `FromJson()` and `IsConsistent()` for asymmetric boundaries
   - **Status**: 🔄 To be analyzed

9. [Python Wrapper](vmec_indata_pywrapper.md) - Python interface for asymmetric arrays
   - **File**: `vmec_indata_pywrapper.cc`
   - **Modified Functions**:
     - `VmecINDATAPyWrapper()` constructor - Asymmetric array initialization
     - `SetMpolNtor()` - Asymmetric array setup
   - **Status**: 🔄 To be analyzed

### Main Integration

10. [VMEC Main](vmec_main.md) - Asymmetric mode integration in main solver
    - **File**: `vmec.cc`
    - **Status**: 🔄 To be analyzed (no function signature changes detected)

## Analysis Methodology

For each function/class, we analyze:
1. **Purpose**: What the function does in the context of asymmetric equilibria
2. **Algorithm**: Step-by-step breakdown of the implementation
3. **Comparison**: How it differs between educational_VMEC, jVMEC, and VMEC++
4. **Key Variables**: Important arrays and parameters specific to asymmetric mode
5. **Verification**: Status of testing and validation

## Force Computation Architecture Analysis

### Educational_VMEC Architecture

In educational_VMEC, the force computation flow for asymmetric mode is integrated into the main routines:

1. **funct3d.f90** - Main force evaluation routine
   - Calls `totzsps` for symmetric geometry transformation
   - Calls `totzspa` for asymmetric geometry transformation (if lasym=true)
   - Computes forces in real space
   - Calls `tomnsps` for symmetric force transformation back to Fourier
   - Calls `tomnspa` for asymmetric force transformation (if lasym=true)

2. **totzsp.f90** - Contains both `totzsps` and `totzspa`
   - Transforms Fourier coefficients to real space
   - Handles both symmetric and asymmetric components

3. **tomnsp.f90** - Contains both `tomnsps` and `tomnspa`
   - Transforms real-space forces back to Fourier space
   - Handles both symmetric and asymmetric components

### VMEC++ Architecture

VMEC++ has split the functionality into separate files:

1. **ideal_mhd_model.cc** - Main force evaluation orchestrator
   - Calls symmetric force computation (existing code)
   - Calls `FourierToReal3DAsymmFastPoloidal` from `fourier_asymmetric.cc`
   - Computes forces in real space (unified logic)
   - Calls `RealToFourier3DAsymmFastPoloidal` from `fourier_asymmetric.cc`

2. **fourier_asymmetric.cc** - NEW FILE containing:
   - `FourierToReal3DAsymmFastPoloidal` ≈ educational_VMEC's `totzspa`
   - `RealToFourier3DAsymmFastPoloidal` ≈ educational_VMEC's `tomnspa`
   - `FourierToReal2DAsymmFastPoloidal` (axisymmetric case)
   - `RealToFourier2DAsymmFastPoloidal` (axisymmetric case)

### Key Architectural Differences

1. **File Organization**:
   - educational_VMEC: Monolithic files with symmetric/asymmetric routines together
   - VMEC++: Separate file for asymmetric transformations

2. **Function Calls**:
   - educational_VMEC: Conditional calls based on `lasym` flag
   - VMEC++: Always creates asymmetric geometry structures, conditionally fills them

3. **Memory Management**:
   - educational_VMEC: Arrays allocated based on `lasym` at startup
   - VMEC++: All arrays pre-allocated in HandoverStorage

### Equivalence Verification Needed

1. **Transform Functions**: Verify `FourierToReal3DAsymmFastPoloidal` matches `totzspa`
2. **Force Integration**: Ensure force calculations use asymmetric geometry correctly
3. **Back Transform**: Verify `RealToFourier3DAsymmFastPoloidal` matches `tomnspa`
4. **Array Mapping**: Confirm array indices and memory layout match

## Priority Order

Based on impact and dependencies:
1. ✅ Magnetic Axis Recovery (completed)
2. 🔴 Fourier Transform Asymmetric (critical - new file)
3. 🔴 Ideal MHD Model (critical - force integration)
4. 🟡 Fourier Coefficients (important - array handling)
5. 🟡 Output Quantities (important - results)
6. 🟢 Others (supporting infrastructure)

## Legend
- ✅ Fully analyzed and verified
- 🔄 To be analyzed
- 🔴 Critical for asymmetric convergence
- 🟡 Important for correctness
- 🟢 Supporting functionality