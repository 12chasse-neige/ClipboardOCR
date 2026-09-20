"""Download the official accelerated Windows VLM during setup."""
import os
from pathlib import Path
from huggingface_hub import snapshot_download

local = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData/Local")) / "ClipboardOCR"
print(snapshot_download(
    "PaddlePaddle/PaddleOCR-VL-1.6-GGUF",
    revision="511b09642bb324401f15f97cc23bc67e8f0a291d",
    local_dir=local / "models/PaddleOCR-VL-1.6-GGUF",
))
