"""jVMEC implementation wrapper."""

import logging
import shutil
import subprocess
from pathlib import Path
from typing import Any, Dict

from .base import VMECImplementation
from .educational import EducationalVMEC

logger = logging.getLogger(__name__)


class JVMEC(VMECImplementation):
    """jVMEC implementation handler."""
    
    def __init__(self, path: Path):
        """Initialize jVMEC.
        
        Args:
            path: Path to jVMEC directory
        """
        super().__init__("jVMEC", path)
    
    def build(self) -> bool:
        """Build jVMEC using Maven."""
        if not self.path.exists():
            logger.info(f"jVMEC not found at {self.path} (not publicly available)")
            return False
        
        try:
            # Build with Maven
            logger.info("Building jVMEC with Maven")
            result = subprocess.run(
                ["mvn", "-f", "pom-standalone.xml", "clean", "compile"],
                cwd=self.path,
                capture_output=True,
                text=True,
                check=True,
            )
            
            self.available = True
            logger.info(f"Successfully built jVMEC at {self.path}")
            return True
            
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to build jVMEC: {e}")
            if e.stdout:
                logger.error(f"stdout: {e.stdout}")
            if e.stderr:
                logger.error(f"stderr: {e.stderr}")
            return False
        except FileNotFoundError:
            logger.error("Maven (mvn) not found. Please install Maven to build jVMEC.")
            return False
    
    def run_case(self, input_file: Path, output_dir: Path, **kwargs) -> bool:
        """Run jVMEC on a test case.
        
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
            logger.error("jVMEC is not available")
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
            # Copy input file to jVMEC directory
            local_input = self.path / indata_file.name
            shutil.copy2(indata_file, local_input)
            
            # Get classpath
            logger.info("Getting Maven classpath")
            cp_result = subprocess.run(
                [
                    "mvn", "-f", "pom-standalone.xml", "dependency:build-classpath",
                    "-Dmdep.outputFile=/dev/stdout", "-q"
                ],
                cwd=self.path,
                capture_output=True,
                text=True,
                check=True,
            )
            
            classpath = f"target/classes:{cp_result.stdout.strip()}"
            
            # Run jVMEC
            logger.info("Running jVMEC")
            timeout = kwargs.get('timeout', 300)
            result = subprocess.run(
                [
                    "java", "-cp", classpath,
                    "de.labathome.jvmec.VmecMain", indata_file.name
                ],
                cwd=self.path,
                capture_output=True,
                text=True,
                timeout=timeout,
            )
            
            # Save output log
            with open(output_dir / "jvmec.log", 'w') as f:
                f.write(f"Return code: {result.returncode}\n")
                f.write(f"STDOUT:\n{result.stdout}\n")
                f.write(f"STDERR:\n{result.stderr}\n")
            
            # Copy output files back to output directory
            for pattern in ["wout_*.nc", "jxbout_*.nc", "*.txt"]:
                for output_file in self.path.glob(pattern):
                    if output_file.is_file():
                        shutil.copy2(output_file, output_dir)
            
            if result.returncode != 0:
                logger.error(f"jVMEC failed with return code {result.returncode}")
                return False
            
            return True
            
        except subprocess.TimeoutExpired:
            logger.error(f"jVMEC timed out for {input_file.stem}")
            return False
        except Exception as e:
            logger.error(f"Failed to run jVMEC for {input_file.stem}: {e}")
            return False
    
    def extract_results(self, output_dir: Path) -> Dict[str, Any]:
        """Extract results from jVMEC output.
        
        Args:
            output_dir: Directory containing output files
            
        Returns:
            Dictionary with extracted results
        """
        # Check if jVMEC produced standard output files
        wout_files = list(output_dir.glob("wout_*.nc"))
        if wout_files:
            # Use standard extraction if NetCDF files are available
            educational = EducationalVMEC(self.path.parent / "educational_VMEC")
            return educational.extract_results(output_dir)
        
        # Otherwise parse log file
        results = {'success': False, 'error': None}
        
        log_file = output_dir / "jvmec.log"
        if log_file.exists():
            with open(log_file, 'r') as f:
                log_content = f.read()
                if "VMEC converged" in log_content or "Successfully" in log_content:
                    results['success'] = True
                    # Try to extract some values from log
                    # This is implementation-specific and may need adjustment
                else:
                    results['error'] = "jVMEC did not converge"
        else:
            results['error'] = "No jVMEC log file found"
        
        return results