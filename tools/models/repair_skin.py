"""Recover continuous skin transitions without changing meshes, rests or clips.

Uses original v1 weights as the source and a saved final model as the baseline.
The screened cotangent Laplacian smooths on the welded surface in physical units;
eight influences preserve overlapping shoulder/wing and weapon/body transitions.
Requires NumPy and SciPy. Run from the project root; never discard the baseline.
"""
from pathlib import Path
import sys,shutil,numpy as np
from scipy.sparse import coo_matrix,diags
from scipy.sparse.linalg import splu
from inspect_geometry import read_glb,accessor,triangles
from upgrade_rigs import Writer

def smooth_surface_weights(v,f,w,sigma):
 # Weld UV copies, then diffuse smoothly on the actual surface rather than assigning whole branches.
 _,uid=np.unique(np.round(v,6),axis=0,return_inverse=True);uid=uid.reshape(-1);count=np.bincount(uid)
 pooled=np.zeros((len(count),w.shape[1]));np.add.at(pooled,uid,w);w=pooled/count[:,None]
 vertices=np.zeros((len(count),3));np.add.at(vertices,uid,v);vertices/=count[:,None]
 faces=uid[f];points=vertices[faces];cross=np.linalg.norm(np.cross(points[:,1]-points[:,0],points[:,2]-points[:,0]),axis=1)
 mass=np.bincount(faces.ravel(),weights=np.repeat(cross/6,3),minlength=len(w))
 rows=[];cols=[];conduct=[]
 for i,j,k in [(0,1,2),(1,2,0),(2,0,1)]:
  value=np.sum((points[:,i]-points[:,k])*(points[:,j]-points[:,k]),axis=1)/np.maximum(cross,1e-12)*.5
  rows.extend([faces[:,i],faces[:,j]]);cols.extend([faces[:,j],faces[:,i]]);conduct.extend([value,value])
 adj=coo_matrix((np.concatenate(conduct),(np.concatenate(rows),np.concatenate(cols))),shape=(len(w),len(w))).tocsr()
 adj.data=np.maximum(adj.data,0)
 lap=diags(np.asarray(adj.sum(1)).ravel())-adj
 matrix=(diags(np.maximum(mass,1e-12))+sigma*sigma*lap).tocsc()
 initial=w.copy()
 w=splu(matrix).solve(mass[:,None]*w)
 w[mass<1e-12]=initial[mass<1e-12]
 w=np.maximum(w,0);w/=np.maximum(w.sum(1,keepdims=True),1e-12)
 return w[uid]

def repair(path,source,backup):
 current,_=read_glb(path)
 if current.get('asset',{}).get('extras',{}).get('sfery_skin_repair',0)>=5:return
 backup.mkdir(parents=True,exist_ok=True)
 if not (backup/path.name).exists():shutil.copy2(path,backup/path.name)
 doc,binary=read_glb(backup/path.name);old,ob=read_glb(backup/path.name if source.resolve()==path.resolve() else source)
 writer=Writer(doc,binary);skin=doc['skins'][0];oldskin=old['skins'][0]
 names=[doc['nodes'][n]['name'] for n in skin['joints']];oldnames=[old['nodes'][n]['name'] for n in oldskin['joints']]
 parents={ch:i for i,n in enumerate(doc['nodes']) for ch in n.get('children',[])}
 groups={name:[names.index(name)] for name in oldnames}
 for i,name in enumerate(names):
  if name in oldnames:continue
  if name.startswith('clavicle.'):
   donor='arm.'+name[-1]
  else:
   node=skin['joints'][i]
   while node in parents and doc['nodes'][node]['name'] not in oldnames:node=parents[node]
   donor=doc['nodes'][node]['name']
  if donor in groups:groups[donor].append(i)
 for (prim,v,f),(op,ov,_) in zip(triangles(doc,binary),triangles(old,ob)):
  assert np.array_equal(v,ov),(path.name,'source geometry mismatch')
  js=accessor(doc,binary,prim['attributes']['JOINTS_0']).astype(int);ws=accessor(doc,binary,prim['attributes']['WEIGHTS_0'])
  current=np.zeros((len(v),len(names)));np.add.at(current,(np.arange(len(v))[:,None],js),ws)
  oj=accessor(old,ob,op['attributes']['JOINTS_0']).astype(int);ow=accessor(old,ob,op['attributes']['WEIGHTS_0'])
  original=np.zeros((len(v),len(oldnames)));np.add.at(original,(np.arange(len(v))[:,None],oj),ow)
  w=np.zeros_like(current)
  for col,name in enumerate(oldnames):
   group=groups[name];total=current[:,group].sum(1);fractions=np.divide(current[:,group],total[:,None],out=np.zeros((len(v),len(group))),where=total[:,None]>1e-8)
   fractions[total<1e-8,0]=1
   w[:,group]=original[:,col,None]*fractions
  w=smooth_surface_weights(v,f,w,np.ptp(v[:,1])*.025)
  top=np.argsort(-w,axis=1)[:,:8];weights=np.take_along_axis(w,top,axis=1);weights/=weights.sum(1,keepdims=True)
  prim['attributes']['JOINTS_0']=writer.add(top[:,:4],'VEC4',5123);prim['attributes']['WEIGHTS_0']=writer.add(weights[:,:4],'VEC4')
  prim['attributes']['JOINTS_1']=writer.add(top[:,4:],'VEC4',5123);prim['attributes']['WEIGHTS_1']=writer.add(weights[:,4:],'VEC4')
 doc['asset'].setdefault('extras',{})['sfery_skin_repair']=5;writer.save(path)

if __name__=='__main__':
 for p in sorted(Path('assets/creatures_hd').glob('*.glb')):
  if p.stem.startswith(('glubinnik','sumrachnik')):continue
  source=Path('tools/ai_models/rigged')/p.name
  if p.stem=='kolossar_light':source=Path('tools/_tmp/lightclean026-v1')/p.name
  if p.stem=='rogozhuk_stone':source=Path('tools/_tmp/rebuilt026-v1')/p.name
  if p.stem=='likorez_shadow':source=p
  repair(p,source,Path('tools/_tmp/skin027-base'));print('REPAIRED',p.stem,flush=True)
