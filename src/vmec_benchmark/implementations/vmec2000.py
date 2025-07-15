"""VMEC2000 implementation wrapper."""

import logging
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict

from .base import VMECImplementation
from .educational import EducationalVMEC

logger = logging.getLogger(__name__)


class VMEC2000(VMECImplementation):
    """VMEC2000 (SIMSOPT style) implementation handler."""
    
    def __init__(self, path: Path):
        """Initialize VMEC2000.
        
        Args:
            path: Path to VMEC2000 directory
        """
        super().__init__("VMEC2000", path)
    
    def build(self) -> bool:
        """Build and install VMEC2000 using pip."""
        if not self.path.exists():
            logger.error(f"VMEC2000 path does not exist: {self.path}")
            return False
        
        try:
            # Install in editable mode
            logger.info("Installing VMEC2000 with pip")
            result = subprocess.run(
                [sys.executable, "-m", "pip", "install", "-e", str(self.path)],
                capture_output=True,
                text=True,
                check=True,
            )
            
            # Test import
            logger.info("Testing VMEC2000 import")
            result = subprocess.run(
                [sys.executable, "-c", "import vmec"],
                capture_output=True,
                text=True,
                check=True,
            )
            
            self.available = True
            logger.info("Successfully built and installed VMEC2000")
            return True
            
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to build VMEC2000: {e}")
            if e.stdout:
                logger.error(f"stdout: {e.stdout}")
            if e.stderr:
                logger.error(f"stderr: {e.stderr}")
            return False
    
    def run_case(self, input_file: Path, output_dir: Path, **kwargs) -> bool:
        """Run VMEC2000 on a test case.
        
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
            logger.error("VMEC2000 is not available")
            return False
        
        # Convert JSON to INDATA if needed
        if input_file.suffix == '.json':
            educational = EducationalVMEC(self.path.parent / "educational_VMEC")
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
            
            timeout = kwargs.get('timeout', 300)
            result = subprocess.run(
                [sys.executable, "-c", python_script],
                cwd=output_dir,
                capture_output=True,
                text=True,
                timeout=timeout,
            )
            
            # Save output log
            with open(output_dir / "vmec2000.log", 'w') as f:
                f.write(f"Return code: {result.returncode}\n")
                f.write(f"STDOUT:\n{result.stdout}\n")
                f.write(f"STDERR:\n{result.stderr}\n")
            
            if result.returncode != 0:
                logger.error(f"VMEC2000 failed with return code {result.returncode}")
                return False
            
            return True
            
        except subprocess.TimeoutExpired:
            logger.error(f"VMEC2000 timed out for {input_file.stem}")
            return False
        except Exception as e:
            logger.error(f"Failed to run VMEC2000 for {input_file.stem}: {e}")
            return False
    
    def extract_results(self, output_dir: Path) -> Dict[str, Any]:
        """Extract results from VMEC2000 output files.
        
        Args:
            output_dir: Directory containing output files
            
        Returns:
            Dictionary with extracted results
        """
        # VMEC2000 produces standard VMEC output files
        educational = EducationalVMEC(self.path.parent / "educational_VMEC")
        return educational.extract_results(output_dir)