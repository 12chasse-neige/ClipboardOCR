"""Revision-pinned model downloads with bounded retries and endpoint failover.

Each endpoint runs in a new process: huggingface_hub reads configuration on
import. Local metadata reuses completed files and partial downloads. Revision
pinning alone is not a cryptographic checksum.
"""
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from windows.paths import data_root

REPO = "PaddlePaddle/PaddleOCR-VL-1.6-GGUF"
REVISION = "511b09642bb324401f15f97cc23bc67e8f0a291d"
OFFICIAL = "https://huggingface.co"
MIRROR = "https://hf-mirror.com"
FILES = ["PaddleOCR-VL-1.6-GGUF.gguf", "PaddleOCR-VL-1.6-GGUF-mmproj.gguf"]


def endpoints(environ):
    if environ.get("HF_ENDPOINT"):
        return [environ["HF_ENDPOINT"]]
    return [OFFICIAL] if environ.get("CLIPBOARD_OCR_DISABLE_MIRROR") == "1" else [OFFICIAL, MIRROR]


def download():
    from huggingface_hub import snapshot_download
    print(snapshot_download(REPO, revision=REVISION, allow_patterns=FILES,
                            local_dir=data_root() / "models/PaddleOCR-VL-1.6-GGUF", max_workers=2), flush=True)


def main():
    if "--worker" in sys.argv:
        download()
        return 0
    for endpoint in endpoints(os.environ):
        env = os.environ.copy()
        env.update(HF_ENDPOINT=endpoint, HF_HUB_DISABLE_XET="1", PYTHONUNBUFFERED="1")
        env.setdefault("HF_HUB_DOWNLOAD_TIMEOUT", "60")
        env.setdefault("HF_HUB_ETAG_TIMEOUT", "15")
        for attempt in range(1, 3):
            print(f"Model download: {endpoint}, attempt {attempt}/2; keeping cached files", flush=True)
            result = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--worker"], env=env)
            if result.returncode == 0:
                return 0
            print(f"Download failed (exit {result.returncode}); retrying or switching endpoint.", flush=True)
            if attempt < 2:
                time.sleep(2)
    print("Model download failed. Rerun setup to resume; inspect download_models.err.log.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
