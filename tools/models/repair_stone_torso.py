"""Align Stone torso skin and reaction clips with its solid shell and limbs.

Run from the repository root with scipy/numpy. Reads the immutable pre-035
backup and writes an isolated candidate; never installs assets automatically.
Geometry, UVs, skeleton rests, bind matrices, idle and all animation times stay
unchanged. Chest/head reaction range and localized body skin are corrected.
"""
from pathlib import Path
import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import dijkstra
from inspect_geometry import read_glb,accessor,triangles
from repair_water_beetle import read_weights
from repair_beetles import store_weights,smooth
from upgrade_rigs import Writer,globals_of,qmul,qconj,qfraction
from compact_glb import compact

SOURCE=Path('tools/_tmp/repair035-stone/base/rogozhuk_stone.glb')
OUTPUT=Path('tools/_tmp/repair035-stone/final/rogozhuk_stone.glb')

def repair():
 d,b=read_glb(SOURCE);writer=Writer(d,b)
 for clip in d['animations']:
  if clip['name']=='idle':continue
  for channel in clip['channels']:
   node=d['nodes'][channel['target']['node']];factor={'chest':.2,'head':.5}.get(node.get('name',''))
   if factor is None or channel['target']['path']!='rotation':continue
   sampler=clip['samplers'][channel['sampler']];rotation=accessor(d,b,sampler['output']);rest=np.asarray(node.get('rotation',[0,0,0,1]))
   sampler['output']=writer.add(qmul(rest,qfraction(qmul(qconj(rest),rotation),factor)),'VEC4')
 parts=list(triangles(d,b))[:2];v=np.concatenate([part[1] for part in parts]);f=np.concatenate([parts[0][2],parts[1][2]+len(parts[0][1])])
 _,first,uid=np.unique(np.round(v,6),axis=0,return_index=True,return_inverse=True);u=v[first];faces=uid[f]
 edges=np.unique(np.sort(np.concatenate([faces[:,[0,1]],faces[:,[1,2]],faces[:,[2,0]]]),axis=1),axis=0)
 lengths=np.linalg.norm(u[edges[:,0]]-u[edges[:,1]],axis=1);graph=coo_matrix((lengths,edges.T),shape=(len(u),)*2).tocsr()
 seeds=np.unique(uid[len(parts[0][1]):][parts[1][2]])
 distance=dijkstra(graph,directed=False,indices=seeds,min_only=True,limit=.04)
 socket=smooth(1-distance/.04)
 # The anterior side of the solid right middle-leg root is not belly skin.
 # It inherited front-arm bleed, and the belly ramp also caught its edge.
 right_root=(u[:,0]>.14)&(u[:,0]<.185)&(u[:,1]>-.17)&(u[:,1]<-.11)&(u[:,2]>-.10)&(u[:,2]<-.055)
 root_distance=dijkstra(graph,directed=False,indices=np.flatnonzero(right_root),min_only=True,limit=.05)
 root_amount=smooth(1-root_distance/.05)
 transforms=globals_of(d);nodes={n.get('name'):i for i,n in enumerate(d['nodes'])};names=[d['nodes'][i]['name'] for i in d['skins'][0]['joints']];hip=names.index('hips')
 origin=transforms[nodes['chest']][:3,3].copy();origin[1]=0
 forward=transforms[nodes['head']][:3,3]-transforms[nodes['chest']][:3,3];forward[1]=0;forward/=np.linalg.norm(forward)
 frame=np.column_stack([np.cross([0,1,0],forward),[0,1,0],forward]);offset=0
 for primitive,vertices,_ in parts:
  weights=read_weights(d,b,primitive,len(names));amount=socket[uid[offset:offset+len(vertices)]]
  weights*=1-amount[:,None];weights[:,hip]+=amount
  # The central belly inherited thigh weights although it is separated from
  # the actual legs. Keep the front head and distal feet outside this region.
  c=(vertices-origin)@frame
  amount=smooth((.20-np.abs(c[:,0]))/.07)*smooth((.14-c[:,2])/.10)*smooth((c[:,2]+.32)/.10)*smooth((c[:,1]+.27)/.05)
  weights*=1-amount[:,None];weights[:,hip]+=amount
  amount=root_amount[uid[offset:offset+len(vertices)]]
  weights*=1-amount[:,None];weights[:,names.index('thigh.R')]+=amount
  store_weights(writer,primitive,weights);offset+=len(vertices)
 for node in d['nodes']:
  if node.get('extras',{}).get('sfery_rigid_limbs'):
   node['extras']['sfery_middle_stride']=.85
 d['asset'].setdefault('extras',{})['stone_torso_binding']=1
 OUTPUT.parent.mkdir(parents=True,exist_ok=True);writer.save(OUTPUT);compact(OUTPUT)

if __name__=='__main__':repair()
