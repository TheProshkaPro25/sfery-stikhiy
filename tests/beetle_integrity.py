"""Regression for hollow beetles and rear appendages accidentally weighted to the body."""
from pathlib import Path
import sys,numpy as np
root=Path(__file__).resolve().parents[1];sys.path.insert(0,str(root/'tools/models'))
from inspect_geometry import read_glb,accessor
for path in sorted((root/'assets/creatures_hd').glob('rogozhuk_*.glb')):
 doc,binary=read_glb(path);skin=doc['skins'][0];names=[doc['nodes'][n]['name'] for n in skin['joints']]
 shell=skin['joints'][names.index('shell')]
 rest=np.asarray(doc['nodes'][shell].get('rotation',[0,0,0,1]))
 for animation in doc['animations']:
  for ch in animation['channels']:
   if ch['target']['node']==shell and ch['target']['path']=='rotation':
    q=accessor(doc,binary,animation['samplers'][ch['sampler']]['output'])
    angle=2*np.arccos(np.clip(np.abs(q@rest),0,1))
    assert angle.max()<.25,(path.name,'shell detached from its bind orientation')
 primitives=doc['meshes'][0]['primitives'];assert len(primitives)>=3,(path.name,'no closed body beneath armour')
 for p in primitives[1:]:
  f=accessor(doc,binary,p['indices']).reshape(-1,3)
  e=np.sort(np.concatenate([f[:,[0,1]],f[:,[1,2]],f[:,[2,0]]]),axis=1);_,count=np.unique(e,axis=0,return_counts=True)
  assert (count==2).all(),(path.name,'open inner body')
 p=primitives[0];js=np.concatenate([accessor(doc,binary,p['attributes']['JOINTS_'+str(k)]) for k in [0,1]],axis=1)
 ws=np.concatenate([accessor(doc,binary,p['attributes']['WEIGHTS_'+str(k)]) for k in [0,1]],axis=1)
 vertices=accessor(doc,binary,p['attributes']['POSITION'])
 leg_slots=[i for i,name in enumerate(names) if name.startswith(('arm.','forearm.','hand.','thigh.','shin.','foot.','rear_'))]
 upper_leg_weights=np.where(np.isin(js,leg_slots),ws,0).sum(1)[vertices[:,1]>.12]
 assert upper_leg_weights.max()<.08,(path.name,'upper armour still pulled by legs',upper_leg_weights.max())
 for side in ['L','R']:
  if 'rear_thigh.'+side not in names:continue
  chain=[names.index(prefix+side) for prefix in ['rear_thigh.','rear_shin.','rear_foot.']]
  strength=np.where(np.isin(js,chain),ws,0).sum(1)
  assert (strength>.5).sum()>100,(path.name,side,'rear leg still glued to torso')
print('Beetles: 6 closed inner bodies; existing rear legs have independent skinning')
