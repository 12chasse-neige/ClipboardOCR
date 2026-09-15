"""Exit even if the owning worker crashes; never keep an orphan model alive."""
import os, signal, threading, time
parent = os.getppid()
def watch_parent():
    while True:
        time.sleep(1)
        if os.getppid() != parent:
            os._exit(0)
threading.Thread(target=watch_parent, daemon=True).start()
from mlx_vlm.server.cli import main
main()
