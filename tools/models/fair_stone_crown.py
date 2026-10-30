"""Remove the voxel terraces left on the repaired Stone crown.

Run from the repository root with scipy/numpy. Immutable input: repair033/base;
output is a candidate only. The fitted crown envelope comes from intact armour.
Only the upper rear crown changes; UVs, skin weights and rig remain identical.
"""
from pathlib import Path
import sys,numpy as np
from scipy.sparse import coo_matrix,diags
sys.path.insert(0,'tools/models')
from inspect_geometry import read_glb,accessor,triangles
from upgrade_rigs import Writer
from compact_glb import compact
from repair_beetles import smooth
source=Path('tools/_tmp/repair033/base/rogozhuk_stone.glb');d,b=read_glb(source);p,v,f=next(triangles(d,b));old_n=accessor(d,b,p['attributes']['NORMAL']);writer=Writer(d,b)
rounded,first,uid=np.unique(np.round(v,6),axis=0,return_index=True,return_inverse=True);u=v[first].astype(float);original=u.copy();faces=uid[f]
edges=np.unique(np.sort(np.concatenate([faces[:,[0,1]],faces[:,[1,2]],faces[:,[2,0]]]),axis=1),axis=0)
graph=coo_matrix((np.ones(len(edges)*2),(np.r_[edges[:,0],edges[:,1]],np.r_[edges[:,1],edges[:,0]])),shape=(len(u),len(u))).tocsr();degree=np.asarray(graph.sum(1)).ravel();average=diags(1/np.maximum(degree,1))@graph
mask=smooth((u[:,1]-.14)/.12)*smooth((.17-u[:,2])/.10)
center=np.array([-.02093199,-.2,-.03341677]);radii=np.array([.36766731,.59244424,.38640222])
radius=np.linalg.norm((u-center)/radii,axis=1)
target=center+(u-center)/radius[:,None]
u+=.92*mask[:,None]*(target-u)
for _ in range(4):
 for factor in [.5,-.53]:u+=factor*mask[:,None]*(average@u-u)
normal=np.zeros_like(u);t=u[faces];area=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0])
for k in range(3):np.add.at(normal,faces[:,k],area)
normal/=np.maximum(np.linalg.norm(normal,axis=1,keepdims=True),1e-12)
n=old_n*(1-mask[uid,None])+normal[uid]*mask[uid,None];n/=np.maximum(np.linalg.norm(n,axis=1,keepdims=True),1e-12)
p['attributes']['POSITION']=writer.add(u[uid],'VEC3');p['attributes']['NORMAL']=writer.add(n,'VEC3');d['asset'].setdefault('extras',{})['stone_crown_fairing']=2
out=Path('tools/_tmp/repair033/crown-rebuilt/rogozhuk_stone.glb');out.parent.mkdir(parents=True,exist_ok=True);writer.save(out);compact(out)
print('maximum crown displacement',np.linalg.norm(u-original,axis=1).max(),'unchanged below y=.14',np.array_equal(u[original[:,1]<=.14],original[original[:,1]<=.14]),flush=True)
