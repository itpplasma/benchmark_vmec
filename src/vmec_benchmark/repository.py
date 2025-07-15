"""Repository management module for VMEC implementations."""

import logging
import shutil
from pathlib import Path
from typing import Dict, Optional

import git

logger = logging.getLogger(__name__)


class RepositoryConfig:
    """Configuration for a VMEC repository."""
    
    def __init__(
        self,
        name: str,
        url: str,
        branch: str = "main",
        build_command: Optional[str] = None,
        test_data_path: Optional[str] = None,
    ):
        self.name = name
        self.url = url
        self.branch = branch
        self.build_command = build_command
        self.test_data_path = test_data_path


DEFAULT_REPOSITORIES = {
    "educational_vmec": RepositoryConfig(
        name="educational_VMEC",
        url="https://github.com/hiddenSymmetries/educational_VMEC.git",
        branch="main",
        build_command="cmake",
        test_data_path="test/from_STELLOPT_repo",
    ),
    "vmec2000": RepositoryConfig(
        name="VMEC2000",
        url="https://github.com/hiddenSymmetries/VMEC2000.git",
        branch="main",
        build_command="pip",
        test_data_path=None,
    ),
    "vmecpp": RepositoryConfig(
        name="VMEC++",
        url="https://github.com/itpplasma/vmecpp.git",
        branch="main",
        build_command="pip",
        test_data_path="src/vmecpp/test_data",
    ),
}


class RepositoryManager:
    """Manages cloning and updating VMEC repositories."""
    
    def __init__(self, base_path: Path):
        """Initialize repository manager.
        
        Args:
            base_path: Base directory for storing repositories
        """
        self.base_path = Path(base_path)
        self.base_path.mkdir(parents=True, exist_ok=True)
        self.repositories: Dict[str, RepositoryConfig] = DEFAULT_REPOSITORIES.copy()
    
    def add_repository(self, key: str, config: RepositoryConfig) -> None:
        """Add a custom repository configuration.
        
        Args:
            key: Unique identifier for the repository
            config: Repository configuration
        """
        self.repositories[key] = config
    
    def get_repo_path(self, key: str) -> Path:
        """Get the local path for a repository.
        
        Args:
            key: Repository identifier
            
        Returns:
            Path to the repository
        """
        return self.base_path / key
    
    def is_cloned(self, key: str) -> bool:
        """Check if a repository is already cloned.
        
        Args:
            key: Repository identifier
            
        Returns:
            True if repository exists
        """
        repo_path = self.get_repo_path(key)
        return repo_path.exists() and (repo_path / ".git").exists()
    
    def clone(self, key: str, force: bool = False) -> Path:
        """Clone a repository.
        
        Args:
            key: Repository identifier
            force: Force reclone if repository exists
            
        Returns:
            Path to cloned repository
            
        Raises:
            KeyError: If repository key is not found
            RuntimeError: If cloning fails
        """
        if key not in self.repositories:
            raise KeyError(f"Unknown repository: {key}")
        
        config = self.repositories[key]
        repo_path = self.get_repo_path(key)
        
        if self.is_cloned(key) and not force:
            logger.info(f"{config.name} already cloned at {repo_path}")
            return repo_path
        
        if repo_path.exists() and force:
            logger.info(f"Removing existing {config.name} repository")
            shutil.rmtree(repo_path)
        
        logger.info(f"Cloning {config.name} from {config.url}")
        try:
            repo = git.Repo.clone_from(
                config.url,
                repo_path,
                branch=config.branch,
                depth=1,  # Shallow clone for faster download
            )
            logger.info(f"Successfully cloned {config.name}")
            return repo_path
        except Exception as e:
            logger.error(f"Failed to clone {config.name}: {e}")
            if repo_path.exists():
                shutil.rmtree(repo_path)
            raise RuntimeError(f"Failed to clone {config.name}: {e}")
    
    def update(self, key: str) -> None:
        """Update a repository to latest version.
        
        Args:
            key: Repository identifier
            
        Raises:
            KeyError: If repository key is not found
            RuntimeError: If repository is not cloned or update fails
        """
        if key not in self.repositories:
            raise KeyError(f"Unknown repository: {key}")
        
        if not self.is_cloned(key):
            raise RuntimeError(f"Repository {key} is not cloned")
        
        config = self.repositories[key]
        repo_path = self.get_repo_path(key)
        
        logger.info(f"Updating {config.name}")
        try:
            repo = git.Repo(repo_path)
            origin = repo.remotes.origin
            origin.pull()
            logger.info(f"Successfully updated {config.name}")
        except Exception as e:
            logger.error(f"Failed to update {config.name}: {e}")
            raise RuntimeError(f"Failed to update {config.name}: {e}")
    
    def clone_all(self, force: bool = False) -> Dict[str, Path]:
        """Clone all configured repositories.
        
        Args:
            force: Force reclone existing repositories
            
        Returns:
            Dictionary mapping repository keys to paths
        """
        paths = {}
        for key in self.repositories:
            try:
                paths[key] = self.clone(key, force=force)
            except Exception as e:
                logger.warning(f"Failed to clone {key}: {e}")
        return paths
    
    def update_all(self) -> None:
        """Update all cloned repositories."""
        for key in self.repositories:
            if self.is_cloned(key):
                try:
                    self.update(key)
                except Exception as e:
                    logger.warning(f"Failed to update {key}: {e}")
    
    def get_test_data_path(self, key: str) -> Optional[Path]:
        """Get path to test data for a repository.
        
        Args:
            key: Repository identifier
            
        Returns:
            Path to test data or None if not configured
        """
        if key not in self.repositories:
            raise KeyError(f"Unknown repository: {key}")
        
        config = self.repositories[key]
        if not config.test_data_path:
            return None
        
        repo_path = self.get_repo_path(key)
        test_path = repo_path / config.test_data_path
        
        if test_path.exists():
            return test_path
        return None