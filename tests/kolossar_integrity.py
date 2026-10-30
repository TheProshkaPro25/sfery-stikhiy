"""Only the two excessive right-arm rotation channels may change in each action."""
from pathlib import Path
import sys,numpy as np
root=Path(__file__).resolve().parents[1];sys.path.insert(0,str(root/'tools/models'))
from inspect_geometry import read_glb,accessor,triangles
from upgrade_rigs import globals_of
checked=0
for path in sorted((root/'assets/creatures_hd').glob('kolossar_*.glb')):
 source=root/'tools/_tmp/kolossar-arms028-base'/path.name
 if not source.exists():continue
 d,b=read_glb(path);old,ob=read_glb(source)
 assert all(np.max(np.abs(a-z))<1e-10 for a,z in zip(globals_of(old),globals_of(d)))
 for (op,ov,of),(p,v,f) in zip(triangles(old,ob),triangles(d,b)):
  assert np.array_equal(ov,v) and np.array_equal(of,f)
  for name,index in op['attributes'].items():assert np.array_equal(accessor(old,ob,index),accessor(d,b,p['attributes'][name]))
 changed=0
 for original,now in zip(old['animations'],d['animations']):
  for oc,ch in zip(original['channels'],now['channels']):
   assert oc['target']==ch['target'];os=original['samplers'][oc['sampler']];ns=now['samplers'][ch['sampler']]
   assert np.array_equal(accessor(old,ob,os['input']),accessor(d,b,ns['input']))
   before=accessor(old,ob,os['output']);after=accessor(d,b,ns['output']);node=d['nodes'][ch['target']['node']];name=node.get('name','')
   intended=original['name'] in ['stance','attack'] and name in ['arm.R','forearm.R'] and ch['target']['path']=='rotation'
   if intended:
    rest=np.array(node.get('rotation',[0,0,0,1]));old_angle=2*np.arccos(np.clip(np.abs(before@rest),0,1));new_angle=2*np.arccos(np.clip(np.abs(after@rest),0,1))
    assert new_angle.max()<old_angle.max()*.85,(path.name,name,'excessive right-arm rotation remains');changed+=1
   else:assert np.array_equal(before,after),(path.name,original['name'],name,'unrelated channel changed')
 assert changed==4
 checked+=1
print('Kolossars:',checked,'references: geometry, UVs, weights, rest and unrelated channels preserved; right-arm extremes reduced')
