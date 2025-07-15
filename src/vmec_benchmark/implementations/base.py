"""Base class for VMEC implementations."""

import logging
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)


class VMECImplementation(ABC):
    """Abstract base class for VMEC implementations."""
    
    def __init__(self, name: str, path: Path):
        """Initialize VMEC implementation.
        
        Args:
            name: Name of the implementation
            path: Path to the implementation directory
        """
        self.name = name
        self.path = Path(path)
        self.available = False
        self.executable: Optional[Path] = None
    
    def is_available(self) -> bool:
        """Check if implementation is available and ready to use.
        
        Returns:
            True if implementation can be used
        """
        return self.available
    
    @abstractmethod
    def build(self) -> bool:
        """Build the implementation.
        
        Returns:
            True if build was successful
        """
        pass
    
    @abstractmethod
    def run_case(self, input_file: Path, output_dir: Path, **kwargs) -> bool:
        """Run a test case.
        
        Args:
            input_file: Path to input file
            output_dir: Directory for output files
            **kwargs: Additional implementation-specific options
            
        Returns:
            True if run was successful
        """
        pass
    
    @abstractmethod
    def extract_results(self, output_dir: Path) -> Dict[str, Any]:
        """Extract results from output files.
        
        Args:
            output_dir: Directory containing output files
            
        Returns:
            Dictionary with extracted results
        """
        pass
    
    def validate_input(self, input_file: Path) -> bool:
        """Validate that input file exists and is readable.
        
        Args:
            input_file: Path to input file
            
        Returns:
            True if input file is valid
        """
        if not input_file.exists():
            logger.error(f"Input file does not exist: {input_file}")
            return False
        
        if not input_file.is_file():
            logger.error(f"Input path is not a file: {input_file}")
            return False
        
        return True
    
    def prepare_output_dir(self, output_dir: Path) -> bool:
        """Prepare output directory.
        
        Args:
            output_dir: Directory for output files
            
        Returns:
            True if directory is ready
        """
        try:
            output_dir.mkdir(parents=True, exist_ok=True)
            return True
        except Exception as e:
            logger.error(f"Failed to create output directory: {e}")
            return False
    
    def __repr__(self) -> str:
        """String representation of implementation."""
        status = "available" if self.available else "not available"
        return f"{self.name} ({status}) at {self.path}"