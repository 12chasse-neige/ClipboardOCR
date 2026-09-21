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
    def test_hybrid_laptop_selects_matching_nvidia_not_integrated_gpu(self):
        devices = '  Vulkan0: Intel UHD Graphics (1024 MiB)\n  Vulkan1: NVIDIA GeForce RTX 5090 (32000 MiB)'
        self.assertEqual(engine_windows.select_vulkan_device(devices, 'NVIDIA GeForce RTX 5090'), 'Vulkan1')
        self.assertIsNone(engine_windows.select_vulkan_device(devices, 'NVIDIA GeForce RTX 4060'))

    def test_failed_multi_slot_start_retries_with_one_slot(self):
        with patch.object(engine_windows, 'gpu_profile', return_value=('test GPU', 16000)):
            instance = engine_windows.Engine()
        with patch.object(instance, '_start_llama_once', side_effect=[None, ('url', 'key', 'model')]) as start:
            self.assertEqual(instance._start_llama(), ('url', 'key', 'model'))
            self.assertEqual(instance.concurrency, 1)
            self.assertEqual(start.call_count, 2)

    def test_gpu_profile_uses_available_memory(self):
        result = type('Result', (), {'stdout': 'NVIDIA GeForce RTX 4060, 8192, 4096\n'})()
        with patch.object(engine_windows.subprocess, 'run', return_value=result):
            self.assertEqual(engine_windows.gpu_profile(), ('NVIDIA GeForce RTX 4060', 4096))

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
        self.assertEqual(engine_windows.bounded_int("not-a-number", 2, 1, 4), 2)

    def test_concurrency_scales_conservatively_with_vram(self):
        self.assertEqual(engine_windows.choose_concurrency(4096), 1)
        self.assertEqual(engine_windows.choose_concurrency(8188), 2)
        self.assertEqual(engine_windows.choose_concurrency(12282), 3)
        self.assertEqual(engine_windows.choose_concurrency(16376), 4)
        self.assertEqual(engine_windows.choose_concurrency(4096, "4"), 4)
        self.assertEqual(engine_windows.choose_concurrency(16376, "invalid"), 1)

    def test_large_transparent_image_is_bounded_rgb(self):
        image = windows_app.Image.new("RGBA", (5000, 3000), (0, 0, 0, 0))
        prepared = windows_app.prepare_image(image)
        self.assertEqual(prepared.mode, "RGB")
        self.assertLessEqual(prepared.width * prepared.height, windows_app.MAX_IMAGE_PIXELS)
        self.assertEqual(prepared.getpixel((0, 0)), (255, 255, 255))

if __name__ == "__main__":
    unittest.main()
