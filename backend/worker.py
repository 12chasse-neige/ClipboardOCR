#!/usr/bin/env python3
"""JSON-lines protocol. Only allowlisted diagnostics escape third-party code."""
import os, sys, json, signal, threading, time
from pathlib import Path
# Keep protocol separate even from native libraries writing directly to fd 1/2.
protocol = os.fdopen(os.dup(sys.stdout.fileno()), 'w', buffering=1)
diagnostic = os.fdopen(os.dup(sys.stderr.fileno()), 'w', buffering=1)
null = os.open(os.devnull, os.O_WRONLY)
os.dup2(null, 1)
os.dup2(null, 2)
os.close(null)
from engine import Engine, BackendError, CACHE
engine = Engine()
parent = os.getppid()
TEMP = CACHE / 'inputs'
TEMP.mkdir(parents=True, exist_ok=True, mode=0o700)

def emit(**fields):
    protocol.write(json.dumps(fields, ensure_ascii=False)+'\n')

def terminate(*_):
    raise SystemExit(0)

signal.signal(signal.SIGTERM, terminate)
signal.signal(signal.SIGINT, terminate)

def watch_parent():
    while True:
        time.sleep(1)
        if os.getppid() != parent:
            os.kill(os.getpid(), signal.SIGTERM)
threading.Thread(target=watch_parent, daemon=True).start()
ERRORS = {
    'missing_models': 'Models are missing. Run the setup command, then retry.',
    'service_start_failed': 'The local MLX service could not start. Retry or run setup again.',
    'service_timeout': 'The local model service took too long to start. Retry.',
    'backend_crashed': 'The OCR backend stopped unexpectedly. Retry.',
    'no_text': 'No text was recognized. Copy a clearer image and retry.',
    'invalid_image': 'The clipboard image could not be read. Copy it again and retry.',
    'recognition_failed': 'Recognition failed. Retry or unload the model and try again.',
    'invalid_request': 'The OCR request was invalid. Copy the image again and retry.',
}
try:
    emit(type='ready', protocol=1)
    for line in sys.stdin:
        request_id = None
        image_path = None
        start = time.monotonic()
        try:
            request = json.loads(line)
            request_id = request.get('id')
            if request.get('action') == 'shutdown':
                break
            if request.get('action') != 'recognize' or not isinstance(request_id, str):
                raise BackendError('invalid_request')
            candidate = Path(request['path'])
            if candidate.parent.resolve() != TEMP.resolve() or candidate.is_symlink() or candidate.suffix.lower() not in ('.png','.tiff'):
                raise BackendError('invalid_request')
            image_path = candidate
            from PIL import Image
            try:
                with Image.open(image_path) as im:
                    if im.format not in ('PNG','TIFF') or im.width * im.height > 40_000_000:
                        raise ValueError()
                    im.verify()
            except Exception:
                raise BackendError('invalid_image') from None
            emit(type='progress', id=request_id, stage='loading' if engine.pipeline is None else 'recognizing')
            engine.load()
            emit(type='progress', id=request_id, stage='recognizing')
            markdown = engine.recognize(image_path)
            emit(type='success', id=request_id, markdown=markdown, seconds=round(time.monotonic()-start,3))
            diagnostic.write('recognition_complete\n')
        except Exception as error:
            code = str(error) if isinstance(error, BackendError) else 'recognition_failed'
            if code not in ERRORS:
                code = 'recognition_failed'
            engine.close()
            emit(type='error', id=request_id, code=code, message=ERRORS[code])
            diagnostic.write(code+'\n')
        finally:
            if image_path is not None:
                image_path.unlink(missing_ok=True)
finally:
    engine.close()
