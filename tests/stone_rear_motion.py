"""Reject rear-leg collapse or intersections in actual exported engine poses."""
from pathlib import Path
import json,sys
root=Path(__file__).resolve().parents[1];sys.path.insert(0,str(root/'tools/models'))
from leg_surface_distortion import measure
folder=Path(sys.argv[1])/'creature_rogozhuk_stone'
r=measure(folder,rear=True);samples={(p['action'],p['frame']) for p in r['poses']}
if {a for a,f in samples}=={'idle'}:
 assert len(samples)>=121 and max(f for a,f in samples)>=720,'sample at least 12 seconds of idle'
else:
 assert len(samples)>=67 and {a for a,f in samples}=={'idle','appear','roar','attack','hit','brace','ability'},'missing action coverage'
assert r['worst']['min_area_ratio']>.98,('solid rear leg collapsed',r['worst'])
report=json.loads(Path(sys.argv[2]).read_text());p=next(m for m in report if m['id']=='creature_rogozhuk_stone')
assert p['region']=='rear'
assert {(x['action'],x['frame']) for x in p['poses']}==samples,'intersection/skin samples differ'
assert max(x['pairs'] for x in p['poses'])==0,'rear legs intersect'
print('Stone rear:',len(samples),'engine poses; no intersections; minimum area ratio',r['worst']['min_area_ratio'])
