#!/usr/bin/env python3
"""
Simple comparison script for jVMEC NetCDF outputs
Compares only the quantities that jVMEC actually provides
"""

import netCDF4 as nc
import numpy as np
import sys

def extract_jvmec_data(filepath):
    """Extract available data from jVMEC NetCDF file"""
    try:
        with nc.Dataset(filepath, 'r') as ds:
            data = {
                'ns': ds.dimensions['rmnc_dim0'].size,
                'mnmax': ds.dimensions['rmnc_dim1'].size,
                'nfp': int(ds.variables['nfp'][:]),
                'mpol': int(ds.variables['mpol'][:]),
                'ntor': int(ds.variables['ntor'][:])}
            
            # Get Fourier coefficients at boundary (last radial surface)
            rmnc = ds.variables['rmnc'][:]
            zmns = ds.variables['zmns'][:]
            lmns = ds.variables['lmns'][:]
            xm = ds.variables['xm'][:]
            xn = ds.variables['xn'][:]
            
            # Extract R axis (m=0, n=0 mode - typically first element)
            data['raxis'] = float(rmnc[-1, 0])
            
            # Get first few Fourier modes at boundary
            data['modes'] = []
            for i in range(min(5, len(xm))):
                data['modes'].append({
                    'm': int(xm[i]),
                    'n': int(xn[i]),
                    'rmnc': float(rmnc[-1, i]),
                    'zmns': float(zmns[-1, i]),
                    'lmns': float(lmns[-1, i])
                })
            
            # Check for asymmetric modes
            if 'lasym__logical__' in ds.variables:
                data['lasym'] = bool(ds.variables['lasym__logical__'][:])
            else:
                data['lasym'] = False
                
            return data
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
        return None

def compare_files(files):
    """Compare multiple jVMEC output files"""
    print("jVMEC Output Comparison")
    print("=" * 60)
    
    all_data = {}
    for name, filepath in files.items():
        data = extract_jvmec_data(filepath)
        if data:
            all_data[name] = data
            
    if not all_data:
        print("No valid data found!")
        return
        
    # Basic parameters
    print("\nBasic Parameters:")
    print("-" * 40)
    print(f"{'Case':<20} {'ns':>6} {'mnmax':>6} {'nfp':>4} {'mpol':>5} {'ntor':>5} {'lasym':>6}")
    for name, data in all_data.items():
        print(f"{name:<20} {data['ns']:>6} {data['mnmax']:>6} {data['nfp']:>4} "
              f"{data['mpol']:>5} {data['ntor']:>5} {str(data.get('lasym', False)):>6}")
    
    # R axis comparison
    print("\nR axis values:")
    print("-" * 40)
    for name, data in all_data.items():
        print(f"{name:<20}: {data['raxis']:.8f}")
    
    # Fourier modes comparison
    print("\nFourier Modes at Boundary:")
    print("-" * 60)
    
    for name, data in all_data.items():
        print(f"\n{name}:")
        print(f"{'(m,n)':<8} {'R_mn':>15} {'Z_mn':>15} {'L_mn':>15}")
        print("-" * 53)
        for mode in data['modes']:
            print(f"({mode['m']:2d},{mode['n']:2d})   "
                  f"{mode['rmnc']:>15.8e} {mode['zmns']:>15.8e} {mode['lmns']:>15.8e}")
    
    # Calculate differences if we have multiple cases
    if len(all_data) > 1:
        print("\nRelative Differences in R axis:")
        print("-" * 40)
        names = list(all_data.keys())
        ref_raxis = all_data[names[0]]['raxis']
        for i in range(1, len(names)):
            diff = (all_data[names[i]]['raxis'] - ref_raxis) / ref_raxis
            print(f"{names[i]} vs {names[0]}: {diff:.6e}")

if __name__ == "__main__":
    # Compare the manual test outputs
    files = {
        'Symmetric (LASYM=F)': 'manual_test/wout_test_symmetric.nc',
        'Asymmetric (LASYM=T)': 'manual_test/wout_test_asymmetric.nc',
        'Original': 'manual_test/wout_input_cleaned.nc'
    }
    
    compare_files(files)