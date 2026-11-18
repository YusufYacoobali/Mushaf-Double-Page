#!/usr/bin/env python3
import os,runpy,shutil,signal,subprocess,time
from pathlib import Path
native=runpy.run_path(str(Path(shutil.which('duoctl')).resolve()),run_name='reader_video')
udid=os.environ['DUOCTL_UDID'];active=[d for d in native['displays'](udid) if d.get('active')];assert len(active)==1
with open('screenshots/duo-video.log','w') as log:
 process=subprocess.Popen(['xcrun','simctl','io',udid,'recordVideo',f"--display={active[0]['displayId']}",'--codec=h264','screenshots/duo-half-open-book.mov'],stdout=log,stderr=subprocess.STDOUT)
 try:
  time.sleep(1.5)
  subprocess.run(['duoctl','swipe','540','300','900','300','--duration','0.3'],check=True,timeout=30)
  time.sleep(1.5)
 finally:
  if process.poll() is None:process.send_signal(signal.SIGINT)
  try:process.wait(timeout=5)
  except subprocess.TimeoutExpired:
   process.kill();process.wait()
