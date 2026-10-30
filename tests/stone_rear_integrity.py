"""Check the repaired Stone hind pair, socket geometry and matching bind data."""
from pathlib import Path
import sys,numpy as np,trimesh
from scipy.spatial import cKDTree
root=Path(__file__).resolve().parents[1];sys.path.insert(0,str(root/'tools/models'))
from inspect_geometry import read_glb,accessor,triangles
from upgrade_rigs import globals_of,qmul,qconj,qfraction
path=Path(sys.argv[1]) if len(sys.argv)>1 else root/'assets/creatures_hd/rogozhuk_stone.glb'
d,b=read_glb(path);old,ob=read_glb(root/'tools/_tmp/repair033/crown-rebuilt/rogozhuk_stone.glb');parts=list(triangles(d,b));op,ov,of=next(triangles(old,ob));assert len(parts)==6
assert d['asset']['extras']['sfery_stone_rear_rebuild']==3
assert any(n.get('extras',{}).get('sfery_rigid_limbs') for n in d['nodes'])
torso_binding=d['asset'].get('extras',{}).get('stone_torso_binding')==1
for node in d['nodes']:
 extras=node.get('extras',{})
 if torso_binding and extras.get('sfery_rigid_limbs'):
  assert extras.get('sfery_middle_stride')==.85,'035 middle stride must be exactly .85'
 else:assert 'sfery_middle_stride' not in extras,'stride marker outside the 035 rigid mesh'
for start in [0,2,4]:
 vv=np.concatenate([parts[start][1],parts[start+1][1]]);ff=np.concatenate([parts[start][2],parts[start+1][2]+len(parts[start][1])]);m=trimesh.Trimesh(vv,ff,process=True)
 assert m.is_watertight and m.is_winding_consistent,(start,'open exterior')
 assert m.area_faces.min()>1e-13,(start,'collapsed face')
 assert len(m.split(only_watertight=False))==1,(start,'detached scrap')
slots={d['nodes'][n]['name']:i for i,n in enumerate(d['skins'][0]['joints'])}
for i,(p,v,f) in enumerate(parts):
 j=np.concatenate([accessor(d,b,p['attributes']['JOINTS_'+str(k)]) for k in [0,1]],axis=1);w=np.concatenate([accessor(d,b,p['attributes']['WEIGHTS_'+str(k)]) for k in [0,1]],axis=1)
 assert np.isfinite(v).all() and np.isfinite(w).all() and (w>=0).all()
 assert abs(w.sum(1)-1).max()<2e-6
 if i>=2:
  joint=slots['rear_thigh.'+('L' if i<4 else 'R')]
  assert np.where(j==joint,w,0).sum(1).min()>.99999,'solid appendage must not squash between knee matrices'
# Crown, head and the anterior/middle feet remain actual original surfaces.
g=globals_of(old);names={n.get('name'):i for i,n in enumerate(old['nodes'])};center=g[names['chest']][:3,3].copy();center[1]=0;forward=g[names['head']][:3,3]-g[names['chest']][:3,3];forward[1]=0;forward/=np.linalg.norm(forward);longitudinal=(ov-center)@forward
protected=(ov[:,1]>.016)|(longitudinal>.18)|((ov[:,1]<-.24)&(longitudinal>-.25))
new_points=np.column_stack([parts[0][1],accessor(d,b,parts[0][0]['attributes']['TEXCOORD_0'])]);old_points=np.column_stack([ov,accessor(old,ob,op['attributes']['TEXCOORD_0'])]);distance,nearest=cKDTree(new_points).query(old_points[protected]);assert distance.max()<3e-6,('protected shape/UV changed',distance.max())
for node,original in zip(d['nodes'],old['nodes']):
 if original.get('name','').startswith('rear_'):continue
 node=dict(node);original=dict(original)
 if 'mesh' in node:
  extras=dict(node.get('extras',{}))
  if torso_binding and extras.get('sfery_rigid_limbs'):extras.pop('sfery_middle_stride')
  extras.pop('sfery_rigid_limbs',None)
  if extras:node['extras']=extras
  else:node.pop('extras',None)
 assert node==original,('unrelated rig changed',original.get('name'))
assert len(d['animations'])==len(old['animations'])
for clip,original in zip(d['animations'],old['animations']):
 assert clip['name']==original['name']
 assert clip['channels']==original['channels']
 assert len(clip['samplers'])==len(original['samplers'])
 for index,(sample,os) in enumerate(zip(clip['samplers'],original['samplers'])):
  assert {k:v for k,v in sample.items() if k not in ('input','output')}=={k:v for k,v in os.items() if k not in ('input','output')}
  assert np.array_equal(accessor(d,b,sample['input']),accessor(old,ob,os['input']))
  expected=accessor(old,ob,os['output'])
  channels=[c for c in original['channels'] if c['sampler']==index]
  if torso_binding and original['name']!='idle' and channels:
   target=channels[0]['target'];node=old['nodes'][target['node']]
   factor={'chest':.2,'head':.5}.get(node.get('name')) if target['path']=='rotation' else None
   if factor is not None:
    assert all(c['target']==target for c in channels),'unexpected shared torso sampler'
    rest=np.asarray(node.get('rotation',[0,0,0,1]))
    expected=qmul(rest,qfraction(qmul(qconj(rest),expected),factor)).astype(expected.dtype)
  assert np.array_equal(accessor(d,b,sample['output']),expected),(clip['name'],index,'unexpected animation output')
g=globals_of(d);bind=accessor(d,b,d['skins'][0]['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
for slot,node in enumerate(d['skins'][0]['joints']):assert np.max(abs(g[node]@bind[slot]-np.eye(4)))<2e-6,('bind mismatch',d['nodes'][node]['name'])
print('Stone rear: three closed components, rigid hind skin, protected crown/head/feet/UVs, matching rig; clips unchanged except exact marked torso rotations' if torso_binding else 'Stone rear: three closed components, rigid hind skin, protected crown/head/feet/UVs, matching rig and unchanged clips')
