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
paddle.set_device("gpu:0")
print("Paddle:", paddle.__version__, "CUDA:", paddle.version.cuda())

# is_compiled_with_cuda() only says the wheel carries CUDA support; it does not say
# it carries kernels for this card.  Run one real kernel so a build for the wrong
# architecture reports itself here instead of failing deep inside OCR.
capability = paddle.device.cuda.get_device_capability()
try:
    product = paddle.matmul(paddle.ones([1024, 1024]), paddle.ones([1024, 1024]))
    product.numpy()
except Exception as error:
    raise SystemExit(
        f"GPU kernel launch failed on compute capability {capability}: {error}\n"
        "Check the NVIDIA driver, available VRAM, and Paddle CUDA build. "
        "This release uses cu129 for capabilities 7.5/8.0/8.6/8.9/12.0, with Windows driver 576.02+. "
        "Other GPU architectures are not covered by the pinned Windows wheel."
    )
print("GPU kernel check passed on capability", capability)

engine = Engine()
try:
    engine.load()
    print("PaddleOCR-VL-1.6 is ready via", engine.backend_name)
    result = engine.recognize(ROOT / "validation/example-1.png")
    assert result.strip(), "End-to-end OCR returned no text"
    print("End-to-end OCR passed:", len(result), "characters")
finally:
    engine.close()
