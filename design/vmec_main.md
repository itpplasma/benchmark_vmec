# VMEC Main - Asymmetric Mode Integration

This document analyzes how the main VMEC solver integrates asymmetric mode support.

## Overview

The main VMEC class orchestrates the entire equilibrium calculation. While no function signatures were changed for asymmetric support, the integration logic throughout the solver was modified.

## Integration Points

### 1. Initialization Phase

**Symmetric Mode**:
```cpp
// Standard initialization
InitializeRadialProfiles();
InitializeFourierBasis();
InitializeGeometry();
```

**Asymmetric Mode Additions**:
- HandoverStorage allocates asymmetric arrays
- FourierBasis includes additional basis functions
- Geometry initialization handles asymmetric coefficients

### 2. Main Iteration Loop

The main convergence loop in `RunIdealMhdIteration()` handles asymmetric mode transparently:

```cpp
while (!converged && iter < maxiter) {
    // Compute geometry from Fourier coefficients
    // Includes asymmetric terms if lasym=true
    UpdateGeometry();
    
    // Calculate forces
    // Asymmetric forces computed if lasym=true
    ComputeForces();
    
    // Update solution
    // Handles full spectrum including asymmetric modes
    UpdateFourierCoefficients();
}
```

### 3. Convergence Criteria

For asymmetric mode:
- Force residuals include asymmetric components
- Convergence tolerance applies to full spectrum
- No special handling needed at this level

## Key Design Decisions

### 1. Transparent Integration

**Approach**: Asymmetric mode integrated without changing main loop structure

**Benefits**:
- Minimal code disruption
- Same convergence logic
- Easy to maintain

**Drawbacks**:
- Some overhead for symmetric cases
- Less obvious what's happening

### 2. Delegation Pattern

The main solver delegates asymmetric handling to:
- `IdealMhdModel` for force calculations
- `Boundaries` for boundary conditions  
- `OutputQuantities` for results

### 3. Error Handling

No special error handling for asymmetric mode - relies on:
- Input validation in VmecINDATA
- Array bounds checking in debug mode
- Standard convergence failure detection

## Comparison with Educational_VMEC

### Educational_VMEC (vmec.f90)

```fortran
! Main iteration loop
DO iter = 1, niter
    CALL funct3d  ! Handles both symmetric and asymmetric
    
    IF (.NOT. lasym) THEN
        ! Symmetric-specific optimizations
    ELSE
        ! Full calculation
    END IF
END DO
```

### VMEC++ Approach

More object-oriented but same logical flow:
- Conditional logic pushed down to component classes
- Main loop remains clean
- Performance optimizations in lower levels

## Integration Challenges

### 1. Memory Management

**Challenge**: Asymmetric arrays significantly increase memory usage
**Solution**: Lazy allocation in HandoverStorage

### 2. Performance

**Challenge**: Asymmetric mode roughly doubles computation
**Solution**: OpenMP parallelization at force calculation level

### 3. Testing

**Challenge**: Need to test both modes thoroughly
**Solution**: Automated tests for both configurations

## Verification Strategy

### 1. Symmetric Consistency

Run symmetric cases with lasym=true and zero asymmetric coefficients:
- Results should match lasym=false exactly
- Performance overhead should be minimal

### 2. Asymmetric Validation

Compare with educational_VMEC on test cases:
- Force residuals at each iteration
- Converged solution accuracy
- Iteration count comparison

### 3. Edge Cases

Test boundary conditions:
- Very small asymmetry
- Large asymmetry
- Mode number limits

## Performance Considerations

### Memory Usage

**Symmetric**: ~N arrays of size ns × mn
**Asymmetric**: ~2N arrays (roughly double)

### Computational Cost

**Symmetric**: O(ns × mn × ntheta)
**Asymmetric**: ~2× symmetric cost

### Optimization Opportunities

1. Skip asymmetric calculations when coefficients are zero
2. Separate code paths for symmetric/asymmetric
3. Better cache usage for array access patterns

## Future Improvements

1. **Adaptive Mode Selection**: Dynamically enable/disable modes
2. **Checkpointing**: Save/restore asymmetric state
3. **Diagnostics**: Better visibility into asymmetric convergence
4. **GPU Support**: Asymmetric transforms on GPU

## Summary

The main VMEC solver successfully integrates asymmetric mode support without major architectural changes. The design prioritizes code maintainability over maximum performance optimization, which is appropriate given the complexity of the physics.