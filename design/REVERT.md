# Changes to Review and Potentially Revert

This document tracks all changes made compared to the prepare-asym branch, especially those that might be questionable.

## 1. guess_magnetic_axis.cc - min_tau initialization

**Current code (line 446):**
```cpp
double min_tau = 0.0;
```

**What we temporarily had (in diff but now fixed):**
```cpp
double min_tau = -1e10;
```

**Status:** Already reverted back to original `0.0` ✓

## 2. guess_magnetic_axis.cc - Debug output

**Added extensive debug output throughout the file:**
- Grid search setup debug (lines 401-413)
- Tau0 computation debug (lines 424-443)
- Early exit logic debug (lines 463-472)
- Grid search progress debug (lines 490-505)
- Axis values after grid search (lines 536-542)
- Axis values after symmetrization (lines 545-551)
- Grid search results and Fourier debug (lines 568-643)

**Status:** Keep for now during debugging, but should be removed before final commit

## 3. guess_magnetic_axis.cc - Tie-breaking logic (lines 510-517)

**Current code:**
```cpp
} else if (min_tau_temp == min_tau) {
  // FIXED: Match educational_VMEC tie-breaking logic exactly
  // Educational_VMEC: IF (ABS(zcom(iv)).gt.ABS(zlim)) then zcom(iv) = zlim
  // Always prefer z-position closest to zero
  if (std::abs(w.new_z_axis[k]) > std::abs(z_grid)) {
    w.new_z_axis[k] = z_grid;
  }
}
```

**Original code in prepare-asym:**
```cpp
} else if (min_tau_temp == min_tau) {
  // If up-down symmetric and lasym=T, need this to pick z = 0
  if (std::abs(w.new_z_axis[k]) > std::abs(z_grid)) {
    w.new_z_axis[k] = z_grid;
  }
}
```

**Status:** Logic is the same, only comment changed. This is correct behavior matching educational_VMEC ✓

## 4. Fourier scaling structure (lines ~620-640)

**Current code:**
```cpp
// DC component (n=0) scaling - match educational_VMEC exactly
// Educational_VMEC applies p5 (0.5) scaling for n=0
w.new_raxis_c[0] /= 2.0;
if (s.lasym) {
  w.new_zaxis_c[0] /= 2.0;
}

// Nyquist component scaling (n = nZeta/2) - if applicable
if (s.ntor > 0 && s.ntor >= s.nZeta / 2) {
  w.new_raxis_c[s.nZeta / 2] /= 2.0;
  if (s.lasym) {
    w.new_zaxis_c[s.nZeta / 2] /= 2.0;
  }
}
```

**Original code in prepare-asym:**
```cpp
w.new_raxis_c[0] /= 2.0;
if (s.ntor > 0 && s.ntor >= s.nZeta / 2) {
  w.new_raxis_c[s.nZeta / 2] /= 2.0;
}
if (s.lasym) {
  w.new_zaxis_c[0] /= 2.0;
  if (s.ntor > 0 && s.ntor >= s.nZeta / 2) {
    w.new_zaxis_c[s.nZeta / 2] /= 2.0;
  }
}
```

**Status:** Cosmetic restructuring only - mathematically identical. Just grouped related operations together ✓

## Summary

All actual logic changes have been reverted. The only changes remaining are:
1. Debug output (to be removed later)
2. Comment updates to better document the tie-breaking logic
3. Cosmetic restructuring of the scaling code (no functional change)

**No factor of 2 errors or other mathematical changes remain.**