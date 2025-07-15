"""Benchmark runner module."""

import json
import logging
from pathlib import Path
from typing import Any, Dict, List, Optional

from .implementations import (
    VMECImplementation,
    EducationalVMEC,
    VMEC2000,
    VMECPlusPlus,
    JVMEC,
)
from .repository import RepositoryManager

logger = logging.getLogger(__name__)


class BenchmarkRunner:
    """Orchestrates benchmark execution across implementations."""
    
    def __init__(self, output_dir: Path, repo_manager: RepositoryManager):
        """Initialize benchmark runner.
        
        Args:
            output_dir: Directory for benchmark outputs
            repo_manager: Repository manager instance
        """
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.repo_manager = repo_manager
        self.implementations: Dict[str, VMECImplementation] = {}
        self.test_cases: List[Path] = []
    
    def setup_implementations(self) -> None:
        """Setup all available implementations."""
        logger.info("Setting up VMEC implementations...")
        
        # Educational VMEC
        if self.repo_manager.is_cloned("educational_vmec"):
            path = self.repo_manager.get_repo_path("educational_vmec")
            impl = EducationalVMEC(path)
            if impl.build():
                self.implementations["educational_vmec"] = impl
                logger.info("✓ Educational VMEC is ready")
            else:
                logger.warning("✗ Educational VMEC setup failed")
        
        # VMEC2000
        if self.repo_manager.is_cloned("vmec2000"):
            path = self.repo_manager.get_repo_path("vmec2000")
            impl = VMEC2000(path)
            if impl.build():
                self.implementations["vmec2000"] = impl
                logger.info("✓ VMEC2000 is ready")
            else:
                logger.warning("✗ VMEC2000 setup failed")
        
        # VMEC++
        if self.repo_manager.is_cloned("vmecpp"):
            path = self.repo_manager.get_repo_path("vmecpp")
            impl = VMECPlusPlus(path)
            if impl.build():
                self.implementations["vmecpp"] = impl
                logger.info("✓ VMEC++ is ready")
            else:
                logger.warning("✗ VMEC++ setup failed")
        
        # jVMEC (optional)
        jvmec_path = self.repo_manager.base_path / "jvmec"
        if jvmec_path.exists():
            impl = JVMEC(jvmec_path)
            if impl.build():
                self.implementations["jvmec"] = impl
                logger.info("✓ jVMEC is ready")
            else:
                logger.warning("✗ jVMEC setup failed")
    
    def discover_test_cases(self, limit: Optional[int] = None) -> None:
        """Discover test cases from repositories.
        
        Args:
            limit: Maximum number of test cases to use
        """
        logger.info("Discovering test cases...")
        test_cases = []
        
        # Check each repository for test data
        for repo_key in ["educational_vmec", "vmecpp"]:
            test_path = self.repo_manager.get_test_data_path(repo_key)
            if test_path:
                # Look for JSON files
                json_files = list(test_path.glob("*.json"))
                if json_files:
                    test_cases.extend(json_files)
                    logger.info(f"Found {len(json_files)} test cases in {repo_key}")
                
                # Look for input files
                input_files = list(test_path.glob("input.*"))
                if input_files:
                    test_cases.extend(input_files)
                    logger.info(f"Found {len(input_files)} input files in {repo_key}")
        
        # Remove duplicates by name
        seen = set()
        unique_cases = []
        for case in test_cases:
            if case.stem not in seen:
                seen.add(case.stem)
                unique_cases.append(case)
        
        # Apply limit if specified
        if limit:
            unique_cases = unique_cases[:limit]
        
        self.test_cases = unique_cases
        logger.info(f"Total unique test cases: {len(self.test_cases)}")
    
    def run_single_case(
        self,
        test_case: Path,
        implementation: str,
        timeout: int = 300
    ) -> Dict[str, Any]:
        """Run a single test case on one implementation.
        
        Args:
            test_case: Path to test case input file
            implementation: Implementation key
            timeout: Timeout in seconds
            
        Returns:
            Results dictionary
        """
        if implementation not in self.implementations:
            return {
                'success': False,
                'error': f'Implementation {implementation} not available'
            }
        
        impl = self.implementations[implementation]
        case_name = test_case.stem
        output_dir = self.output_dir / case_name / implementation
        
        logger.info(f"Running {case_name} on {implementation}")
        
        # Run the case
        success = impl.run_case(test_case, output_dir, timeout=timeout)
        
        if success:
            # Extract results
            results = impl.extract_results(output_dir)
            results['implementation'] = implementation
            results['case'] = case_name
            return results
        else:
            return {
                'success': False,
                'error': 'Run failed',
                'implementation': implementation,
                'case': case_name
            }
    
    def run_all_cases(
        self,
        implementations: Optional[List[str]] = None,
        cases: Optional[List[str]] = None,
        timeout: int = 300
    ) -> Dict[str, Dict[str, Any]]:
        """Run all test cases on specified implementations.
        
        Args:
            implementations: List of implementation keys to use (None = all)
            cases: List of case names to run (None = all)
            timeout: Timeout per case in seconds
            
        Returns:
            Nested dictionary of results by case and implementation
        """
        # Filter implementations
        if implementations:
            impl_keys = [k for k in implementations if k in self.implementations]
        else:
            impl_keys = list(self.implementations.keys())
        
        # Filter cases
        if cases:
            case_set = set(cases)
            test_cases = [c for c in self.test_cases if c.stem in case_set]
        else:
            test_cases = self.test_cases
        
        results = {}
        
        for test_case in test_cases:
            case_name = test_case.stem
            logger.info(f"\nRunning test case: {case_name}")
            
            case_results = {}
            
            for impl_key in impl_keys:
                result = self.run_single_case(test_case, impl_key, timeout)
                case_results[impl_key] = result
                
                if result['success']:
                    logger.info(f"  ✓ {impl_key} completed")
                else:
                    logger.warning(f"  ✗ {impl_key} failed: {result.get('error', 'Unknown error')}")
            
            results[case_name] = case_results
        
        # Save raw results
        results_file = self.output_dir / "raw_results.json"
        with open(results_file, 'w') as f:
            # Convert numpy arrays to lists for JSON serialization
            json.dump(results, f, indent=2, default=str)
        
        logger.info(f"\nResults saved to {results_file}")
        
        return results
    
    def get_available_implementations(self) -> List[str]:
        """Get list of available implementation keys.
        
        Returns:
            List of implementation keys
        """
        return list(self.implementations.keys())
    
    def get_test_case_names(self) -> List[str]:
        """Get list of test case names.
        
        Returns:
            List of test case names (stems)
        """
        return [case.stem for case in self.test_cases]