"""Validate the local Stone crown fairing; pose intersections are a separate check."""
from pathlib import Path
import sys,numpy as np,trimesh
root=Path(__file__).resolve().parents[1];sys.path.insert(0,str(root/'tools/models'))
from inspect_geometry import read_glb,accessor,triangles
# This stage precedes the separate hind-leg reconstruction. The latter has its
# own preservation test against this exact intermediate crown.
path=Path(sys.argv[1]) if len(sys.argv)>1 else root/'tools/_tmp/repair033/crown-rebuilt/rogozhuk_stone.glb'
d,b=read_glb(path);old,ob=read_glb(root/'tools/_tmp/repair033/base/rogozhuk_stone.glb');p,v,f=next(triangles(d,b));op,ov,of=next(triangles(old,ob))
assert np.array_equal(f,of),'crown repair must retain topology'
assert np.array_equal(v[(ov[:,1]<=.14)|(ov[:,2]>=.17)],ov[(ov[:,1]<=.14)|(ov[:,2]>=.17)]),'protected head/lower body changed'
assert np.linalg.norm(v-ov,axis=1).max()<.02,'excessive crown displacement'
for name in ['TEXCOORD_0','JOINTS_0','JOINTS_1','WEIGHTS_0','WEIGHTS_1']:
 assert np.array_equal(accessor(d,b,p['attributes'][name]),accessor(old,ob,op['attributes'][name])),name
assert d['nodes']==old['nodes']
assert np.array_equal(accessor(d,b,d['skins'][0]['inverseBindMatrices']),accessor(old,ob,old['skins'][0]['inverseBindMatrices']))
for a,oa in zip(d['animations'],old['animations']):
 assert a['channels']==oa['channels']
 for s,os in zip(a['samplers'],oa['samplers']):
  for key in ['input','output']:assert np.array_equal(accessor(d,b,s[key]),accessor(old,ob,os[key]))
m=trimesh.Trimesh(v,f,process=True)
assert m.is_watertight and m.is_winding_consistent
assert m.area_faces.min()>1e-12
normal=accessor(d,b,p['attributes']['NORMAL']);assert np.isfinite(normal).all() and np.max(abs(np.linalg.norm(normal,axis=1)-1))<1e-5
# Compare the crown to the same envelope used to reconstruct the original dent.
center=np.array([-.02093199,-.2,-.03341677]);radii=np.array([.36766731,.59244424,.38640222]);region=(ov[:,1]>.26)&(ov[:,2]<.07)
old_error=abs(np.linalg.norm((ov[region]-center)/radii,axis=1)-1);new_error=abs(np.linalg.norm((v[region]-center)/radii,axis=1)-1)
assert np.mean(new_error)<np.mean(old_error)*.15,'crown terraces remain'
print('Stone crown: closed surface, unchanged lower body/UV/skin/rig/clips; envelope error',float(old_error.mean()),'->',float(new_error.mean()))
