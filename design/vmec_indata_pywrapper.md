# VMEC Input Data Python Wrapper - Asymmetric Interface

This document analyzes how the Python wrapper handles asymmetric mode arrays in VMEC++.

## Overview

The Python wrapper provides a Pythonic interface to VMEC++ input data structures. For asymmetric mode, it must properly expose and initialize the additional boundary arrays.

## Modified Functions

### 1. Constructor: `VmecINDATAPyWrapper()`

**Changes for Asymmetric Arrays**:
```cpp
VmecINDATAPyWrapper::VmecINDATAPyWrapper() {
    // ... existing initialization ...
    
    // NEW: Proper initialization for asymmetric boundary arrays
    // These arrays need to be accessible from Python even if empty
    rbs = py::array_t<double>({0, 0});  // Initialize as 0x0 array
    zbc = py::array_t<double>({0, 0});  // Initialize as 0x0 array
    
    // Asymmetric axis arrays
    raxis_cs = py::array_t<double>({0});
    zaxis_cc = py::array_t<double>({0});
}
```

### 2. `SetMpolNtor()` Method

**Purpose**: Resize arrays when mpol/ntor change

**Changes**:
```cpp
void VmecINDATAPyWrapper::SetMpolNtor(int new_mpol, int new_ntor) {
    mpol = new_mpol;
    ntor = new_ntor;
    
    // Resize symmetric arrays
    rbc = ResizeArray(rbc, {2*ntor+1, mpol+1});
    zbs = ResizeArray(zbs, {2*ntor+1, mpol+1});
    
    // NEW: Handle asymmetric arrays based on lasym flag
    if (lasym) {
        rbs = ResizeArray(rbs, {2*ntor+1, mpol+1});
        zbc = ResizeArray(zbc, {2*ntor+1, mpol+1});
        
        // Axis arrays
        raxis_cs = ResizeArray(raxis_cs, {ntor+1});
        zaxis_cc = ResizeArray(zaxis_cc, {ntor+1});
    }
}
```

## Python Interface

### Usage from Python

```python
import vmecpp

# Create input object
indata = vmecpp.VmecInput()

# Enable asymmetric mode
indata.lasym = True

# Set dimensions
indata.mpol = 5
indata.ntor = 3

# Access asymmetric arrays
indata.rbs[0, 0] = 0.1  # R sine coefficient
indata.zbc[0, 0] = 0.05  # Z cosine coefficient

# Axis guess
indata.raxis_cs[0] = 0.0
indata.zaxis_cc[0] = 0.0
```

### Array Properties

The wrapper exposes numpy arrays with:
- **Shape**: `(2*ntor+1, mpol+1)` for boundary arrays
- **Dtype**: float64
- **Memory**: C-contiguous
- **Writeable**: Yes

## Key Implementation Details

### 1. Array Lifecycle

**Problem**: Python/C++ array ownership
**Solution**: pybind11 manages reference counting

### 2. Dynamic Resizing

When mpol/ntor change:
1. Create new array with correct size
2. Copy old data (if any)
3. Zero-fill new elements
4. Update Python object

### 3. Validation

The wrapper performs minimal validation, relying on the C++ layer for comprehensive checks.

## Comparison with Direct Fortran

### Fortran NAMELIST
```fortran
&INDATA
  LASYM = T
  RBS(0,0) = 0.1
  ZBC(0,0) = 0.05
/
```

### Python API
```python
indata.lasym = True
indata.rbs[0, 0] = 0.1
indata.zbc[0, 0] = 0.05
```

## Integration Issues

### 1. Array Initialization

**Issue**: Uninitialized arrays could cause crashes
**Fix**: Always initialize to zero-size arrays in constructor

### 2. Resize Logic

**Issue**: Need to handle lasym flag changes
**Fix**: Proper array management in SetMpolNtor

### 3. Memory Layout

**Issue**: Fortran vs C memory order
**Fix**: Use C-contiguous arrays, convert in C++ layer

## Verification Points

1. **Array Access**: Test reading/writing all elements
2. **Resize Behavior**: Verify data preserved on resize
3. **Memory Management**: Check for leaks with valgrind
4. **Type Safety**: Ensure proper float64 handling

## Known Limitations

1. **Performance**: Array copies on resize
2. **Validation**: Limited input checking at Python level
3. **Documentation**: Python docstrings could be improved

## Testing Strategy

1. Create arrays with various sizes
2. Test resize operations
3. Verify data persistence
4. Check memory usage patterns
5. Test edge cases (mpol=0, ntor=0)

## Future Improvements

1. Add property validators
2. Implement array views for efficiency
3. Better error messages
4. Support for direct INDATA file reading