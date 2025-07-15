"""Results comparison module."""

import logging
from pathlib import Path
from typing import Any, Dict, List, Optional

import numpy as np
import pandas as pd

logger = logging.getLogger(__name__)


class ResultsComparator:
    """Compares results across implementations."""
    
    def __init__(self, results: Dict[str, Dict[str, Any]]):
        """Initialize comparator with results.
        
        Args:
            results: Nested dictionary of results by case and implementation
        """
        self.results = results
        self.key_quantities = [
            'wb',           # Magnetic energy
            'betatotal',    # Total beta
            'aspect',       # Aspect ratio
            'raxis_cc',     # Major radius
            'volume_p',     # Plasma volume
            'iotaf_edge',   # Edge rotational transform
        ]
    
    def create_comparison_table(
        self,
        quantities: Optional[List[str]] = None
    ) -> pd.DataFrame:
        """Create comparison table of key quantities.
        
        Args:
            quantities: List of quantities to compare (None = use defaults)
            
        Returns:
            DataFrame with comparison data
        """
        if quantities is None:
            quantities = self.key_quantities
        
        comparison_data = []
        
        for case_name, case_results in self.results.items():
            for impl_name, impl_results in case_results.items():
                if impl_results.get('success', False):
                    row = {
                        'case': case_name,
                        'implementation': impl_name
                    }
                    for qty in quantities:
                        if qty in impl_results:
                            row[qty] = impl_results[qty]
                        else:
                            row[qty] = np.nan
                    comparison_data.append(row)
        
        df = pd.DataFrame(comparison_data)
        
        # Sort by case and implementation for better readability
        if not df.empty:
            df = df.sort_values(['case', 'implementation'])
        
        return df
    
    def calculate_relative_differences(
        self,
        reference_impl: str,
        quantities: Optional[List[str]] = None
    ) -> pd.DataFrame:
        """Calculate relative differences with respect to reference implementation.
        
        Args:
            reference_impl: Reference implementation key
            quantities: List of quantities to compare
            
        Returns:
            DataFrame with relative differences
        """
        if quantities is None:
            quantities = self.key_quantities
        
        diff_data = []
        
        for case_name, case_results in self.results.items():
            # Get reference values
            if reference_impl not in case_results:
                logger.warning(f"Reference {reference_impl} not found for {case_name}")
                continue
            
            ref_results = case_results[reference_impl]
            if not ref_results.get('success', False):
                logger.warning(f"Reference {reference_impl} failed for {case_name}")
                continue
            
            # Compare other implementations
            for impl_name, impl_results in case_results.items():
                if impl_name == reference_impl:
                    continue
                
                if not impl_results.get('success', False):
                    continue
                
                row = {
                    'case': case_name,
                    'implementation': impl_name,
                    'reference': reference_impl
                }
                
                for qty in quantities:
                    if qty in ref_results and qty in impl_results:
                        ref_val = ref_results[qty]
                        impl_val = impl_results[qty]
                        
                        if ref_val != 0:
                            rel_diff = (impl_val - ref_val) / abs(ref_val)
                            row[f'{qty}_rel_diff'] = rel_diff
                            row[f'{qty}_abs_diff'] = impl_val - ref_val
                        else:
                            row[f'{qty}_rel_diff'] = np.nan
                            row[f'{qty}_abs_diff'] = impl_val - ref_val
                
                diff_data.append(row)
        
        return pd.DataFrame(diff_data)
    
    def get_convergence_summary(self) -> pd.DataFrame:
        """Get summary of which cases converged for each implementation.
        
        Returns:
            DataFrame with convergence summary
        """
        summary_data = []
        
        # Get all implementations
        all_impls = set()
        for case_results in self.results.values():
            all_impls.update(case_results.keys())
        
        for case_name, case_results in self.results.items():
            row = {'case': case_name}
            
            for impl in sorted(all_impls):
                if impl in case_results:
                    success = case_results[impl].get('success', False)
                    row[impl] = '✓' if success else '✗'
                else:
                    row[impl] = '-'
            
            summary_data.append(row)
        
        return pd.DataFrame(summary_data)
    
    def generate_report(self, output_file: Path) -> None:
        """Generate comprehensive comparison report.
        
        Args:
            output_file: Path to output markdown file
        """
        with open(output_file, 'w') as f:
            f.write("# VMEC Implementation Comparison Report\n\n")
            
            # Convergence summary
            f.write("## Convergence Summary\n\n")
            convergence_df = self.get_convergence_summary()
            if not convergence_df.empty:
                f.write(convergence_df.to_markdown(index=False))
                f.write("\n\n")
            
            # Key quantities comparison
            f.write("## Key Quantities Comparison\n\n")
            comparison_df = self.create_comparison_table()
            
            if not comparison_df.empty:
                # Group by case for better readability
                for case_name in comparison_df['case'].unique():
                    f.write(f"### {case_name}\n\n")
                    case_df = comparison_df[comparison_df['case'] == case_name]
                    case_df = case_df.drop('case', axis=1)
                    f.write(case_df.to_markdown(index=False))
                    f.write("\n\n")
            
            # Relative differences
            f.write("## Relative Differences\n\n")
            
            # Find most common implementation to use as reference
            impl_counts = {}
            for case_results in self.results.values():
                for impl in case_results:
                    if case_results[impl].get('success', False):
                        impl_counts[impl] = impl_counts.get(impl, 0) + 1
            
            if impl_counts:
                reference_impl = max(impl_counts, key=impl_counts.get)
                f.write(f"Using {reference_impl} as reference implementation\n\n")
                
                diff_df = self.calculate_relative_differences(reference_impl)
                if not diff_df.empty:
                    # Show summary statistics
                    f.write("### Summary Statistics\n\n")
                    
                    for qty in self.key_quantities:
                        rel_col = f'{qty}_rel_diff'
                        if rel_col in diff_df.columns:
                            stats = diff_df[rel_col].describe()
                            f.write(f"**{qty}**:\n")
                            f.write(f"- Mean relative difference: {stats['mean']:.2e}\n")
                            f.write(f"- Max relative difference: {stats['max']:.2e}\n")
                            f.write(f"- Min relative difference: {stats['min']:.2e}\n\n")
            
            logger.info(f"Report saved to {output_file}")
    
    def export_to_csv(self, output_dir: Path) -> None:
        """Export comparison data to CSV files.
        
        Args:
            output_dir: Directory for CSV files
        """
        output_dir.mkdir(parents=True, exist_ok=True)
        
        # Export comparison table
        comparison_df = self.create_comparison_table()
        if not comparison_df.empty:
            comparison_df.to_csv(output_dir / "comparison_table.csv", index=False)
        
        # Export convergence summary
        convergence_df = self.get_convergence_summary()
        if not convergence_df.empty:
            convergence_df.to_csv(output_dir / "convergence_summary.csv", index=False)
        
        logger.info(f"CSV files exported to {output_dir}")