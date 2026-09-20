"""Download/load the official models and verify native Windows GPU inference setup."""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))

from engine_windows import Engine, configure_environment

configure_environment()
import paddle

assert paddle.is_compiled_with_cuda(), "PaddlePaddle is not CUDA-enabled"
assert paddle.device.cuda.device_count() > 0, "No CUDA GPU is visible to PaddlePaddle"
print("GPU:", paddle.device.cuda.get_device_name(0))
engine = Engine()
try:
    engine.load()
    print("PaddleOCR-VL-1.6 is ready via", engine.backend_name)
    result = engine.recognize(ROOT / "validation/example-1.png")
    assert result.strip(), "End-to-end OCR returned no text"
    print("End-to-end OCR passed:", len(result), "characters")
finally:
    engine.close()
