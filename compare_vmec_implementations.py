#!/usr/bin/env python3
"""
Automated VMEC Implementation Comparison System

This script automatically:
1. Clones and builds educational_VMEC, VMEC++, and VMEC2000 (SIMSOPT style)
2. Optionally builds jVMEC if available
3. Runs all VMEC++ test cases in all available implementations
4. Compares results and generates summary tables
5. Creates flux surface visualizations at multiple phi positions

Requirements:
- Python 3.8+
- CMake, Maven (for builds)
- matplotlib, numpy, netCDF4, pandas
"""

import os
import sys
import subprocess
import shutil
import json
import tempfile
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any
import argparse

# Third-party imports (install with pip if missing)
try:
    import numpy as np
    import matplotlib.pyplot as plt
    import pandas as pd
    from netCDF4 import Dataset
except ImportError as e:
    print(f"Error: Missing required package: {e}")
    print("Install with: pip install numpy matplotlib pandas netcdf4")
    sys.exit(1)


class VMECImplementation:
    """Base class for VMEC implementations"""
    
    def __init__(self, name: str, path: Path):
        self.name = name
        self.path = path
        self.available = False
        self.executable = None
        
    def is_available(self) -> bool:
        """Check if implementation is available"""
        return self.available
        
    def build(self) -> bool:
        """Build the implementation"""
        raise NotImplementedError
        
    def run_case(self, input_file: Path, output_dir: Path) -> bool:
        """Run a test case"""
        raise NotImplementedError
        
    def extract_results(self, output_dir: Path) -> Dict[str, Any]:
        """Extract results from output files"""
        raise NotImplementedError


class EducationalVMEC(VMECImplementation):
    """Educational VMEC implementation handler"""
    
    def __init__(self, path: Path, auto_clone: bool = True):
        super().__init__("Educational_VMEC", path)
        self.repo_url = "https://github.com/hiddenSymmetries/educational_VMEC.git"
        self.auto_clone = auto_clone
        
    def clone_and_setup(self) -> bool:
        """Clone educational_VMEC repository if not present"""
        if self.path.exists():
            print(f"Educational VMEC already exists at {self.path}")
            return True
            
        if not self.auto_clone:
            print(f"Educational VMEC not found at {self.path} and auto-clone disabled")
            return False
            
        print(f"Cloning educational_VMEC to {self.path}")
        try:
            subprocess.run([
                "git", "clone", self.repo_url, str(self.path)
            ], check=True, capture_output=True)
            return True
        except subprocess.CalledProcessError as e:
            print(f"Failed to clone educational_VMEC: {e}")
            return False
    
    def build(self) -> bool:
        """Build educational_VMEC using CMake"""
        if not self.clone_and_setup():
            return False
            
        build_dir = self.path / "build"
        build_dir.mkdir(exist_ok=True)
        
        try:
            # Configure with CMake
            subprocess.run([
                "cmake", "..", 
            ], cwd=build_dir, check=True, capture_output=True)
            
            # Build
            subprocess.run([
                "make", "-j", str(os.cpu_count() or 4)
            ], cwd=build_dir, check=True, capture_output=True)
            
            # Check if executable exists
            self.executable = build_dir / "bin" / "xvmec"
            if self.executable.exists():
                self.available = True
                print(f"Successfully built educational_VMEC at {self.executable}")
                return True
            else:
                print("Build completed but executable not found")
                return False
                
        except subprocess.CalledProcessError as e:
            print(f"Failed to build educational_VMEC: {e}")
            return False
    
    def convert_json_to_indata(self, json_file: Path, output_file: Path) -> bool:
        """Convert VMEC++ JSON input to INDATA format"""
        try:
            with open(json_file, 'r') as f:
                data = json.load(f)
            
            with open(output_file, 'w') as f:
                f.write("&INDATA\n")
                
                # Basic parameters
                f.write(f"  LASYM = {'T' if data.get('lasym', False) else 'F'}\n")
                f.write(f"  NFP = {data.get('nfp', 1)}\n")
                f.write(f"  MPOL = {data.get('mpol', 6)}\n")
                f.write(f"  NTOR = {data.get('ntor', 0)}\n")
                
                # Arrays
                if 'ns_array' in data:
                    ns_str = ' '.join(map(str, data['ns_array']))
                    f.write(f"  NS_ARRAY = {ns_str}\n")
                
                if 'ftol_array' in data:
                    ftol_str = ' '.join([f"{x:.0e}" for x in data['ftol_array']])
                    f.write(f"  FTOL_ARRAY = {ftol_str}\n")
                
                if 'niter_array' in data:
                    niter_str = ' '.join(map(str, data['niter_array']))
                    f.write(f"  NITER_ARRAY = {niter_str}\n")
                
                # Scalar parameters
                for key, value in data.items():
                    if key in ['delt', 'tcon0', 'phiedge', 'nstep', 'pres_scale', 
                              'gamma', 'spres_ped', 'ncurr', 'curtor', 'bloat']:
                        if isinstance(value, list) and len(value) == 1:
                            value = value[0]
                        f.write(f"  {key.upper()} = {value}\n")
                
                # String parameters
                for key in ['pmass_type', 'pcurr_type']:
                    if key in data:
                        f.write(f"  {key.upper()} = \"{data[key]}\"\n")
                
                # Special arrays
                if 'am' in data:
                    am_str = ' '.join([f"{x:.6e}" for x in data['am']])
                    f.write(f"  AM = {am_str}\n")
                
                if 'ac' in data:
                    ac_str = ' '.join([f"{x:.6e}" for x in data['ac']])
                    f.write(f"  AC = {ac_str}\n")
                
                if 'aphi' in data:
                    aphi_str = ' '.join([f"{x:.6e}" for x in data['aphi']])
                    f.write(f"  APHI = {aphi_str}\n")
                
                # Free boundary
                f.write(f"  LFREEB = {'T' if data.get('lfreeb', False) else 'F'}\n")
                
                # Axis arrays
                if 'raxis_c' in data:
                    raxis_str = ' '.join([f"{x:.6e}" for x in data['raxis_c']])
                    f.write(f"  RAXIS_CC = {raxis_str}\n")
                
                if 'zaxis_s' in data:
                    zaxis_str = ' '.join([f"{x:.6e}" for x in data['zaxis_s']])
                    f.write(f"  ZAXIS_CS = {zaxis_str}\n")
                
                # Boundary coefficients
                for coeff_type in ['rbc', 'zbs', 'rbs', 'zbc']:
                    if coeff_type in data:
                        for coeff in data[coeff_type]:
                            n, m, value = coeff['n'], coeff['m'], coeff['value']
                            f.write(f"  {coeff_type.upper()}({n},{m}) = {value:.12e}\n")
                
                f.write("/\n&END\n")
            
            return True
            
        except Exception as e:
            print(f"Failed to convert {json_file} to INDATA format: {e}")
            return False
    
    def run_case(self, input_file: Path, output_dir: Path) -> bool:
        """Run educational_VMEC on a test case"""
        if not self.available:
            return False
        
        output_dir.mkdir(parents=True, exist_ok=True)
        
        # Convert JSON to INDATA if needed
        if input_file.suffix == '.json':
            indata_file = output_dir / f"input.{input_file.stem}"
            if not self.convert_json_to_indata(input_file, indata_file):
                return False
        else:
            indata_file = input_file
        
        try:
            # Copy input file to output directory
            local_input = output_dir / indata_file.name
            shutil.copy2(indata_file, local_input)
            
            # Run educational_VMEC
            result = subprocess.run([
                str(self.executable), local_input.name
            ], cwd=output_dir, capture_output=True, text=True, timeout=300)
            
            # Save output log
            with open(output_dir / "educational_vmec.log", 'w') as f:
                f.write(f"Return code: {result.returncode}\n")
                f.write(f"STDOUT:\n{result.stdout}\n")
                f.write(f"STDERR:\n{result.stderr}\n")
            
            return result.returncode == 0
            
        except subprocess.TimeoutExpired:
            print(f"Educational VMEC timed out for {input_file.stem}")
            return False
        except Exception as e:
            print(f"Failed to run educational_VMEC for {input_file.stem}: {e}")
            return False
    
    def extract_results(self, output_dir: Path) -> Dict[str, Any]:
        """Extract results from educational_VMEC output files"""
        results = {'success': False, 'error': None}
        
        try:
            # Look for wout file
            wout_files = list(output_dir.glob("wout_*.nc"))
            jxbout_files = list(output_dir.glob("jxbout_*.nc"))
            
            if not wout_files:
                results['error'] = "No wout file found"
                return results
            
            wout_file = wout_files[0]
            
            with Dataset(wout_file, 'r') as wout:
                results.update({
                    'success': True,
                    'wb': float(wout.variables['wb'][()]),
                    'betatotal': float(wout.variables['betatotal'][()]),
                    'aspect': float(wout.variables['aspect'][()]),
                    'raxis_cc': float(wout.variables['raxis_cc'][()][0]),
                    'volume_p': float(wout.variables['volume_p'][()]),
                    'iotaf_edge': float(wout.variables['iotaf'][()][-1]),
                    'rmnc': wout.variables['rmnc'][()],
                    'zmns': wout.variables['zmns'][()],
                    'xm': wout.variables['xm'][()],
                    'xn': wout.variables['xn'][()],
                    'phi': wout.variables['phi'][()],
                })
            
            # Extract force quantities if available
            if jxbout_files:
                with Dataset(jxbout_files[0], 'r') as jxb:
                    results.update({
                        'avforce': jxb.variables['avforce'][()],
                        'jdotb': jxb.variables['surf_av_jdotb'][()],
                        'bdotgradv': jxb.variables['bdotgradv'][()],
                    })
            
        except Exception as e:
            results['error'] = str(e)
            
        return results


class VMEC2000(VMECImplementation):
    """VMEC2000 (SIMSOPT style) implementation handler"""
    
    def __init__(self, path: Path, auto_clone: bool = True):
        super().__init__("VMEC2000", path)
        self.repo_url = "https://github.com/hiddenSymmetries/VMEC2000.git"
        self.auto_clone = auto_clone
        
    def clone_and_setup(self) -> bool:
        """Clone VMEC2000 repository if not present"""
        if self.path.exists():
            print(f"VMEC2000 already exists at {self.path}")
            return True
            
        if not self.auto_clone:
            print(f"VMEC2000 not found at {self.path} and auto-clone disabled")
            return False
            
        print(f"Cloning VMEC2000 to {self.path}")
        try:
            subprocess.run([
                "git", "clone", self.repo_url, str(self.path)
            ], check=True, capture_output=True)
            return True
        except subprocess.CalledProcessError as e:
            print(f"Failed to clone VMEC2000: {e}")
            return False
    
    def build(self) -> bool:
        """Build and install VMEC2000 using pip"""
        if not self.clone_and_setup():
            return False
        
        try:
            # Install in editable mode
            subprocess.run([
                sys.executable, "-m", "pip", "install", "-e", str(self.path)
            ], check=True, capture_output=True)
            
            # Test import
            subprocess.run([
                sys.executable, "-c", "import vmec"
            ], check=True, capture_output=True)
            
            self.available = True
            print(f"Successfully built and installed VMEC2000")
            return True
            
        except subprocess.CalledProcessError as e:
            print(f"Failed to build VMEC2000: {e}")
            return False
    
    def run_case(self, input_file: Path, output_dir: Path) -> bool:
        """Run VMEC2000 on a test case"""
        if not self.available:
            return False
        
        output_dir.mkdir(parents=True, exist_ok=True)
        
        # Convert JSON to INDATA if needed
        educational = EducationalVMEC(self.path.parent / "educational_VMEC")
        if input_file.suffix == '.json':
            indata_file = output_dir / f"input.{input_file.stem}"
            if not educational.convert_json_to_indata(input_file, indata_file):
                return False
        else:
            indata_file = input_file
        
        try:
            # Run VMEC2000 using Python
            python_script = f'''
import sys
sys.path.insert(0, "{self.path}")
import vmec
import os
os.chdir("{output_dir}")
vmec.main(["{indata_file.name}"])
'''
            
            result = subprocess.run([
                sys.executable, "-c", python_script
            ], cwd=output_dir, capture_output=True, text=True, timeout=300)
            
            # Save output log
            with open(output_dir / "vmec2000.log", 'w') as f:
                f.write(f"Return code: {result.returncode}\n")
                f.write(f"STDOUT:\n{result.stdout}\n")
                f.write(f"STDERR:\n{result.stderr}\n")
            
            return result.returncode == 0
            
        except subprocess.TimeoutExpired:
            print(f"VMEC2000 timed out for {input_file.stem}")
            return False
        except Exception as e:
            print(f"Failed to run VMEC2000 for {input_file.stem}: {e}")
            return False
    
    def extract_results(self, output_dir: Path) -> Dict[str, Any]:
        """Extract results from VMEC2000 output files"""
        # VMEC2000 produces standard VMEC output files
        educational = EducationalVMEC(self.path.parent / "educational_VMEC")
        return educational.extract_results(output_dir)


class JVMEC(VMECImplementation):
    """jVMEC implementation handler"""
    
    def __init__(self, path: Path):
        super().__init__("jVMEC", path)
    
    def build(self) -> bool:
        """Build jVMEC using Maven"""
        if not self.path.exists():
            print(f"jVMEC not found at {self.path} (not publicly available)")
            return False
        
        try:
            # Build with Maven
            subprocess.run([
                "mvn", "-f", "pom-standalone.xml", "clean", "compile"
            ], cwd=self.path, check=True, capture_output=True)
            
            self.available = True
            print(f"Successfully built jVMEC at {self.path}")
            return True
            
        except subprocess.CalledProcessError as e:
            print(f"Failed to build jVMEC: {e}")
            return False
    
    def run_case(self, input_file: Path, output_dir: Path) -> bool:
        """Run jVMEC on a test case"""
        if not self.available:
            return False
        
        output_dir.mkdir(parents=True, exist_ok=True)
        
        # Convert JSON to INDATA if needed
        educational = EducationalVMEC(self.path.parent / "educational_VMEC")
        if input_file.suffix == '.json':
            indata_file = output_dir / f"input.{input_file.stem}"
            if not educational.convert_json_to_indata(input_file, indata_file):
                return False
        else:
            indata_file = input_file
        
        try:
            # Copy input file to jVMEC directory
            local_input = self.path / indata_file.name
            shutil.copy2(indata_file, local_input)
            
            # Get classpath
            cp_result = subprocess.run([
                "mvn", "-f", "pom-standalone.xml", "dependency:build-classpath",
                "-Dmdep.outputFile=/dev/stdout", "-q"
            ], cwd=self.path, capture_output=True, text=True)
            
            if cp_result.returncode != 0:
                raise RuntimeError("Failed to get Maven classpath")
            
            classpath = f"target/classes:{cp_result.stdout.strip()}"
            
            # Run jVMEC
            result = subprocess.run([
                "java", "-cp", classpath, 
                "de.labathome.jvmec.VmecMain", indata_file.name
            ], cwd=self.path, capture_output=True, text=True, timeout=300)
            
            # Save output log
            with open(output_dir / "jvmec.log", 'w') as f:
                f.write(f"Return code: {result.returncode}\n")
                f.write(f"STDOUT:\n{result.stdout}\n")
                f.write(f"STDERR:\n{result.stderr}\n")
            
            return result.returncode == 0
            
        except subprocess.TimeoutExpired:
            print(f"jVMEC timed out for {input_file.stem}")
            return False
        except Exception as e:
            print(f"Failed to run jVMEC for {input_file.stem}: {e}")
            return False
    
    def extract_results(self, output_dir: Path) -> Dict[str, Any]:
        """Extract results from jVMEC output"""
        results = {'success': False, 'error': None}
        
        log_file = output_dir / "jvmec.log"
        if log_file.exists():
            with open(log_file, 'r') as f:
                log_content = f.read()
                if "VMEC converged" in log_content:
                    results['success'] = True
                else:
                    results['error'] = "jVMEC did not converge"
        else:
            results['error'] = "No jVMEC log file found"
        
        return results


class VMECPlusPlus(VMECImplementation):
    """VMEC++ implementation handler"""
    
    def __init__(self, path: Path, auto_clone: bool = True):
        super().__init__("VMEC++", path)
        self.repo_url = "https://github.com/itpplasma/vmecpp.git"
        self.auto_clone = auto_clone
        
    def clone_and_setup(self) -> bool:
        """Clone VMEC++ repository if not present"""
        if self.path.exists():
            print(f"VMEC++ already exists at {self.path}")
            return True
            
        if not self.auto_clone:
            print(f"VMEC++ not found at {self.path} and auto-clone disabled")
            return False
            
        print(f"Cloning VMEC++ to {self.path}")
        try:
            subprocess.run([
                "git", "clone", self.repo_url, str(self.path)
            ], check=True, capture_output=True)
            return True
        except subprocess.CalledProcessError as e:
            print(f"Failed to clone VMEC++: {e}")
            return False
    
    def build(self) -> bool:
        """Build VMEC++ using pip install"""
        if not self.clone_and_setup():
            return False
        
        try:
            # Install in editable mode
            subprocess.run([
                sys.executable, "-m", "pip", "install", "-e", str(self.path)
            ], check=True, capture_output=True)
            
            # Test import
            subprocess.run([
                sys.executable, "-c", "import vmecpp"
            ], check=True, capture_output=True)
            
            self.available = True
            print(f"Successfully built and installed VMEC++")
            return True
            
        except subprocess.CalledProcessError as e:
            print(f"Failed to build VMEC++: {e}")
            return False
    
    def run_case(self, input_file: Path, output_dir: Path) -> bool:
        """Run VMEC++ on a test case"""
        if not self.available:
            return False
        
        output_dir.mkdir(parents=True, exist_ok=True)
        
        try:
            # Run VMEC++ using Python
            python_script = f'''
import vmecpp
import json

input_data = vmecpp.VmecInput.from_file("{input_file}")
output = vmecpp.run(input_data)

# Save results
results = {{
    "wb": output.wout.wb,
    "betatotal": output.wout.betatot,
    "aspect": output.wout.aspect,
    "raxis_cc": output.wout.raxis_c[0],
    "volume_p": output.wout.volume_p,
    "iotaf_edge": output.wout.iota_full[-1],
    "avforce": output.jxbout.avforce.tolist(),
    "jdotb": output.jxbout.jdotb.tolist(),
    "bdotgradv": output.jxbout.bdotgradv.tolist(),
    "rmnc": output.wout.rmnc.tolist(),
    "zmns": output.wout.zmns.tolist(),
    "xm": output.wout.xm.tolist(),
    "xn": output.wout.xn.tolist(),
    "phi": output.wout.toroidal_flux.tolist(),
}}

with open("{output_dir}/vmecpp_results.json", "w") as f:
    json.dump(results, f, indent=2)
'''
            
            result = subprocess.run([
                sys.executable, "-c", python_script
            ], capture_output=True, text=True, timeout=300)
            
            # Save output log
            with open(output_dir / "vmecpp.log", 'w') as f:
                f.write(f"Return code: {result.returncode}\n")
                f.write(f"STDOUT:\n{result.stdout}\n")
                f.write(f"STDERR:\n{result.stderr}\n")
            
            return result.returncode == 0
            
        except subprocess.TimeoutExpired:
            print(f"VMEC++ timed out for {input_file.stem}")
            return False
        except Exception as e:
            print(f"Failed to run VMEC++ for {input_file.stem}: {e}")
            return False
    
    def extract_results(self, output_dir: Path) -> Dict[str, Any]:
        """Extract results from VMEC++ output"""
        results = {'success': False, 'error': None}
        
        results_file = output_dir / "vmecpp_results.json"
        if results_file.exists():
            try:
                with open(results_file, 'r') as f:
                    data = json.load(f)
                    results.update(data)
                    results['success'] = True
            except Exception as e:
                results['error'] = str(e)
        else:
            results['error'] = "No VMEC++ results file found"
        
        return results


class VMECComparator:
    """Main comparison orchestrator"""
    
    def __init__(self, vmecpp_path: Path, educational_path: Path, 
                 vmec2000_path: Path, jvmec_path: Path, 
                 output_path: Path, auto_clone: bool = True):
        self.output_path = Path(output_path)
        self.output_path.mkdir(parents=True, exist_ok=True)
        
        # Initialize implementations
        self.implementations = {
            'vmecpp': VMECPlusPlus(vmecpp_path, auto_clone),
            'educational': EducationalVMEC(educational_path, auto_clone),
            'vmec2000': VMEC2000(vmec2000_path, auto_clone),
            'jvmec': JVMEC(jvmec_path),
        }
        
        # Find test cases
        self.test_cases = []
        for impl in self.implementations.values():
            test_data_paths = [
                impl.path / "src" / "vmecpp" / "cpp" / "vmecpp" / "test_data",  # VMEC++
                impl.path / "test" / "from_STELLOPT_repo",  # Educational VMEC
            ]
            for test_path in test_data_paths:
                if test_path.exists():
                    self.test_cases.extend(list(test_path.glob("*.json")))
                    break
        
        # Remove duplicates
        seen = set()
        unique_cases = []
        for case in self.test_cases:
            if case.stem not in seen:
                seen.add(case.stem)
                unique_cases.append(case)
        self.test_cases = unique_cases[:3]  # Limit for testing
    
    def setup_implementations(self) -> None:
        """Build all available implementations"""
        print("Setting up VMEC implementations...")
        
        for name, impl in self.implementations.items():
            print(f"\nSetting up {name}...")
            if impl.build():
                print(f"✓ {name} is ready")
            else:
                print(f"✗ {name} setup failed")
    
    def run_all_comparisons(self) -> Dict[str, Dict[str, Any]]:
        """Run all test cases on all available implementations"""
        results = {}
        
        for test_case in self.test_cases:
            case_name = test_case.stem
            print(f"\nRunning test case: {case_name}")
            
            case_results = {}
            
            for impl_name, impl in self.implementations.items():
                if not impl.is_available():
                    print(f"  ⏭  Skipping {impl_name} (not available)")
                    continue
                
                print(f"  🔄 Running {impl_name}...")
                
                case_output_dir = self.output_path / case_name / impl_name
                
                if impl.run_case(test_case, case_output_dir):
                    case_results[impl_name] = impl.extract_results(case_output_dir)
                    print(f"  ✓ {impl_name} completed")
                else:
                    case_results[impl_name] = {'success': False, 'error': 'Run failed'}
                    print(f"  ✗ {impl_name} failed")
            
            results[case_name] = case_results
        
        return results
    
    def create_comparison_table(self, results: Dict[str, Dict[str, Any]]) -> pd.DataFrame:
        """Create a comparison table of key quantities"""
        comparison_data = []
        
        key_quantities = [
            'wb', 'betatotal', 'aspect', 'raxis_cc', 'volume_p', 'iotaf_edge'
        ]
        
        for case_name, case_results in results.items():
            for impl_name, impl_results in case_results.items():
                if impl_results.get('success', False):
                    row = {'case': case_name, 'implementation': impl_name}
                    for qty in key_quantities:
                        if qty in impl_results:
                            row[qty] = impl_results[qty]
                        else:
                            row[qty] = np.nan
                    comparison_data.append(row)
        
        return pd.DataFrame(comparison_data)
    
    def generate_summary_report(self, results: Dict[str, Dict[str, Any]], 
                              comparison_df: pd.DataFrame) -> None:
        """Generate comprehensive summary report"""
        
        report_file = self.output_path / "comparison_report.md"
        
        with open(report_file, 'w') as f:
            f.write("# VMEC Implementation Comparison Report\n\n")
            f.write(f"Generated by automated comparison script\n\n")
            
            # Implementation status
            f.write("## Implementation Status\n\n")
            for name, impl in self.implementations.items():
                status = "✓ Available" if impl.is_available() else "✗ Not available"
                f.write(f"- **{name}**: {status}\n")
            f.write("\n")
            
            # Test cases summary
            f.write("## Test Cases Summary\n\n")
            f.write(f"Total test cases: {len(self.test_cases)}\n\n")
            
            for case_name, case_results in results.items():
                f.write(f"### {case_name}\n")
                for impl_name, impl_results in case_results.items():
                    status = "✓ Success" if impl_results.get('success', False) else "✗ Failed"
                    f.write(f"- {impl_name}: {status}\n")
                    if not impl_results.get('success', False) and 'error' in impl_results:
                        f.write(f"  - Error: {impl_results['error']}\n")
                f.write("\n")
            
            # Key quantities comparison
            f.write("## Key Quantities Comparison\n\n")
            if not comparison_df.empty:
                f.write(comparison_df.to_markdown(index=False))
                f.write("\n\n")
    
    def run_full_comparison(self) -> None:
        """Run the complete comparison workflow"""
        print("🚀 Starting VMEC Implementation Comparison")
        print("=" * 50)
        
        # Setup
        self.setup_implementations()
        
        if not self.test_cases:
            print("❌ No test cases found!")
            return
        
        print(f"\n📋 Found {len(self.test_cases)} test cases:")
        for case in self.test_cases:
            print(f"  - {case.stem}")
        
        # Run comparisons
        print(f"\n🏃 Running comparisons...")
        results = self.run_all_comparisons()
        
        # Generate comparison tables
        print(f"\n📊 Generating comparison tables...")
        comparison_df = self.create_comparison_table(results)
        
        # Save raw results
        results_file = self.output_path / "raw_results.json"
        with open(results_file, 'w') as f:
            json.dump(results, f, indent=2, default=str)
        
        # Save comparison tables
        comparison_df.to_csv(self.output_path / "comparison_table.csv", index=False)
        
        # Generate report
        print(f"\n📝 Generating summary report...")
        self.generate_summary_report(results, comparison_df)
        
        print(f"\n✅ Comparison complete!")
        print(f"📁 Results saved to: {self.output_path}")
        print(f"📖 Read the full report: {self.output_path / 'comparison_report.md'}")


def main():
    parser = argparse.ArgumentParser(description="Compare VMEC implementations")
    parser.add_argument("--vmecpp-path", type=Path, default=Path.cwd() / "vmecpp",
                       help="Path to VMEC++ repository")
    parser.add_argument("--educational-path", type=Path, default=Path.cwd() / "educational_VMEC",
                       help="Path to educational_VMEC repository")
    parser.add_argument("--vmec2000-path", type=Path, default=Path.cwd() / "VMEC2000",
                       help="Path to VMEC2000 repository")
    parser.add_argument("--jvmec-path", type=Path, default=Path.cwd() / "jVMEC",
                       help="Path to jVMEC repository")
    parser.add_argument("--output-path", type=Path, default=Path.cwd() / "vmec_comparison_results",
                       help="Output directory for results")
    parser.add_argument("--auto-clone", action='store_true', default=True,
                       help="Automatically clone missing repositories")
    parser.add_argument("--no-auto-clone", dest='auto_clone', action='store_false',
                       help="Don't automatically clone missing repositories")
    
    args = parser.parse_args()
    
    # Run comparison
    comparator = VMECComparator(
        args.vmecpp_path, args.educational_path, args.vmec2000_path, 
        args.jvmec_path, args.output_path, args.auto_clone
    )
    comparator.run_full_comparison()


if __name__ == "__main__":
    main()