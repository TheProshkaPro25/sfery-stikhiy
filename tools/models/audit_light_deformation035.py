"""Blender BVH audit of actual Godot Light meshes and skin palettes.

Arguments after --: exported creature directory, output JSON, optional shard
index/count. Geometrically adjacent faces are excluded. Body, independent rear
limbs, and their intentional socket overlap are reported separately.
"""
import json,sys,os
from pathlib import Path
import numpy as np
from mathutils.bvhtree import BVHTree
from collections import Counter
root=Path(sys.argv[sys.argv.index('--')+1]);out=Path(sys.argv[sys.argv.index('--')+2]);d=json.loads((root/'poses.json').read_text());meshes=[];ff=[];rest=[];tags=[];bone_tags=[];offset=0
for i,mesh in enumerate(d['meshes']):
 prefix=root/mesh['prefix'];read=lambda n,t:np.fromfile(str(prefix)+'_'+n+'.bin',t);v=read('vertices',np.float32).reshape(-1,3);j=read('joints',np.int32).reshape(-1,mesh['stride']);w=read('weights',np.float32).reshape(j.shape);f=read('indices',np.int32).reshape(-1,3);used,remap=np.unique(f,return_inverse=True);v=v[used];j=j[used];w=w[used];f=remap.reshape(-1,3);meshes.append((mesh,v,j,w));ff.append(f+offset);rest.append(v);tags.extend([i]*len(f));mass=np.zeros((len(v),len(mesh['bones'])))
 for k in range(j.shape[1]):np.add.at(mass,(np.arange(len(v)),j[:,k]),w[:,k])
 bone_tags.extend([mesh['bones'][k] for k in mass[f].mean(1).argmax(1)]);offset+=len(v)
f=np.concatenate(ff);rest=np.concatenate(rest);tags=np.array(tags);bone_tags=np.array(bone_tags);_,uid=np.unique(np.round(rest,6),axis=0,return_inverse=True);rows=[]
args=sys.argv[sys.argv.index('--')+3:];chunk=int(args[0]) if args else 0;chunks=int(args[1]) if len(args)>1 else 1
for pi,pose in enumerate([{'action':'rest','frame':0}]+d['poses']):
 if pi%chunks!=chunk:continue
 vs=[]
 for mesh,v,j,w in meshes:
  if pose['action']=='rest':vs.append(v);continue
  pal=np.array(pose['palettes'][mesh['mi']]).reshape(-1,3,4);posed=np.zeros_like(v)
  for k in range(j.shape[1]):
   m=pal[j[:,k]];posed+=(np.einsum('nij,nj->ni',m[:,:,:3],v)+m[:,:,3])*w[:,k,None]
  vs.append(posed)
 v=np.concatenate(vs);tree=BVHTree.FromPolygons(v.tolist(),f.tolist(),all_triangles=True);pairs=np.array([(a,b) for a,b in tree.overlap(tree) if a<b],int).reshape(-1,2);pairs=pairs[~(uid[f[pairs[:,0]]][:,:,None]==uid[f[pairs[:,1]]][:,None,:]).any((1,2))]
 body=pairs[(tags[pairs]<2).all(1)];rear=pairs[(tags[pairs]>=2).all(1)];cross=pairs[((tags[pairs]<2).sum(1)==1)]
 detail=Counter(map(tuple,np.sort(bone_tags[body],axis=1)))
 if pose['action']=='rest':print('REAR PARTS',Counter(map(tuple,np.sort(tags[rear],axis=1))),flush=True)
 row={'action':pose['action'],'frame':pose['frame'],'body':len(body),'rear':len(rear),'cross':len(cross),'bones':[(list(k),n) for k,n in detail.most_common(8)]};rows.append(row)
 if pose['action']=='rest' or len(body)>0:print(row,flush=True)
 if len(rear):np.savez(out.with_name(out.stem+'-rear-'+pose['action']+'-'+str(pose['frame'])+'.npz'),face_ids=rear,points=v[f[rear]],rest_points=rest[f[rear]],tags=tags[rear],bones=bone_tags[rear])
 if len(body):np.savez(out.with_name(out.stem+'-'+pose['action']+'-'+str(pose['frame'])+'.npz'),face_ids=body,points=v[f[body]],rest_points=rest[f[body]],tags=tags[body],bones=bone_tags[body])
out.write_text(json.dumps(rows,indent=2));print('WORST',max(rows,key=lambda x:x['body']),flush=True);sys.stdout.flush();os._exit(0)
