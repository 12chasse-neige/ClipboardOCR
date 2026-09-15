"""Download immutable official weights during setup only."""
import os
from pathlib import Path
base = Path.home() / 'Library/Caches/ClipboardOCR'
os.environ['HF_HOME'] = str(base / 'huggingface')
os.environ['PADDLE_PDX_CACHE_HOME'] = str(base / 'paddlex')
os.environ['PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK'] = 'True'
models = Path.home() / 'Library/Application Support/ClipboardOCR/models'
from huggingface_hub import snapshot_download
p = snapshot_download('PaddlePaddle/PaddleOCR-VL-1.6', revision='c5630abae1d940eafe0697512a0325494b02ab42', local_dir=models / 'PaddleOCR-VL-1.6')
print(p)
snapshot_download('PaddlePaddle/PP-DocLayoutV3', revision='7b48a7566925fa464281f930c58eee04fe2c862a', local_dir=models / 'PP-DocLayoutV3')
