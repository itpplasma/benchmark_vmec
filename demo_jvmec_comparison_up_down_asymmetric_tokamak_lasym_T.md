# Quantitative jVMEC Comparison Summary

Reference implementation: educational_vmec

## Convergence Analysis

| Implementation | Status | R_axis | Available Data |
|---|---|---|---|
| educational_vmec | ✓ |   1.015000 | Fourier (25×10) |
| jvmec | ✓ |   1.025000 | Fourier (25×10) |
| vmec2000 | ✓ |   1.035000 | Fourier (25×10) |
| vmecpp | ✓ |   1.045000 | Limited |

## Quantitative Differences from Reference

### jvmec vs Reference

- R-axis: Δ =  9.85222E-03 (ref:  1.01500E+00)
- Fourier R modes: RMS Δ =  1.01648E-03, Max Δ =  1.09894E-03 (10 modes)
- Fourier Z modes: RMS Δ =  4.96758E-04, Max Δ =  5.24004E-04 (10 modes)

### vmec2000 vs Reference

- R-axis: Δ =  1.97044E-02 (ref:  1.01500E+00)
- Fourier R modes: RMS Δ =  2.03295E-03, Max Δ =  2.19787E-03 (10 modes)
- Fourier Z modes: RMS Δ =  9.93517E-04, Max Δ =  1.04801E-03 (10 modes)

### vmecpp vs Reference

- R-axis: Δ =  2.95567E-02 (ref:  1.01500E+00)
- Fourier coefficients: Not available for comparison

## Statistical Summary

- Total implementations: 4 (4 successful)
- R-axis mean:  1.03000E+00
- R-axis std dev:  1.29099E-02
- R-axis range: [ 1.01500E+00,  1.04500E+00]
- R-axis relative std dev:  1.25339E-02 (ratio)
