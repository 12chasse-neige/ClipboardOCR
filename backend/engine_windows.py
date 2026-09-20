"""Native Windows PaddleOCR-VL engine with an accelerated llama.cpp VLM."""
from __future__ import annotations

import gc
import atexit
import json
import os
import secrets
import socket
import subprocess
import time
import urllib.request
import warnings
from pathlib import Path

from engine import BackendError, normalize_markdown


ROOT = Path(__file__).resolve().parents[1]
LOCAL = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData/Local")) / "ClipboardOCR"
LAYOUT = LOCAL / "paddlex/official_models/PP-DocLayoutV3"
GGUF = ROOT / ".windows/models/PaddleOCR-VL-1.6-GGUF"


def bounded_int(name, default, minimum, maximum):
    try:
        return max(minimum, min(maximum, int(os.environ.get(name, default))))
    except ValueError:
        return default


VLM_CONCURRENCY = bounded_int("CLIPBOARD_OCR_CONCURRENCY", 2, 1, 4)


def configure_environment():
    os.environ.update({
        "PADDLE_PDX_CACHE_HOME": str(LOCAL / "paddlex"),
        "HF_HOME": str(LOCAL / "huggingface"),
        "HF_HUB_DISABLE_TELEMETRY": "1",
        "DO_NOT_TRACK": "1",
        "TOKENIZERS_PARALLELISM": "false",
        "PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK": "True",
    })
    warnings.filterwarnings("ignore", message="No ccache found.*")
    warnings.filterwarnings("ignore", message=".*llama-cpp-server.*does not support.*pixels.*")


def find_llama_server():
    import shutil
    bundled = ROOT / ".windows/tools/llama/llama-server.exe"
    if bundled.is_file():
        return bundled
    found = shutil.which("llama-server")
    if found:
        return Path(found)
    packages = Path(os.environ.get("LOCALAPPDATA", "")) / "Microsoft/WinGet/Packages"
    return next(packages.glob("ggml.llamacpp_*/llama-server.exe"), None)


class Engine:
    def __init__(self):
        self.pipeline = None
        self.service = None
        self.backend_name = "PaddlePaddle CUDA"
        atexit.register(self.close)

    def _start_llama(self):
        executable = find_llama_server()
        model = GGUF / "PaddleOCR-VL-1.6-GGUF.gguf"
        mmproj = GGUF / "PaddleOCR-VL-1.6-GGUF-mmproj.gguf"
        if not executable or not model.is_file() or not mmproj.is_file():
            return None
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        token = secrets.token_urlsafe(32)
        flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
        self.service = subprocess.Popen([
            str(executable), "-m", str(model), "--mmproj", str(mmproj),
            "--host", "127.0.0.1", "--port", str(port), "--temp", "0",
            "--ctx-size", "8192", "--parallel", str(VLM_CONCURRENCY), "--n-gpu-layers", "99",
            "--api-key", token, "--no-ui", "--log-disable",
        ], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
           stderr=subprocess.DEVNULL, creationflags=flags)
        url = f"http://127.0.0.1:{port}"
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            if self.service.poll() is not None:
                break
            try:
                request = urllib.request.Request(url + "/v1/models", headers={"Authorization": "Bearer " + token})
                with urllib.request.urlopen(request, timeout=1) as response:
                    model_id = json.load(response)["data"][0]["id"]
                self.backend_name = f"llama.cpp Vulkan · RTX 4060 · {VLM_CONCURRENCY} 路并行"
                return url + "/v1", token, model_id
            except Exception:
                time.sleep(.2)
        self._stop_service()
        return None

    def load(self):
        if self.pipeline is not None:
            return
        configure_environment()
        try:
            import paddle
            if not paddle.is_compiled_with_cuda() or paddle.device.cuda.device_count() < 1:
                raise BackendError("gpu_unavailable")
            from paddleocr import PaddleOCRVL
            fast = self._start_llama()
            common = dict(
                pipeline_version="v1.6", device="gpu:0",
                layout_detection_model_dir=str(LAYOUT) if LAYOUT.is_dir() else None,
                use_doc_orientation_classify=False, use_doc_unwarping=False,
                use_queues=False, markdown_ignore_labels=[],
            )
            if fast:
                url, token, model_id = fast
                self.pipeline = PaddleOCRVL(
                    **common, vl_rec_backend="llama-cpp-server",
                    vl_rec_server_url=url, vl_rec_api_model_name=model_id,
                    vl_rec_api_key=token, vl_rec_max_concurrency=VLM_CONCURRENCY,
                )
            else:
                self.pipeline = PaddleOCRVL(**common, engine="paddle")
        except BackendError:
            raise
        except Exception as error:
            self.close()
            raise BackendError("model_load_failed") from error

    def recognize(self, path):
        self.load()
        for attempt in range(2):
            try:
                results = self.pipeline.predict(str(path), use_queues=False, max_new_tokens=4096)
                markdown = self.pipeline.concatenate_markdown_pages(
                    [r._to_markdown(pretty=False, show_formula_number=True) for r in results]
                )
                break
            except Exception as error:
                if attempt or not self.service or self.service.poll() is None:
                    raise BackendError("recognition_failed") from error
                self.close()
                self.load()
        if not markdown or not markdown.strip():
            raise BackendError("no_text")
        return normalize_markdown(markdown)

    def _stop_service(self):
        if self.service and self.service.poll() is None:
            self.service.terminate()
            try:
                self.service.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.service.kill()
                self.service.wait()
        self.service = None

    def close(self):
        self.pipeline = None
        self._stop_service()
        gc.collect()
        try:
            import paddle
            paddle.device.cuda.empty_cache()
        except Exception:
            pass
