"""Start the app with the managed GUI interpreter and the private runtime."""
from __future__ import annotations

import runpy
import site
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
site.addsitedir(str(ROOT / ".windows/runtime/Lib/site-packages"))
sys.path.insert(0, str(ROOT))
runpy.run_path(str(ROOT / "windows/app.py"), run_name="__main__")
