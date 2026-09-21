"""Download the large Windows Paddle wheel with resume and ZIP CRC validation."""
import os
import http.client
import re
import sys
import time
import urllib.error
import urllib.request
import zipfile
import zlib
from pathlib import Path

HOSTS = ("https://paddle-whl.bj.bcebos.com", "https://paddle-whl.cdn.bcebos.com")


def valid_wheel(path):
    try:
        with zipfile.ZipFile(path) as archive:
            return "paddle/version/__init__.py" in archive.namelist() and archive.testzip() is None
    except (OSError, zipfile.BadZipFile, EOFError, zlib.error):
        return False


def transfer(url, part):
    offset = part.stat().st_size if part.exists() else 0
    request = urllib.request.Request(url, headers={"Range": f"bytes={offset}-"})
    try:
        response = urllib.request.urlopen(request, timeout=60)
    except urllib.error.HTTPError as error:
        if error.code == 416:
            if valid_wheel(part):
                return
            part.unlink(missing_ok=True)
        raise
    with response:
        if response.status == 206:
            match = re.fullmatch(r"bytes (\d+)-(\d+)/(\d+)", response.headers.get("Content-Range", ""))
            if not match or int(match[1]) != offset:
                raise ValueError("Server returned an invalid resume range")
            expected = int(match[3])
            mode = "ab"
        elif response.status == 200:
            # A server may ignore Range; restarting avoids appending a whole file.
            offset = 0
            expected = int(response.headers["Content-Length"])
            mode = "wb"
        else:
            raise ValueError(f"Unexpected HTTP status {response.status}")
        print(f"Paddle download: {offset / 1048576:.1f}/{expected / 1048576:.1f} MiB", flush=True)
        report = time.monotonic()
        with part.open(mode) as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
                offset += len(chunk)
                if time.monotonic() - report >= 10:
                    print(f"Paddle download: {offset / 1048576:.1f}/{expected / 1048576:.1f} MiB", flush=True)
                    report = time.monotonic()
        if offset != expected:
            raise OSError(f"Incomplete wheel: {offset} of {expected} bytes; keeping partial download")


def download(variant):
    if variant not in ("cu126", "cu129"):
        raise ValueError("Unsupported Paddle CUDA variant")
    local = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData/Local")) / "ClipboardOCR"
    destination = local / "downloads" / variant / "paddlepaddle_gpu-3.2.1-cp312-cp312-win_amd64.whl"
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() and valid_wheel(destination):
        print(f"Reusing verified wheel: {destination}", flush=True)
        return destination
    part = destination.with_suffix(".whl.part")
    for host in HOSTS:
        url = f"{host}/stable/{variant}/paddlepaddle-gpu/{destination.name}"
        for attempt in range(1, 3):
            print(f"Paddle source: {host}, attempt {attempt}/2", flush=True)
            try:
                transfer(url, part)
                if not valid_wheel(part):
                    # Only the corrupt task-owned partial file is discarded.
                    part.unlink(missing_ok=True)
                    raise ValueError("Wheel CRC validation failed; restarting download")
                part.replace(destination)
                print(f"Wheel download and CRC validation passed: {destination}", flush=True)
                return destination
            except (OSError, ValueError, http.client.HTTPException) as error:
                print(f"Download failed: {error}", flush=True)
                if attempt < 2:
                    time.sleep(2)
    raise RuntimeError("Paddle download failed on both official hosts. Rerun setup to resume the partial file.")


if __name__ == "__main__":
    download(sys.argv[1])
