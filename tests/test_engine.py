import sys,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'backend'))
import engine
class EngineTests(unittest.TestCase):
    def test_missing_models_does_not_start_process(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(engine,'MODELS',Path(directory)):
            instance=engine.Engine()
            with self.assertRaisesRegex(engine.BackendError,'missing_models'): instance.load()
            self.assertIsNone(instance.service)
    def test_dead_service_returns_structured_code(self):
        instance=engine.Engine()
        with self.assertRaisesRegex(engine.BackendError,'backend_crashed'): instance.recognize('unused.png')
if __name__=='__main__': unittest.main()
