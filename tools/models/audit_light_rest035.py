"""Blender BVH audit of the complete Light body exterior, excluding adjacent faces.
Arguments after --: input GLB, optional NPZ output.
"""
import sys,os,json,numpy as np
from pathlib import Path
from mathutils.bvhtree import BVHTree
sys.path.insert(0,'tools/models')
from inspect_geometry import read_glb,triangles
args=sys.argv[sys.argv.index('--')+1:];d,b=read_glb(args[0]);parts=list(triangles(d,b));group=list(range(2)) if len(parts)==6 else [0];vs=[];fs=[];tags=[];off=0
for i in group:
 p,v,f=parts[i];vs.append(v);fs.append(f+off);tags.extend([i]*len(f));off+=len(v)
v=np.concatenate(vs);f=np.concatenate(fs);tags=np.array(tags);_,uid=np.unique(np.round(v,6),axis=0,return_inverse=True);tree=BVHTree.FromPolygons(v.tolist(),f.tolist(),all_triangles=True);pairs=np.array([(a,b) for a,b in tree.overlap(tree) if a<b],int).reshape(-1,2);pairs=pairs[~(uid[f[pairs[:,0]]][:,:,None]==uid[f[pairs[:,1]]][:,None,:]).any((1,2))];print('body',len(pairs),'low feet',int((v[f[pairs],1].max((1,2))<-.24).sum()),flush=True)
if len(args)>1:np.savez(args[1],face_ids=pairs,points=v[f[pairs]],tags=tags[pairs])
print('bbox',v[f[pairs]].min((0,1,2)) if len(pairs) else None,v[f[pairs]].max((0,1,2)) if len(pairs) else None,flush=True);sys.stdout.flush();os._exit(0)
