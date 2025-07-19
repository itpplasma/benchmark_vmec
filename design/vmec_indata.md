# VMEC Input Data - Asymmetric Parsing

This document analyzes how VMEC input data parsing handles asymmetric mode parameters across implementations.

## Overview

The VMEC input data module is responsible for reading and validating input parameters. For asymmetric mode, it must handle additional boundary coefficient arrays.

## Input Format Changes

### Symmetric Mode Inputs

**Boundary coefficients**:
- `rbc(n,m)` - R boundary cosine coefficients
- `zbs(n,m)` - Z boundary sine coefficients

**Axis initial guess**:
- `raxis_cc(n)` - R axis cosine coefficients
- `zaxis_cs(n)` - Z axis sine coefficients

### Asymmetric Mode Additions

**Boundary coefficients**:
- `rbs(n,m)` - R boundary sine coefficients
- `zbc(n,m)` - Z boundary cosine coefficients

**Axis initial guess**:
- `raxis_cs(n)` - R axis sine coefficients
- `zaxis_cc(n)` - Z axis cosine coefficients

## Implementation Changes

### Educational_VMEC (readin.f90)

```fortran
! Read boundary coefficients
DO m = 0, mpol
   DO n = -ntor, ntor
      READ(unit) rbc(n,m), zbs(n,m)
      IF (lasym) THEN
         READ(unit) rbs(n,m), zbc(n,m)
      END IF
   END DO
END DO
```

### VMEC++ Modifications

**In `FromJson()` method**:
```cpp
// Logic modified to handle asymmetric boundary arrays
if (json.contains("rbs")) {
    // Parse rbs array with proper dimensions
    ParseBoundaryArray(json["rbs"], rbs, mpol, ntor);
}
if (json.contains("zbc")) {
    // Parse zbc array with proper dimensions
    ParseBoundaryArray(json["zbc"], zbc, mpol, ntor);
}
```

**In `IsConsistent()` method**:
```cpp
// Modified validation logic
if (lasym) {
    // Check that asymmetric arrays have correct dimensions
    if (rbs.size() != expected_size) return false;
    if (zbc.size() != expected_size) return false;
}
```

## JSON Format for Asymmetric Mode

```json
{
    "lasym": true,
    "mpol": 5,
    "ntor": 3,
    "rbc": [[...], [...]],  // Symmetric R cosine
    "zbs": [[...], [...]],  // Symmetric Z sine
    "rbs": [[...], [...]],  // Asymmetric R sine
    "zbc": [[...], [...]]   // Asymmetric Z cosine
}
```

## Key Implementation Details

### 1. Array Dimensions

**Fortran INDATA format**: `rbc(-ntor:ntor, 0:mpol)`
**JSON format**: Nested arrays `[m][n]` where n goes from 0 to 2*ntor

### 2. Validation Logic

The validation must ensure:
- All asymmetric arrays present when `lasym=true`
- Arrays have consistent dimensions
- No asymmetric arrays when `lasym=false`

### 3. Default Values

When converting from old format:
- Asymmetric arrays default to zero
- Maintains backward compatibility

## Comparison: INDATA vs JSON

### INDATA Format (Fortran)
```
&INDATA
  LASYM = T
  ...
  RBC(0,0) = 6.0  ZBS(0,0) = 0.0
  RBS(0,0) = 0.1  ZBC(0,0) = 0.0  ! Asymmetric terms
  ...
/
```

### JSON Format (VMEC++)
```json
{
  "lasym": true,
  "rbc": [[6.0, ...], ...],
  "zbs": [[0.0, ...], ...],
  "rbs": [[0.1, ...], ...],
  "zbc": [[0.0, ...], ...]
}
```

## Verification Points

1. **Array Parsing**: Verify all coefficients read correctly
2. **Dimension Checking**: Ensure array sizes match mpol/ntor
3. **Validation Logic**: Test with various valid/invalid inputs
4. **Backward Compatibility**: Old files should still work

## Known Issues

1. **Error Messages**: Could be more specific about what's wrong
2. **Partial Data**: No graceful handling of incomplete asymmetric data
3. **Large Arrays**: Performance for high mpol/ntor

## Testing Strategy

1. Test parsing of both INDATA and JSON formats
2. Verify error handling for malformed input
3. Check boundary conditions (n=0, m=0, edge cases)
4. Compare parsed values between implementations

## Integration with Rest of Code

The parsed input data flows to:
1. **Boundaries**: For computing plasma boundary
2. **FourierCoefficients**: For initializing spectral arrays
3. **Output**: For writing results

Correct parsing is critical as errors here propagate throughout the calculation.