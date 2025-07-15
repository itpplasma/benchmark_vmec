"""Command-line interface for VMEC benchmark suite."""

import logging
import sys
from pathlib import Path

import click

from . import __version__
from .repository import RepositoryManager
from .runner import BenchmarkRunner
from .comparator import ResultsComparator

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)

logger = logging.getLogger(__name__)


@click.group()
@click.version_option(version=__version__)
def cli():
    """VMEC Benchmark Suite - Compare different VMEC implementations."""
    pass


@cli.command()
@click.option(
    '--base-dir',
    type=click.Path(path_type=Path),
    default=Path.cwd() / 'vmec_repos',
    help='Base directory for repositories'
)
@click.option(
    '--force',
    is_flag=True,
    help='Force reclone repositories'
)
def setup(base_dir: Path, force: bool):
    """Clone and setup VMEC repositories."""
    logger.info(f"Setting up repositories in {base_dir}")
    
    repo_manager = RepositoryManager(base_dir)
    
    # Clone all repositories
    paths = repo_manager.clone_all(force=force)
    
    logger.info("\nRepository setup complete:")
    for key, path in paths.items():
        logger.info(f"  {key}: {path}")
    
    if len(paths) < len(repo_manager.repositories):
        logger.warning("\nSome repositories failed to clone")


@cli.command()
@click.option(
    '--base-dir',
    type=click.Path(path_type=Path),
    default=Path.cwd() / 'vmec_repos',
    help='Base directory for repositories'
)
@click.option(
    '--output-dir',
    type=click.Path(path_type=Path),
    default=Path.cwd() / 'benchmark_results',
    help='Output directory for results'
)
@click.option(
    '--implementations',
    '-i',
    multiple=True,
    help='Implementations to benchmark (can specify multiple)'
)
@click.option(
    '--cases',
    '-c',
    multiple=True,
    help='Test cases to run (can specify multiple)'
)
@click.option(
    '--limit',
    type=int,
    help='Limit number of test cases'
)
@click.option(
    '--timeout',
    type=int,
    default=300,
    help='Timeout per case in seconds'
)
def run(
    base_dir: Path,
    output_dir: Path,
    implementations: tuple,
    cases: tuple,
    limit: int,
    timeout: int
):
    """Run benchmarks on VMEC implementations."""
    logger.info("Starting VMEC benchmark run")
    
    # Initialize components
    repo_manager = RepositoryManager(base_dir)
    runner = BenchmarkRunner(output_dir, repo_manager)
    
    # Setup implementations
    runner.setup_implementations()
    
    if not runner.implementations:
        logger.error("No implementations available!")
        logger.info("Run 'vmec-benchmark setup' first to clone repositories")
        sys.exit(1)
    
    logger.info(f"\nAvailable implementations: {', '.join(runner.get_available_implementations())}")
    
    # Discover test cases
    runner.discover_test_cases(limit=limit)
    
    if not runner.test_cases:
        logger.error("No test cases found!")
        sys.exit(1)
    
    logger.info(f"Found {len(runner.test_cases)} test cases")
    
    # Run benchmarks
    impl_list = list(implementations) if implementations else None
    case_list = list(cases) if cases else None
    
    results = runner.run_all_cases(
        implementations=impl_list,
        cases=case_list,
        timeout=timeout
    )
    
    # Generate comparison report
    if results:
        comparator = ResultsComparator(results)
        
        # Generate report
        report_file = output_dir / "comparison_report.md"
        comparator.generate_report(report_file)
        
        # Export CSV files
        comparator.export_to_csv(output_dir)
        
        logger.info(f"\n✅ Benchmark complete!")
        logger.info(f"📁 Results saved to: {output_dir}")
        logger.info(f"📖 Read the report: {report_file}")
    else:
        logger.error("No results to compare")


@cli.command()
@click.option(
    '--base-dir',
    type=click.Path(path_type=Path),
    default=Path.cwd() / 'vmec_repos',
    help='Base directory for repositories'
)
def update(base_dir: Path):
    """Update all cloned repositories."""
    logger.info(f"Updating repositories in {base_dir}")
    
    repo_manager = RepositoryManager(base_dir)
    repo_manager.update_all()
    
    logger.info("Update complete")


@cli.command()
@click.option(
    '--base-dir',
    type=click.Path(path_type=Path),
    default=Path.cwd() / 'vmec_repos',
    help='Base directory for repositories'
)
def list_repos(base_dir: Path):
    """List available repositories and their status."""
    repo_manager = RepositoryManager(base_dir)
    
    logger.info("Repository status:")
    for key, config in repo_manager.repositories.items():
        status = "✓ Cloned" if repo_manager.is_cloned(key) else "✗ Not cloned"
        logger.info(f"  {key}: {status}")
        logger.info(f"    Name: {config.name}")
        logger.info(f"    URL: {config.url}")


@cli.command()
@click.option(
    '--base-dir',
    type=click.Path(path_type=Path),
    default=Path.cwd() / 'vmec_repos',
    help='Base directory for repositories'
)
def list_cases(base_dir: Path):
    """List available test cases."""
    repo_manager = RepositoryManager(base_dir)
    
    logger.info("Available test cases:")
    
    for repo_key in ["educational_vmec", "vmecpp"]:
        test_path = repo_manager.get_test_data_path(repo_key)
        if test_path:
            logger.info(f"\nFrom {repo_key}:")
            
            # JSON files
            json_files = list(test_path.glob("*.json"))
            if json_files:
                logger.info("  JSON inputs:")
                for f in sorted(json_files)[:10]:  # Show first 10
                    logger.info(f"    - {f.stem}")
                if len(json_files) > 10:
                    logger.info(f"    ... and {len(json_files) - 10} more")
            
            # Input files
            input_files = list(test_path.glob("input.*"))
            if input_files:
                logger.info("  INDATA inputs:")
                for f in sorted(input_files)[:10]:  # Show first 10
                    logger.info(f"    - {f.stem}")
                if len(input_files) > 10:
                    logger.info(f"    ... and {len(input_files) - 10} more")


def main():
    """Main entry point."""
    cli()


if __name__ == "__main__":
    main()