"""Synchronize the Light beetle's continuous armour and authored animation.

Arguments: restored-surface candidate, accepted030 baseline, output candidate.
Requires numpy/scipy/Pillow. Writes a candidate only. Keeps all bone rests and
bind matrices intact; six planted limbs remain independent runtime supports.
"""
from pathlib import Path
import sys,numpy as np
from scipy.spatial import cKDTree
from scipy.spatial.transform import Rotation
sys.path.insert(0,'tools/models')
from inspect_geometry import read_glb,accessor,triangles
from upgrade_rigs import Writer
from repair_water_beetle import read_weights
from repair_beetles import store_weights,smooth
from compact_glb import compact
assert len(sys.argv)==4,'RESTORED_INPUT BASELINE030 OUTPUT required'
d,b=read_glb(sys.argv[1]);writer=Writer(d,b);parts=list(triangles(d,b));names=[d['nodes'][i]['name'] for i in d['skins'][0]['joints']]
for node in d['nodes']:
 if 'mesh' in node:
  node.setdefault('extras',{}).update(sfery_rigid_limbs=True,sfery_turn_stance=True,sfery_middle_stride=.85)
# The complete rear shell moves at the socket. Mixing the torso into its
# narrowed proximal section folded its closed surface under a planted stance.
for side,start in [('L',2),('R',4)]:
 mass=np.zeros((len(parts[start][1]),len(names)));mass[:,names.index('rear_thigh.'+side)]=1
 for i in [start,start+1]:store_weights(writer,parts[i][0],mass)
# Use the same local lower-joint pose in authored channels and runtime support,
# including the first frame before the procedural support has run.
for clip in d['animations']:
 for channel in clip['channels']:
  node=d['nodes'][channel['target']['node']];name=node.get('name','');path=channel['target']['path'];sampler=clip['samplers'][channel['sampler']];old=accessor(d,b,sampler['output'])
  assert sampler.get('interpolation','LINEAR')!='CUBICSPLINE'
  if name.startswith(('forearm.','hand.','shin.','foot.','rear_shin.','rear_foot.')):
   value=node.get(path,{'rotation':[0,0,0,1],'translation':[0,0,0],'scale':[1,1,1]}[path]);sampler['output']=writer.add(np.tile(value,(len(old),1)),'VEC4' if path=='rotation' else 'VEC3')
  elif path=='rotation' and ((clip['name']=='idle' and name in ['chest','head']) or (clip['name']=='stance' and name=='hips') or (clip['name']!='idle' and name in ['chest','head','shell'])):
   rest=Rotation.from_quat(node.get('rotation',[0,0,0,1]));factor=.3 if clip['name']=='idle' or name=='hips' else {'chest':.2,'head':.35,'shell':0}[name];q=(rest*Rotation.from_rotvec((rest.inv()*Rotation.from_quat(old)).as_rotvec()*factor)).as_quat();sampler['output']=writer.add(q,'VEC4')
# Original restored ankle faces meet the historical torso-biased skin smoothly.
# Fade along the immediate neighbourhood instead of inserting a weight jump.
p,v,f=parts[0];w=read_weights(d,b,p,len(names));od,ob=read_glb(sys.argv[2]);ov=next(triangles(od,ob))[1];distance,_=cKDTree(ov).query(v);restored=(distance>1e-6)&(v[:,1]<-.20);assert restored.any();distance,_=cKDTree(v[restored]).query(v);blend=1-smooth(distance/.04)
for side in ['L','R']:
 slots=[names.index(x+'.'+side) for x in ['thigh','shin','foot']];mass=w[:,slots].sum(1);use=mass>.5;original=w[use].copy();target=np.zeros_like(original);target[:,slots]=original[:,slots]/mass[use,None];w[use]=original*(1-blend[use,None])+target*blend[use,None]
for i in [0,1]:store_weights(writer,parts[i][0],w)
d['asset'].setdefault('extras',{})['light_motion_repair035']=1;out=Path(sys.argv[3]);out.parent.mkdir(parents=True,exist_ok=True);writer.save(out);compact(out)
