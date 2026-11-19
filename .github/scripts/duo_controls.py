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

# Fresh display lookup on every attempt: rotating/unfolding a Duo changes
# the active panel and its digitizer coordinate transform. Use the official
# duoctl CLI as a genuine second physical input route, not a synthetic state
# change, and offset within the *rendered* control to recover missed hits.
TAPS=[(0,0,'native'),(0,0,'duoctl'),(-6,0,'native'),(6,0,'duoctl'),(0,-5,'native')]
def touch(label,attempt=0):
 s=state();box=s['controls'].get(label)
 if box is None:raise RuntimeError(f'{a.case}: missing actual {label} control')
 dx,dy,method=TAPS[attempt % len(TAPS)]
 x=max(box['left']+3,min(box['left']+box['width']-3,box['left']+box['width']/2+dx))
 y=max(box['top']+3,min(box['top']+box['height']-3,box['top']+box['height']/2+dy))
 print(f'Physical {method} tap {label} at ({x:.1f},{y:.1f}); attempt {attempt+1}',flush=True)
 if method=='duoctl':
  subprocess.run(['duoctl','-d',a.udid,'tap',str(x),str(y)],check=True,timeout=45)
 else:
  displays=[d for d in native['displays'](a.udid) if d.get('active')]
  assert len(displays)==1,displays
  nx,ny=native['to_native'](displays[0],x,y)
  native['helper'](a.udid,'tap',displays[0]['uniqueId'],f'{nx:.5f}',f'{ny:.5f}',.11)

def ensure_control_change(label,predicate,description):
 for attempt in range(len(TAPS)):
  if predicate(state()):return state()
  if label not in state()['controls']:
   raise RuntimeError(f'{a.case}: {label} disappeared before {description}: {state()}')
  try:
   touch(label,attempt)
   return until(predicate,description)
  except (RuntimeError,subprocess.SubprocessError) as e:
   print(f'{label} attempt {attempt+1}/{len(TAPS)} did not complete: {e}',flush=True)
   if attempt+1==len(TAPS):raise
   time.sleep(.8)
 raise RuntimeError(f'{a.case}: {description}; last state={state()}')
def capture(suffix):
 s=state();png=Path(str(a.prefix)+'-'+suffix+'.png')
 displays=[d for d in native['displays'](a.udid) if d.get('active')]
 subprocess.run(['xcrun','simctl','io',a.udid,'screenshot',f"--display={displays[0]['displayId']}",str(png)],check=True,timeout=30)
 meta=png.with_suffix('.layout.json');meta.write_text(json.dumps(s,indent=2)+'\n')
 from verify_fitted_capture import verify
 verify(png,meta,round(s['zoom']*100))
if a.case=='navigation':
 original=state()['focusedPage']
 if 'Collapse navigation' in state()['controls']:
  ensure_control_change('Collapse navigation',lambda s:'Open navigation' in s['controls'],
                        'collapsed tab did not appear')
 until(lambda s:'Open navigation' in s['controls'],'collapsed tab did not appear')
 capture('closed')
 ensure_control_change('Open navigation',lambda s:'Zoom in' in s['controls'],
                       'navigation did not open')
 capture('open')
 assert state()['focusedPage']==original,'navigation changed focused page'
else:
 minimum=70 if state()['mode']=='single' else 60
 for target in range(minimum,101,5):
  for step in range(10):
   s=state();current=round(s['zoom']*100)
   if current==target:break
   label='Zoom in' if current<target else 'Zoom out'
   expected=current+(5 if current<target else -5)
   # Verify the actual app reports each 5% step after real physical touches.
   # Rotate/hinge transitions occasionally cause dropped digitizer events;
   # try bounded fresh-display/CLI touch routes, never edit app zoom state.
   for attempt in range(len(TAPS)):
    s=state()
    if round(s['zoom']*100)==expected:break
    if label not in s['controls']:
     if 'Open navigation' not in s['controls']:
      raise RuntimeError(f'No zoom or navigation control at {current}%: {s}')
     ensure_control_change('Open navigation',lambda v:label in v['controls'],
                           'zoom controls did not open')
    try:
     touch(label,attempt)
     until(lambda v:round(v['zoom']*100)==expected,
           f'{label} did not advance {current}% to {expected}% (attempt {attempt+1})')
     break
    except (RuntimeError,subprocess.SubprocessError) as error:
     actual=round(state()['zoom']*100)
     print(f'Zoom physical tap {attempt+1}/{len(TAPS)}: '
           f'expected {expected}%, rendered {actual}%; {error}',flush=True)
     if attempt+1==len(TAPS):raise
     time.sleep(.8)
   assert round(state()['zoom']*100)==expected, f'Zoom jumped unexpectedly: expected {expected}%'
  assert round(state()['zoom']*100)==target,'requested zoom was not reached'
  capture(str(target))
print(json.dumps({'case':a.case,'passed':True}))
