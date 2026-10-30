"""Cape partition preserves every original corner; only cloth uses four weights."""
import sys
from pathlib import Path
import numpy as np
root=Path(__file__).resolve().parents[1];sys.path.insert(0,str(root/'tools/models'))
from inspect_geometry import read_glb,accessor,triangles
from upgrade_rigs import globals_of

def corners(doc,blob):
 out=[]
 for p,v,f in triangles(doc,blob):
  normal=accessor(doc,blob,p['attributes']['NORMAL']);uv=accessor(doc,blob,p['attributes']['TEXCOORD_0']);out.append(np.concatenate([v,normal,uv],axis=1)[f].reshape(-1,24))
 a=np.ascontiguousarray(np.concatenate(out));return np.sort(a.view(np.dtype((np.void,a.dtype.itemsize*24))).ravel())
for path in sorted((root/'assets/creatures_hd').glob('ratnik_*.glb')):
 d,b=read_glb(path);assert d['asset']['extras'].get('sfery_gpu_cape')==1
 assert len(d['meshes'])==2
 body,cape=list(triangles(d,b));bp,bv,bf=body;cp,cv,cf=cape
 assert 'JOINTS_1' in bp['attributes'] and 'JOINTS_1' not in cp['attributes']
 mask=accessor(d,b,cp['attributes']['COLOR_0'])[:,0];assert (mask==0).sum()>20 and (mask>.9).sum()>1000
 bodykeys=np.ascontiguousarray(np.round(bv,6));capekeys=np.ascontiguousarray(np.round(cv,6));boundary=np.isin(capekeys.view('V12').ravel(),bodykeys.view('V12').ravel())
 assert boundary.sum()>20 and mask[boundary].max()<1e-5,(path.name,'free seam')
 w=accessor(d,b,cp['attributes']['WEIGHTS_0']);assert np.abs(w.sum(1)-1).max()<2e-6
 reference=root/'tools/_tmp/gpucloth028-base'/path.name
 if reference.exists():
  old,ob=read_glb(reference);assert np.array_equal(corners(old,ob),corners(d,b)),(path.name,'changed original surface/UV/normals')
  assert all(np.max(np.abs(a-z))<1e-10 for a,z in zip(globals_of(old),globals_of(d)))
  for a,z in zip(old['animations'],d['animations']):
   assert a['channels']==z['channels']
   for s,t in zip(a['samplers'],z['samplers']):
    for k in ['input','output']:assert np.array_equal(accessor(old,ob,s[k]),accessor(d,b,t[k]))
 print(path.stem,'body/cape, pinned seam, original surface and clips OK')
