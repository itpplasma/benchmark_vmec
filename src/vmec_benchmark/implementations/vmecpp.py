"""VMEC++ implementation wrapper."""

import json
import logging
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict

from .base import VMECImplementation

logger = logging.getLogger(__name__)


class VMECPlusPlus(VMECImplementation):
    """VMEC++ implementation handler."""
    
    def __init__(self, path: Path):
        """Initialize VMEC++.
        
        Args:
            path: Path to VMEC++ directory
        """
        super().__init__("VMEC++", path)
    
    def build(self) -> bool:
        """Build VMEC++ using pip install."""
        if not self.path.exists():
            logger.error(f"VMEC++ path does not exist: {self.path}")
            return False
        
        try:
            # Install in editable mode
            logger.info("Installing VMEC++ with pip")
            result = subprocess.run(
                [sys.executable, "-m", "pip", "install", "-e", str(self.path)],
                capture_output=True,
                text=True,
                check=True,
            )
            
            # Test import
            logger.info("Testing VMEC++ import")
            result = subprocess.run(
                [sys.executable, "-c", "import vmecpp"],
                capture_output=True,
                text=True,
                check=True,
            )
            
            self.available = True
            logger.info("Successfully built and installed VMEC++")
            return True
            
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to build VMEC++: {e}")
            if e.stdout:
                logger.error(f"stdout: {e.stdout}")
            if e.stderr:
                logger.error(f"stderr: {e.stderr}")
            return False
    
    def run_case(self, input_file: Path, output_dir: Path, **kwargs) -> bool:
        """Run VMEC++ on a test case.
        
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
            logger.error("VMEC++ is not available")
            return False
        
        try:
            # Run VMEC++ using Python
            python_script = f'''
import vmecpp
import json
import numpy as np

# Load input data
input_data = vmecpp.VmecInput.from_file("{input_file}")

# Run VMEC
output = vmecpp.run(input_data)

# Convert numpy arrays to lists for JSON serialization
def convert_to_serializable(obj):
    if isinstance(obj, np.ndarray):
        return obj.tolist()
    elif isinstance(obj, np.integer):
        return int(obj)
    elif isinstance(obj, np.floating):
        return float(obj)
    elif isinstance(obj, dict):
        return {{k: convert_to_serializable(v) for k, v in obj.items()}}
    elif isinstance(obj, list):
        return [convert_to_serializable(item) for item in obj]
    else:
        return obj

# Save results
results = {{
    "wb": float(output.wout.wb),
    "betatotal": float(output.wout.betatot),
    "aspect": float(output.wout.aspect),
    "raxis_cc": float(output.wout.raxis_c[0]),
    "volume_p": float(output.wout.volume_p),
    "iotaf_edge": float(output.wout.iota_full[-1]),
    "rmnc": convert_to_serializable(output.wout.rmnc),
    "zmns": convert_to_serializable(output.wout.zmns),
    "xm": convert_to_serializable(output.wout.xm),
    "xn": convert_to_serializable(output.wout.xn),
    "phi": convert_to_serializable(output.wout.toroidal_flux),
}}

# Add force quantities if available
if hasattr(output, 'jxbout'):
    results.update({{
        "avforce": convert_to_serializable(output.jxbout.avforce),
        "jdotb": convert_to_serializable(output.jxbout.jdotb),
        "bdotgradv": convert_to_serializable(output.jxbout.bdotgradv),
    }})

with open("{output_dir}/vmecpp_results.json", "w") as f:
    json.dump(results, f, indent=2)
'''
            
            timeout = kwargs.get('timeout', 300)
            result = subprocess.run(
                [sys.executable, "-c", python_script],
                capture_output=True,
                text=True,
                timeout=timeout,
            )
            
            # Save output log
            with open(output_dir / "vmecpp.log", 'w') as f:
                f.write(f"Return code: {result.returncode}\n")
                f.write(f"STDOUT:\n{result.stdout}\n")
                f.write(f"STDERR:\n{result.stderr}\n")
            
            if result.returncode != 0:
                logger.error(f"VMEC++ failed with return code {result.returncode}")
                return False
            
            return True
            
        except subprocess.TimeoutExpired:
            logger.error(f"VMEC++ timed out for {input_file.stem}")
            return False
        except Exception as e:
            logger.error(f"Failed to run VMEC++ for {input_file.stem}: {e}")
            return False
    
    def extract_results(self, output_dir: Path) -> Dict[str, Any]:
        """Extract results from VMEC++ output.
        
        Args:
            output_dir: Directory containing output files
            
        Returns:
            Dictionary with extracted results
        """
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
                logger.error(f"Failed to load results: {e}")
        else:
            results['error'] = "No VMEC++ results file found"
        
        return results