"""Характерные части тела действительно анимированы, оружие и уши корректно привязаны."""
import sys
from pathlib import Path
import numpy as np
root=Path(__file__).resolve().parents[1];sys.path.insert(0,str(root/'tools/models'))
from inspect_geometry import read_glb,accessor,triangles
traits={
 'dragnar':[('idle','tail3'),('attack','wing.L')],
 'klykar':[('idle','tail2'),('idle','ear.L'),('idle','ear.R')],
 'ratnik':[('attack','sword'),('attack','cape2')],
 'grifalon':[('idle','wing.L'),('attack','wingtip.R')],
 'kolossar':[('attack','chest'),('attack','forearm.R')],
 'rogozhuk':[('attack','horn'),('roar','shell')],
 'levian':[('idle','neck2'),('attack','neck3')],
 'gorgul':[('idle','wing.R'),('attack','tail2')],
}
checks=0;models=0
for path in sorted((root/'assets/creatures_hd').glob('*.glb')):
 sp=path.stem.rsplit('_',1)[0]
 if sp not in traits:continue
 doc,binary=read_glb(path);skin=doc['skins'][0];names={doc['nodes'][n]['name']:n for n in skin['joints']}
 assert doc['asset']['extras']['sfery_personality_version']==1,path.name
 for clip,bone in traits[sp]:
  animation=next(a for a in doc['animations'] if a['name']==clip);channels=[ch for ch in animation['channels'] if ch['target']=={'node':names[bone],'path':'rotation'}]
  assert len(channels)==1,(path.name,bone,'duplicate or missing channel')
  values=accessor(doc,binary,animation['samplers'][channels[0]['sampler']]['output'])
  assert np.linalg.norm(values-values[0],axis=1).max()>.015,(path.name,bone,'static')
  checks+=1
 for animation in doc['animations']:
  keys=[(c['target']['node'],c['target']['path']) for c in animation['channels']]
  assert len(keys)==len(set(keys)),(path.name,'duplicate channel targets')
 if sp=='ratnik':
  assert names['sword'] in doc['nodes'][names['hand.L']].get('children',[]),(path.name,'sword grip')
  checks+=1
 if sp=='klykar':
  for ear in ['ear.L','ear.R']:
   slot=skin['joints'].index(names[ear]);count=0
   for prim,v,f in triangles(doc,binary):
    js=accessor(doc,binary,prim['attributes']['JOINTS_0']);ws=accessor(doc,binary,prim['attributes']['WEIGHTS_0']);count+=int((np.where(js==slot,ws,0).sum(1)>.05).sum())
   assert count>20,(path.name,ear,'no bound vertices');checks+=1
 models+=1
print(f'Индивидуальность: {models} моделей, {checks} проверок характерных частей: OK')
