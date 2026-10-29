"""Periodic idle curves, original mesh/rest preservation, unchanged action clips."""
import sys
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools/models'))
from inspect_geometry import read_glb,accessor,triangles
from upgrade_rigs import globals_of
root=Path(__file__).resolve().parents[1];checks=0;preserved=0
for path in sorted((root/'assets/creatures_hd').glob('*.glb')):
 if path.stem.startswith(('glubinnik','sumrachnik','likorez')):continue
 candidates=[root/folder/path.name for folder in ['tools/_tmp/lightclean026-idle-base','tools/_tmp/rebuilt026-idle-base','tools/_tmp/idle026-base']]
 ref=next((p for p in candidates if p.exists()),None)
 old,oldbin=read_glb(ref) if ref else (None,None)
 doc,binary=read_glb(path)
 assert doc['asset']['extras']['sfery_idle_loop_version']==2,path.name
 if old is not None:
  for a,b in zip(globals_of(old),globals_of(doc)):
   assert np.abs(a-b).max()<2e-5,(path.name,'rest')
  for (op,ov,of),(p,v,f) in zip(triangles(old,oldbin),triangles(doc,binary)):
   assert np.array_equal(ov,v) and np.array_equal(of,f),(path.name,'mesh')
   for attr in ['NORMAL','TEXCOORD_0']:
    assert np.array_equal(accessor(old,oldbin,op['attributes'][attr]),accessor(doc,binary,p['attributes'][attr])),(path.name,attr)
  preserved+=1
 for a in doc['animations']:
  if a['name']!='idle':
   if old is not None:
    oa=next(x for x in old['animations'] if x['name']==a['name'])
    assert a==oa,(path.name,'action changed',a['name'])
  else:
   length=max(float(accessor(doc,binary,s['input'])[-1,0]) for s in a['samplers'])
   assert abs(length*30-round(length*30))<1e-4,(path.name,'import frame grid')
   for ch in a['channels']:
    if ch['target']['path']!='rotation':continue
    s=a['samplers'][ch['sampler']];v=accessor(doc,binary,s['output']);t=accessor(doc,binary,s['input']).ravel()
    assert np.isfinite(v).all() and np.abs(np.linalg.norm(v,axis=1)-1).max()<1e-5,path.name
    assert np.linalg.norm(v[-1]-v[0])<1e-5,(path.name,'position seam')
    if len(t)==121:
     dt=t[1]-t[0];before=(3*v[-1]-4*v[-2]+v[-3])/(2*dt);after=(-3*v[0]+4*v[1]-v[2])/(2*dt)
     assert np.linalg.norm(before-after)<.001,(path.name,'velocity seam')
    checks+=1
print('Idle loops:',checks,'channels OK; preserved mesh/UV/rest/action references:',preserved)
