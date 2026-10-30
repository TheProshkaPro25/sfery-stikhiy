"""Check exterior repairs and independently skinned rear beetle legs.

The reconstructed Stone/Tide meshes must close their actual exterior. Legacy
variants still have separate under-armour surfaces; do not demand those proxies
from a reconstructed model or mistake them for a repaired exterior.
"""
from pathlib import Path
import sys,numpy as np
root=Path(__file__).resolve().parents[1];sys.path.insert(0,str(root/'tools/models'))
from inspect_geometry import read_glb,accessor
from upgrade_rigs import globals_of

for path in ([Path(p) for p in sys.argv[1:]] or sorted((root/'assets/creatures_hd').glob('rogozhuk_*.glb'))):
 doc,binary=read_glb(path);skin=doc['skins'][0];names=[doc['nodes'][n]['name'] for n in skin['joints']]
 shell=skin['joints'][names.index('shell')];rest=np.asarray(doc['nodes'][shell].get('rotation',[0,0,0,1]))
 for animation in doc['animations']:
  for ch in animation['channels']:
   if ch['target']['node']==shell and ch['target']['path']=='rotation':
    q=accessor(doc,binary,animation['samplers'][ch['sampler']]['output']);angle=2*np.arccos(np.clip(np.abs(q@rest),0,1))
    assert angle.max()<.25,(path.name,'shell detached from its bind orientation')
 primitives=doc['meshes'][0]['primitives'];extras=doc['asset'].get('extras',{})
 reconstructed=extras.get('stone_exterior_repair') or extras.get('sfery_water_beetle_anatomy',0)>=11 or extras.get('sfery_light_beetle_anatomy',0)>=13
 if reconstructed:
  separate_rear=not path.stem.endswith('stone') or extras.get('sfery_stone_rear_rebuild',0)>=3
  assert len(primitives)==(6 if separate_rear else 1),(path.name,'unexpected proxy surfaces')
  groups=[primitives[i:i+2] for i in range(0,6,2)] if separate_rear else [primitives]
 else:
  assert len(primitives)>=3,(path.name,'missing under-armour surfaces');groups=[[p] for p in primitives[1:]]
 for group in groups:
  vertices=[];faces=[];offset=0
  for p in group:
   v=accessor(doc,binary,p['attributes']['POSITION']);f=accessor(doc,binary,p['indices']).reshape(-1,3);vertices.append(v);faces.append(f+offset);offset+=len(v)
  v=np.concatenate(vertices);f=np.concatenate(faces);_,uid=np.unique(np.round(v,6),axis=0,return_inverse=True);geometric=uid[f]
  directed=np.concatenate([geometric[:,[0,1]],geometric[:,[1,2]],geometric[:,[2,0]]]);edges=np.sort(directed,axis=1)
  unique,inverse,count=np.unique(edges,axis=0,return_inverse=True,return_counts=True)
  assert (count==2).all(),(path.name,'exterior open or nonmanifold',np.unique(count,return_counts=True))
  winding=np.bincount(inverse,weights=np.where(directed[:,0]<directed[:,1],1,-1))
  assert (winding==0).all(),(path.name,'inconsistent exterior winding')
  tri=v[f];area=np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1)
  assert (area>1e-12).all(),(path.name,'collapsed exterior faces')
 # Check all exterior surfaces: Tide's two new legs are separate primitives.
 leg_slots=[i for i,name in enumerate(names) if name.startswith(('arm.','forearm.','hand.','thigh.','shin.','foot.','rear_'))]
 rear_counts={side:0 for side in ['L','R']}
 for p in (primitives if reconstructed else primitives[:1]):
  js=np.concatenate([accessor(doc,binary,p['attributes']['JOINTS_'+str(k)]) for k in [0,1]],axis=1)
  ws=np.concatenate([accessor(doc,binary,p['attributes']['WEIGHTS_'+str(k)]) for k in [0,1]],axis=1);v=accessor(doc,binary,p['attributes']['POSITION'])
  upper=np.where(np.isin(js,leg_slots),ws,0).sum(1)[v[:,1]>.12]
  assert len(upper)==0 or upper.max()<.08,(path.name,'upper armour pulled by legs')
  for side in ['L','R']:
   chain=[names.index(prefix+side) for prefix in ['rear_thigh.','rear_shin.','rear_foot.'] if prefix+side in names]
   rear_counts[side]+=int((np.where(np.isin(js,chain),ws,0).sum(1)>.5).sum())
 for side,count in rear_counts.items():
  if 'rear_thigh.'+side in names:assert count>100,(path.name,side,'rear leg still glued to torso')
 if path.stem.endswith('stone'):
  assert extras.get('sfery_baked_repair_atlas')==1,'repaired Stone requires a baked UV atlas'
 if extras.get('light_rear_plates_removed'):
  gs=globals_of(doc);nodes={n.get('name'):i for i,n in enumerate(doc['nodes'])}
  center=gs[nodes['chest']][:3,3]
  forward=gs[nodes['head']][:3,3]-center;forward[1]=0;forward/=np.linalg.norm(forward)
  # The old paddles hung behind the abdomen. Inspect referenced exterior
  # vertices, not unused source vertices retained in the accessor.
  for p in primitives[:2]:
   used=np.unique(accessor(doc,binary,p['indices']))
   v=accessor(doc,binary,p['attributes']['POSITION'])[used]
   behind=(v-center)@forward
   assert not ((behind<-.315)&(v[:,1]<.06)).any(),(path.name,'false rear plates returned')
 print(path.stem,'exterior topology and rear skinning OK')
