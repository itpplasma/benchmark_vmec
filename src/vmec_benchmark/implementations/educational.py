"""Educational VMEC implementation wrapper."""

import json
import logging
import shutil
import subprocess
from pathlib import Path
from typing import Any, Dict

from netCDF4 import Dataset

from .base import VMECImplementation

logger = logging.getLogger(__name__)


class EducationalVMEC(VMECImplementation):
    """Educational VMEC implementation handler."""
    
    def __init__(self, path: Path):
        """Initialize Educational VMEC.
        
        Args:
            path: Path to educational_VMEC directory
        """
        super().__init__("Educational_VMEC", path)
    
    def build(self) -> bool:
        """Build educational_VMEC using CMake."""
        if not self.path.exists():
            logger.error(f"Educational VMEC path does not exist: {self.path}")
            return False
        
        build_dir = self.path / "build"
        build_dir.mkdir(exist_ok=True)
        
        try:
            # Configure with CMake
            logger.info("Configuring Educational VMEC with CMake")
            result = subprocess.run(
                ["cmake", ".."],
                cwd=build_dir,
                capture_output=True,
                text=True,
                check=True,
            )
            
            # Build
            logger.info("Building Educational VMEC")
            result = subprocess.run(
                ["make", "-j", str(subprocess.os.cpu_count() or 4)],
                cwd=build_dir,
                capture_output=True,
                text=True,
                check=True,
            )
            
            # Check if executable exists
            self.executable = build_dir / "bin" / "xvmec"
            if self.executable.exists():
                self.available = True
                logger.info(f"Successfully built educational_VMEC at {self.executable}")
                return True
            else:
                logger.error("Build completed but executable not found")
                return False
                
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to build educational_VMEC: {e}")
            if e.stdout:
                logger.error(f"stdout: {e.stdout}")
            if e.stderr:
                logger.error(f"stderr: {e.stderr}")
            return False
    
    def convert_json_to_indata(self, json_file: Path, output_file: Path) -> bool:
        """Convert VMEC++ JSON input to INDATA format.
        
        Args:
            json_file: Path to JSON input file
            output_file: Path to output INDATA file
            
        Returns:
            True if conversion was successful
        """
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
                scalar_params = [
                    'delt', 'tcon0', 'phiedge', 'nstep', 'pres_scale',
                    'gamma', 'spres_ped', 'ncurr', 'curtor', 'bloat'
                ]
                for key in scalar_params:
                    if key in data:
                        value = data[key]
                        if isinstance(value, list) and len(value) == 1:
                            value = value[0]
                        f.write(f"  {key.upper()} = {value}\n")
                
                # String parameters
                for key in ['pmass_type', 'pcurr_type']:
                    if key in data:
                        f.write(f"  {key.upper()} = \"{data[key]}\"\n")
                
                # Special arrays
                for key in ['am', 'ac', 'aphi', 'ai', 'ah', 'at', 'av']:
                    if key in data:
                        arr_str = ' '.join([f"{x:.6e}" for x in data[key]])
                        f.write(f"  {key.upper()} = {arr_str}\n")
                
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
            logger.error(f"Failed to convert {json_file} to INDATA format: {e}")
            return False
    
    def run_case(self, input_file: Path, output_dir: Path, **kwargs) -> bool:
        """Run educational_VMEC on a test case.
        
        Args:
            input_file: Path to input file
            output_dir: Directory for output files
            **kwargs: Additional options
            
        Returns:
            True if run was successful
        """
        if not self.validate_input(input_file):
            return False
        
        if not self.prepare_output_dir(output_dir):
            return False
        
        if not self.available:
            logger.error("Educational VMEC is not available")
            return False
        
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
            if local_input != indata_file:
                shutil.copy2(indata_file, local_input)
            
            # Run educational_VMEC
            timeout = kwargs.get('timeout', 300)
            result = subprocess.run(
                [str(self.executable), local_input.name],
                cwd=output_dir,
                capture_output=True,
                text=True,
                timeout=timeout,
            )
            
            # Save output log
            with open(output_dir / "educational_vmec.log", 'w') as f:
                f.write(f"Return code: {result.returncode}\n")
                f.write(f"STDOUT:\n{result.stdout}\n")
                f.write(f"STDERR:\n{result.stderr}\n")
            
            if result.returncode != 0:
                logger.error(f"Educational VMEC failed with return code {result.returncode}")
                return False
            
            return True
            
        except subprocess.TimeoutExpired:
            logger.error(f"Educational VMEC timed out for {input_file.stem}")
            return False
        except Exception as e:
            logger.error(f"Failed to run educational_VMEC for {input_file.stem}: {e}")
            return False
    
    def extract_results(self, output_dir: Path) -> Dict[str, Any]:
        """Extract results from educational_VMEC output files.
        
        Args:
            output_dir: Directory containing output files
            
        Returns:
            Dictionary with extracted results
        """
        results = {'success': False, 'error': None}
        
        try:
            # Look for wout file
            wout_files = list(output_dir.glob("wout_*.nc"))
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
            jxbout_files = list(output_dir.glob("jxbout_*.nc"))
            if jxbout_files:
                with Dataset(jxbout_files[0], 'r') as jxb:
                    results.update({
                        'avforce': jxb.variables['avforce'][()],
                        'jdotb': jxb.variables['surf_av_jdotb'][()],
                        'bdotgradv': jxb.variables['bdotgradv'][()],
                    })
            
        except Exception as e:
            results['error'] = str(e)
            logger.error(f"Failed to extract results: {e}")
            
        return results