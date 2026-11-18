#!/usr/bin/env python3
import argparse, hashlib, json, os, re, subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--device',required=True);p.add_argument('--reference',required=True);a=p.parse_args()
listing=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','-j'],timeout=20))
needle={'mini':'iPad mini','pro11':'iPad Pro 11-inch','pro13':'iPad Pro 13-inch'}[a.device]
options=[(tuple(map(int,re.findall(r'\d+',runtime))),runtime,d) for runtime,devices in listing['devices'].items() if '.iOS-' in runtime for d in devices if d.get('isAvailable') and needle in d['name']]
assert options,f'No available simulator for {needle}'
_,runtime,device=max(options,key=lambda x:x[0]);template={'runtime':runtime,'device':device}
Path('.ci').mkdir(exist_ok=True);Path('.ci/ipad-template.json').write_text(json.dumps(template,indent=2)+'\n')
profile=hashlib.sha256(Path('tools/ios_ui_qa/layout_profile.json').read_bytes()).hexdigest()
key=hashlib.sha256(json.dumps([a.reference,device['deviceTypeIdentifier'],runtime,profile]).encode()).hexdigest()
with open(os.environ['GITHUB_OUTPUT'],'a') as f:f.write('baseline_key=reader-v5-layout-'+key+'\n')
print(json.dumps(template,indent=2))
