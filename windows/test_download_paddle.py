import io
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

from windows import download_paddle as wheel


class Response(io.BytesIO):
    def __init__(self, data, status, headers):
        super().__init__(data)
        self.status = status
        self.headers = headers


class WheelDownloadTests(unittest.TestCase):
    def test_resume_and_range_ignored(self):
        for status in (206, 200):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as directory:
                part = Path(directory) / 'wheel.part'
                part.write_bytes(b'abc')
                response = Response(b'def' if status == 206 else b'abcdef', status,
                                    {'Content-Range': 'bytes 3-5/6', 'Content-Length': '6'})
                with patch.object(wheel.urllib.request, 'urlopen', return_value=response) as request:
                    wheel.transfer('https://example.test/wheel', part)
                    self.assertEqual(request.call_args.args[0].get_header('Range'), 'bytes=3-')
                self.assertEqual(part.read_bytes(), b'abcdef')

    def test_incomplete_download_keeps_bytes_for_retry(self):
        with tempfile.TemporaryDirectory() as directory:
            part = Path(directory) / 'wheel.part'
            with patch.object(wheel.urllib.request, 'urlopen', return_value=Response(b'abc', 200, {'Content-Length': '6'})):
                with self.assertRaisesRegex(OSError, 'Incomplete'):
                    wheel.transfer('https://example.test/wheel', part)
            self.assertEqual(part.read_bytes(), b'abc')

    def test_wrong_range_cannot_corrupt_partial_file(self):
        with tempfile.TemporaryDirectory() as directory:
            part = Path(directory) / 'wheel.part'
            part.write_bytes(b'abc')
            with patch.object(wheel.urllib.request, 'urlopen', return_value=Response(b'def', 206, {'Content-Range': 'bytes 0-2/6'})):
                with self.assertRaises(ValueError):
                    wheel.transfer('https://example.test/wheel', part)
            self.assertEqual(part.read_bytes(), b'abc')

    def test_cached_valid_wheel_skips_network(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(wheel, 'data_root', return_value=Path(directory) / 'data'):
            target = Path(directory) / 'data/downloads/cu129/paddlepaddle_gpu-3.2.1-cp312-cp312-win_amd64.whl'
            target.parent.mkdir(parents=True)
            with zipfile.ZipFile(target, 'w') as archive:
                archive.writestr('paddle/version/__init__.py', "cuda_version = '12.9'")
            with patch.object(wheel.urllib.request, 'urlopen') as request:
                self.assertEqual(wheel.download('cu129'), target)
                request.assert_not_called()
            target.write_bytes(b'broken')
            self.assertFalse(wheel.valid_wheel(target))


if __name__ == '__main__':
    unittest.main()
