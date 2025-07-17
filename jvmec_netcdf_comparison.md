# jVMEC vs Standard VMEC NetCDF Output Comparison

## Key Differences Found

### Standard VMEC NetCDF Output Contains:
- `wb` - MHD energy
- `betatotal` - Total plasma beta
- `betapol` - Poloidal beta
- `betator` - Toroidal beta
- `betaxis` - Beta on axis
- `aspect` - Aspect ratio
- `volume_p` - Plasma volume
- And many other derived physics quantities

### jVMEC NetCDF Output Contains:
- `iotas` - Rotational transform profile
- `phips` - Toroidal flux derivative
- `buco` - Ballooning coefficient
- `phipf` - Toroidal flux
- `rmnc`, `zmns`, `lmns` - Fourier coefficients
- `gmnc` - Jacobian Fourier coefficients
- Basic parameters: `nfp`, `mpol`, `ntor`, `ns`, `mnmax`

## Analysis

jVMEC's NetCDF output appears to contain primarily the **raw Fourier coefficients** and basic equilibrium profiles, but lacks the **derived physics quantities** that standard VMEC computes and stores, such as:

1. **Energy quantities**: MHD energy (wb), magnetic energy
2. **Beta values**: Total, poloidal, toroidal beta
3. **Geometric quantities**: Aspect ratio, elongation, volume
4. **Stability parameters**: Mercier criterion, shear, well depth

This explains why the benchmark comparison showed zeros for jVMEC - the extraction code was looking for variables like `wb` and `betatotal` that don't exist in jVMEC's output format.

## Implications

To properly compare jVMEC with other VMEC implementations, we would need to either:
1. Modify jVMEC to compute and output these derived quantities
2. Post-process jVMEC's Fourier coefficients to calculate the physics quantities
3. Compare only the fundamental quantities (Fourier harmonics, iota profile, etc.)