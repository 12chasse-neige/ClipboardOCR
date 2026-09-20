"""Download the official accelerated Windows VLM during setup.

huggingface.co is frequently unreachable from mainland China, and setup used to
abort there.  Probe the Hub first and fall back to the community mirror when it
cannot be reached; the revision is pinned and huggingface_hub verifies every
downloaded file against it, so the mirror serves the same bytes.  Set HF_ENDPOINT
yourself to override the choice, and CLIPBOARD_OCR_DISABLE_MIRROR=1 to keep the
official endpoint even when the probe fails.
"""
import os
import urllib.error
import urllib.request
from pathlib import Path

REPO = "PaddlePaddle/PaddleOCR-VL-1.6-GGUF"
REVISION = "511b09642bb324401f15f97cc23bc67e8f0a291d"
MIRROR = "https://hf-mirror.com"
PROBE = "https://huggingface.co/api/models/" + REPO


def huggingface_reachable():
    try:
        with urllib.request.urlopen(PROBE, timeout=10) as response:
            return response.status == 200
    except (urllib.error.URLError, OSError, ValueError):
        return False


if not os.environ.get("HF_ENDPOINT") and os.environ.get("CLIPBOARD_OCR_DISABLE_MIRROR") != "1":
    if huggingface_reachable():
        print("huggingface.co reachable")
    else:
        os.environ["HF_ENDPOINT"] = MIRROR
        # The Xet transfer backend is not served by the mirror; use plain HTTPS.
        os.environ["HF_HUB_DISABLE_XET"] = "1"
        print("huggingface.co is unreachable; downloading through " + MIRROR)

# Imported only now: huggingface_hub reads HF_ENDPOINT while it is imported.
from huggingface_hub import snapshot_download

local = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData/Local")) / "ClipboardOCR"
print(snapshot_download(REPO, revision=REVISION, local_dir=local / "models/PaddleOCR-VL-1.6-GGUF"))
