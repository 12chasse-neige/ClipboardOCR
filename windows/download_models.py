"""Download the official accelerated Windows VLM during setup."""
from pathlib import Path
from huggingface_hub import snapshot_download

root = Path(__file__).resolve().parents[1]
print(snapshot_download(
    "PaddlePaddle/PaddleOCR-VL-1.6-GGUF",
    revision="511b09642bb324401f15f97cc23bc67e8f0a291d",
    local_dir=root / ".windows/models/PaddleOCR-VL-1.6-GGUF",
))
