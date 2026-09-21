import os
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from windows import download_models as models


class DownloadTests(unittest.TestCase):
    def test_explicit_endpoint_and_mirror_opt_out(self):
        self.assertEqual(models.endpoints({"HF_ENDPOINT": "https://example.test"}), ["https://example.test"])
        self.assertEqual(models.endpoints({"CLIPBOARD_OCR_DISABLE_MIRROR": "1"}), [models.OFFICIAL])

    def test_transfer_failure_retries_then_switches_endpoint(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(models.sys, "argv", ["download_models.py"]), \
             patch.object(models.subprocess, "run", side_effect=[SimpleNamespace(returncode=n) for n in (1, 1, 0)]) as run, \
             patch.object(models.time, "sleep"):
            self.assertEqual(models.main(), 0)
            self.assertEqual([c.kwargs["env"]["HF_ENDPOINT"] for c in run.call_args_list],
                             [models.OFFICIAL, models.OFFICIAL, models.MIRROR])
            self.assertEqual(run.call_args.kwargs["env"]["HF_HUB_DISABLE_XET"], "1")

    def test_permanent_failure_is_bounded_and_nonzero(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(models.sys, "argv", ["download_models.py"]), \
             patch.object(models.subprocess, "run", return_value=SimpleNamespace(returncode=1)) as run, \
             patch.object(models.time, "sleep"):
            self.assertEqual(models.main(), 1)
            self.assertEqual(run.call_count, 4)


if __name__ == "__main__":
    unittest.main()
