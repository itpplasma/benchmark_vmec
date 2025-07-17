# Quantitative jVMEC Comparison Summary

Reference implementation: educational_vmec

## Convergence Analysis

| Implementation | Status | R_axis | Available Data |
|---|---|---|---|
| educational_vmec | ✓ |   1.000000 | Fourier (50×10) |
| jvmec | ✓ |   1.010000 | Fourier (50×10) |
| vmec2000 | ✓ |   1.020000 | Fourier (50×10) |

## Quantitative Differences from Reference

### jvmec vs Reference

- R-axis: Δ =  1.00000E-02 (ref:  1.00000E+00)
- Fourier R modes: RMS Δ =  2.00000E-03, Max Δ =  2.00000E-03 (10 modes)
- Fourier Z modes: RMS Δ =  2.00000E-03, Max Δ =  2.00000E-03 (10 modes)

### vmec2000 vs Reference

- R-axis: Δ =  2.00000E-02 (ref:  1.00000E+00)
- Fourier R modes: RMS Δ =  3.00000E-03, Max Δ =  3.00000E-03 (10 modes)
- Fourier Z modes: RMS Δ =  3.00000E-03, Max Δ =  3.00000E-03 (10 modes)

## Statistical Summary

- Total implementations: 3 (3 successful)
- R-axis mean:  1.01000E+00
- R-axis std dev:  1.00000E-02
- R-axis range: [ 1.00000E+00,  1.02000E+00]
- R-axis relative std dev:  9.90099E-03 (ratio)
