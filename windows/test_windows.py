import ctypes
import sys
import unittest
from ctypes import wintypes
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))
import engine_windows
from engine import BackendError

sys.path.insert(0, str(ROOT / "windows"))
import app as windows_app


class WindowsEngineTests(unittest.TestCase):
    def test_requires_cuda(self):
        class FakeCuda:
            @staticmethod
            def device_count(): return 0
        class FakePaddle:
            device = type("Device", (), {"cuda": FakeCuda})
            @staticmethod
            def is_compiled_with_cuda(): return False
        with patch.dict(sys.modules, {"paddle": FakePaddle()}):
            with self.assertRaisesRegex(BackendError, "gpu_unavailable"):
                engine_windows.Engine().load()

    def test_64_bit_global_memory_signatures_and_long_payload(self):
        self.assertEqual(windows_app.kernel32.GlobalUnlock.argtypes, [wintypes.HGLOBAL])
        self.assertEqual(windows_app.kernel32.GlobalFree.argtypes, [wintypes.HGLOBAL])
        payload = (("长文本 OCR result 123\n" * 100_000) + "\0").encode("utf-16-le")
        handle = windows_app.kernel32.GlobalAlloc(windows_app.GMEM_MOVEABLE, len(payload))
        self.assertTrue(handle)
        try:
            pointer = windows_app.kernel32.GlobalLock(handle)
            self.assertTrue(pointer)
            ctypes.memmove(pointer, payload, len(payload))
            windows_app.kernel32.GlobalUnlock(handle)
        finally:
            self.assertFalse(windows_app.kernel32.GlobalFree(handle))

    def test_invalid_concurrency_uses_default(self):
        with patch.dict(engine_windows.os.environ, {"BAD_INT": "not-a-number"}):
            self.assertEqual(engine_windows.bounded_int("BAD_INT", 2, 1, 4), 2)

    def test_large_transparent_image_is_bounded_rgb(self):
        image = windows_app.Image.new("RGBA", (5000, 3000), (0, 0, 0, 0))
        prepared = windows_app.prepare_image(image)
        self.assertEqual(prepared.mode, "RGB")
        self.assertLessEqual(prepared.width * prepared.height, windows_app.MAX_IMAGE_PIXELS)
        self.assertEqual(prepared.getpixel((0, 0)), (255, 255, 255))


if __name__ == "__main__":
    unittest.main()
