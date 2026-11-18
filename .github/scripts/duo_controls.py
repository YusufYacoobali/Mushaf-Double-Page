#!/usr/bin/env python3
"""Exercise actual rendered control positions, independently of layout cases."""
import argparse,json,runpy,shutil,subprocess,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('case',choices=['navigation','zoom']);p.add_argument('udid');p.add_argument('metadata',type=Path);p.add_argument('prefix',type=Path);a=p.parse_args()
native=runpy.run_path(str(Path(shutil.which('duoctl')).resolve()),run_name='reader_control_input')
def state():return json.loads(a.metadata.read_text())
def until(predicate,description):
 end=time.monotonic()+5
 while time.monotonic()<end:
  s=state()
  if predicate(s):return s
  time.sleep(.1)
 raise RuntimeError(f'{a.case}: {description}; last state={state()}')
def touch(label):
 s=state();box=s['controls'].get(label)
 if box is None:raise RuntimeError(f'{a.case}: missing actual {label} control')
 displays=[d for d in native['displays'](a.udid) if d.get('active')]
 assert len(displays)==1
 x,y=native['to_native'](displays[0],box['left']+box['width']/2,box['top']+box['height']/2)
 native['helper'](a.udid,'tap',displays[0]['uniqueId'],f'{x:.5f}',f'{y:.5f}',.08)
def capture(suffix):
 s=state();png=Path(str(a.prefix)+'-'+suffix+'.png')
 displays=[d for d in native['displays'](a.udid) if d.get('active')]
 subprocess.run(['xcrun','simctl','io',a.udid,'screenshot',f"--display={displays[0]['displayId']}",str(png)],check=True,timeout=30)
 meta=png.with_suffix('.layout.json');meta.write_text(json.dumps(s,indent=2)+'\n')
 from verify_fitted_capture import verify
 verify(png,meta,round(s['zoom']*100))
if a.case=='navigation':
 original=state()['focusedPage']
 if 'Collapse navigation' in state()['controls']:touch('Collapse navigation')
 until(lambda s:'Open navigation' in s['controls'],'collapsed tab did not appear')
 capture('closed');touch('Open navigation')
 until(lambda s:'Zoom in' in s['controls'],'navigation did not open');capture('open')
 assert state()['focusedPage']==original,'navigation changed focused page'
else:
 minimum=70 if state()['mode']=='single' else 60
 for target in range(minimum,101,5):
  for step in range(10):
   s=state();current=round(s['zoom']*100)
   if current==target:break
   label='Zoom in' if current<target else 'Zoom out'
   if label not in s['controls']:
    touch('Open navigation');until(lambda v:label in v['controls'],'zoom controls did not open')
   touch(label)
   until(lambda v:round(v['zoom']*100)!=current,'zoom button made no change')
  assert round(state()['zoom']*100)==target,'requested zoom was not reached'
  capture(str(target))
print(json.dumps({'case':a.case,'passed':True}))
