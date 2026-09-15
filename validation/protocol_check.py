"""Exercise the real worker without modifying the user's clipboard."""
import json, os, selectors, shutil, signal, subprocess, sys, time
from pathlib import Path
root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/'backend'))
import engine
import psutil
python=Path.home()/'Library/Application Support/ClipboardOCR/runtime/bin/python'
inputs=engine.CACHE/'inputs'; inputs.mkdir(parents=True,exist_ok=True)
p=subprocess.Popen(['/usr/bin/sandbox-exec','-f',str(root/'backend/local-only.sb'),str(python),'-u',str(root/'backend/worker.py')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
selector=selectors.DefaultSelector(); selector.register(p.stdout,selectors.EVENT_READ)
# TextIO prefetch can hide multiple lines from select; use a background queue instead.
import queue, threading
messages=queue.Queue()
def read():
 for line in p.stdout: messages.put(json.loads(line))
threading.Thread(target=read,daemon=True).start()
def get(): return messages.get(timeout=120)
def request(id,source):
 path=inputs/(id+source.suffix)
 shutil.copyfile(source,path)
 p.stdin.write(json.dumps({'action':'recognize','id':id,'path':str(path)})+'\n'); p.stdin.flush()
 while True:
  result=get()
  if result['type'] in ('success','error'):
   # Worker deletes input in finally immediately after the response.
   for _ in range(30):
    if not path.exists(): break
    time.sleep(.1)
   assert not path.exists(), 'Input not deleted'
   return result
try:
 assert get()['type']=='ready'
 first=request('protocol-first',root/'validation/example-1.png')
 assert first['type']=='success',first
 assert '\\tag*{(1)}' in first['markdown'] and '\\begin{pmatrix}' in first['markdown']
 children=psutil.Process(p.pid).children(recursive=True)
 assert children
 service=children[0]
 second=request('protocol-warm',root/'validation/example-2.png')
 assert second['type']=='success',second
 assert service.is_running() and service.pid in [c.pid for c in psutil.Process(p.pid).children(recursive=True)]
 assert '数学' in second['markdown']
 # Stop the actual MLX child and verify a structured failure and temp cleanup.
 service.kill(); time.sleep(.2)
 crash=request('protocol-crash',root/'validation/example-1.png')
 assert crash['type']=='error' and crash['code']=='backend_crashed',crash
 recovery=request('protocol-recovery',root/'validation/example-1.tiff')
 assert recovery['type']=='success',recovery
 child_ids=[c.pid for c in psutil.Process(p.pid).children(recursive=True)]
 p.stdin.close(); p.wait(timeout=15)
 for child_id in child_ids:
  assert not psutil.pid_exists(child_id), 'Model process survived worker shutdown'
 diagnostics=p.stderr.read()
 assert set(diagnostics.splitlines()) <= {'recognition_complete','backend_crashed'}
 report = {'passed':['PNG recognition','TIFF recognition','warm model reuse','service crash','recovery','input cleanup','shutdown','allowlisted diagnostics'], 'cold_seconds':first['seconds'],'warm_seconds':second['seconds'],'diagnostics':diagnostics.splitlines()}
 (root/'validation/protocol-results.json').write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps(report,indent=2))
finally:
 if p.poll() is None:
  p.terminate()
  try: p.wait(timeout=15)
  except subprocess.TimeoutExpired: p.kill(); p.wait()
