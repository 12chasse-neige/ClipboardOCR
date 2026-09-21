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
        "The installed PaddlePaddle build has no kernels for this GPU architecture. "
        "Blackwell (RTX 50) needs the cu129 build, Ada/Ampere/Turing the cu126 build, "
        "and older cards the cu118 build; set CLIPBOARD_OCR_PADDLE_INDEX to force one."
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
