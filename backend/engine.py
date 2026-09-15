"""Full PaddleOCR document parser with a private, persistent MLX service."""
from __future__ import annotations
import os
from pathlib import Path
CACHE = Path.home() / 'Library/Caches/ClipboardOCR'
MODELS = Path.home() / 'Library/Application Support/ClipboardOCR/models'

def configure_environment():
    os.environ.update({
        'HF_HOME': str(CACHE / 'huggingface'),
        'PADDLE_PDX_CACHE_HOME': str(CACHE / 'paddlex'),
        'HF_HUB_OFFLINE': '1', 'TRANSFORMERS_OFFLINE': '1',
        'HF_HUB_DISABLE_TELEMETRY': '1',
        'APC_ENABLED': '0', 'APC_DISK_ENABLED': '0', 'APC_DISK_PATH': '',
        'PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK': 'True',
        'DO_NOT_TRACK': '1', 'TOKENIZERS_PARALLELISM': 'false',
        'NO_PROXY': '127.0.0.1,localhost', 'no_proxy': '127.0.0.1,localhost',
    })

class BackendError(Exception):
    pass

class Engine:
    def __init__(self):
        self.service = None
        self.pipeline = None

    def load(self):
        if self.pipeline is not None:
            return
        configure_environment()
        for path in [MODELS/'PaddleOCR-VL-1.6/model.safetensors', MODELS/'PP-DocLayoutV3/inference.pdiparams']:
            if not path.is_file():
                raise BackendError('missing_models')
        import secrets, socket, subprocess, sys, time, urllib.request, json
        self.token = secrets.token_urlsafe(32)
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        self.url = f'http://127.0.0.1:{port}'
        env = os.environ.copy()
        env['MLX_VLM_SERVER_API_KEY'] = self.token
        service_python = Path(sys.prefix).parent / 'runtime-mlx/bin/python'
        if not service_python.is_file():
            raise BackendError('service_start_failed')
        self.service = subprocess.Popen([
            str(service_python), str(Path(__file__).with_name('mlx_service.py')),
            '--host', '127.0.0.1', '--port', str(port), '--log-level', 'ERROR',
            '--vision-cache-size', '0', '--log-progress-interval', '0',
        ], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)
        try:
            deadline = time.monotonic() + 120
            while time.monotonic() < deadline:
                if self.service.poll() is not None:
                    raise BackendError('service_start_failed')
                try:
                    request = urllib.request.Request(self.url+'/v1/models', headers={'Authorization': 'Bearer '+self.token})
                    with urllib.request.urlopen(request, timeout=1) as response:
                        json.load(response)
                    break
                except Exception:
                    time.sleep(.2)
            else:
                raise BackendError('service_timeout')
            from paddleocr import PaddleOCRVL
            self.pipeline = PaddleOCRVL(
                pipeline_version='v1.6', device='cpu', enable_mkldnn=False,
                layout_detection_model_dir=str(MODELS/'PP-DocLayoutV3'),
                vl_rec_backend='mlx-vlm-server', vl_rec_server_url=self.url,
                vl_rec_api_model_name=str(MODELS/'PaddleOCR-VL-1.6'),
                vl_rec_api_key=self.token, vl_rec_max_concurrency=1,
                use_doc_orientation_classify=False, use_doc_unwarping=False,
                use_queues=False, markdown_ignore_labels=[],
            )
        except BaseException:
            self.close()
            raise

    def recognize(self, path):
        if self.service is None or self.service.poll() is not None:
            raise BackendError('backend_crashed')
        results = self.pipeline.predict(str(path), use_queues=False, max_new_tokens=4096)
        markdown = self.pipeline.concatenate_markdown_pages([r._to_markdown(pretty=False, show_formula_number=True) for r in results])
        if not markdown or not markdown.strip():
            raise BackendError('no_text')
        return normalize_markdown(markdown)

    def close(self):
        if self.service is not None:
            if self.service.poll() is None:
                self.service.terminate()
                try:
                    self.service.wait(timeout=5)
                except Exception:
                    self.service.kill()
                    self.service.wait()
            self.service = None
        self.pipeline = None

def normalize_markdown(text):
    """Normalize delimiters and list markers, preserving LaTeX interiors."""
    import re
    text = text.replace('\r\n', '\n')
    text = re.sub(r'\\\[(.*?)\\\]', lambda m: '$$'+m[1]+'$$', text, flags=re.S)
    text = re.sub(r'\\\((.*?)\\\)', lambda m: '$'+m[1]+'$', text, flags=re.S)
    parts = []
    offset = 0
    for match in re.finditer(r'(?<!\\)(\$\$|\$)(.*?)(?<!\\)\1', text, flags=re.S):
        plain = text[offset:match.start()]
        parts.append(re.sub(r'(?m)^([ \t]*)[•●] +', r'\1- ', plain))
        delimiter, body = match[1], match[2].strip()
        parts.append('$$\n'+body+'\n$$' if delimiter == '$$' else '$'+body+'$')
        offset = match.end()
    parts.append(re.sub(r'(?m)^([ \t]*)[•●] +', r'\1- ', text[offset:]))
    return ''.join(parts).strip() + '\n'
