import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'backend'))
from engine import Engine, MODELS
from safetensors import safe_open
with safe_open(MODELS/'PaddleOCR-VL-1.6/model.safetensors',framework='numpy') as weights:
    assert len(weights.keys()) > 100
engine=Engine()
try:
    engine.load()
    print('PaddleOCR-VL-1.6 pipeline and local MLX service are ready.')
finally:
    engine.close()
