"""Persistent paths for the Windows app installation."""
from pathlib import Path


def data_root(app_root=None):
    """Return the mutable data directory beside the installed application."""
    root = Path(app_root) if app_root is not None else Path(__file__).resolve().parents[1]
    return root / "data"
