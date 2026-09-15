import sys, time, json, threading, os
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'backend'))
from engine import Engine
import psutil
root=Path(__file__).resolve().parent
engine=Engine()
measurements=[]
peak=0
running=True
def sample():
    global peak
    while running:
        try:
            p=psutil.Process()
            rss=sum(x.memory_info().rss for x in [p]+p.children(recursive=True) if x.is_running())
            peak=max(peak,rss)
        except psutil.Error:
            pass
        time.sleep(.1)
threading.Thread(target=sample,daemon=True).start()
try:
    start=time.perf_counter()
    engine.load()
    print('PIPELINE_READY', round(time.perf_counter()-start,2), flush=True)
    for name in ['example-1','example-2','example-1']:
        t=time.perf_counter()
        text=engine.recognize(root/(name+'.png'))
        elapsed=time.perf_counter()-t
        (root/(name+'.actual.md')).write_text(text)
        measurements.append({'image':name, 'seconds':elapsed, 'end_to_end_seconds':time.perf_counter()-start, 'peak_process_tree_rss_bytes':peak})
        print(json.dumps(measurements[-1]),flush=True)
        print(text,flush=True)
    (root/'measurements.json').write_text(json.dumps(measurements,indent=2))
finally:
    running=False
    engine.close()
