"""Проверка данных всех 48 GLB после обновления скелетов. --reference /tmp/sfery-rig-v1 проверяет сохранность исходников."""
import argparse,sys
from pathlib import Path
import numpy as np
root=Path(__file__).resolve().parents[1];sys.path.insert(0,str(root/'tools/models'))
from inspect_geometry import read_glb,accessor,triangles
from upgrade_rigs import globals_of
args=argparse.ArgumentParser();args.add_argument('--reference');args=args.parse_args();checked=0;bones=0
for path in sorted((root/'assets/creatures_hd').glob('*.glb')):
 if path.stem.startswith(('glubinnik','sumrachnik','likorez')):continue  # Separate 35-bone rig: tests/likorez_tests.gd.
 doc,binary=read_glb(path);gs=globals_of(doc);skin=doc['skins'][0];joint_count=len(skin['joints']);bones+=joint_count
 old,oldbin=read_glb(Path(args.reference)/path.name) if args.reference else (None,None)
 assert len({doc['nodes'][n]['name'] for n in skin['joints']})==joint_count,(path.name,'duplicate joint names')
 assert doc['asset']['extras']['sfery_rig_version']==2,path.name
 inverse=accessor(doc,binary,skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
 for slot,node in enumerate(skin['joints']):
  assert np.abs(gs[node]@inverse[slot]-np.eye(4)).max()<2e-5,(path.name,'bind',slot)
 for prim,v,f in triangles(doc,binary):
  js=accessor(doc,binary,prim['attributes']['JOINTS_0']);ws=accessor(doc,binary,prim['attributes']['WEIGHTS_0'])
  assert np.isfinite(ws).all() and np.isfinite(v).all(),path.name
  assert js.max()<joint_count and (ws>=0).all(),path.name
  assert np.abs(ws.sum(1)-1).max()<2e-6,(path.name,'normalization')
 for animation in doc['animations']:
  for channel in animation['channels']:
   sampler=animation['samplers'][channel['sampler']];values=accessor(doc,binary,sampler['output'])
   assert np.isfinite(values).all(),(path.name,'keyframe')
   if channel['target']['path']=='rotation':
    assert np.abs(np.linalg.norm(values,axis=1)-1).max()<1e-4,(path.name,'quaternion')
    name=doc['nodes'][channel['target']['node']].get('name','')
    if old and channel['target']['node']>=len(old['nodes']) and animation.get('name')=='attack' and name.startswith(('hand.','foot.','wingfan.','toes.','fingers.','feathers.')):
     assert np.linalg.norm(values-values[0],axis=1).max()>.015,(path.name,'missing distal animation',name)
 if args.reference:
  oldgs=globals_of(old)
  assert binary[:len(oldbin)]==oldbin,(path.name,'original binary changed')
  for i,g in enumerate(oldgs):assert np.abs(gs[i]-g).max()<2e-5,(path.name,'rest changed')
  for (op,ov,of),(np_,nv,nf) in zip(triangles(old,oldbin),triangles(doc,binary)):
   assert np.array_equal(ov,nv) and np.array_equal(of,nf),(path.name,'geometry')
   for attr in ['NORMAL','TEXCOORD_0']:
    assert np.array_equal(accessor(old,oldbin,op['attributes'][attr]),accessor(doc,binary,np_['attributes'][attr])),(path.name,attr)
 checked+=1
print(f'Скелеты: {checked} моделей, {bones} костей. Поза покоя, веса, кватернионы и исходная геометрия: OK')
