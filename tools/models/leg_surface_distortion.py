"""Measure leg triangle area loss and edge stretch in actual Godot poses.

This complements intersection checks: a shin can collapse without crossing
itself. Large area loss identifies candidates for visual inspection, not an
artistic pass/fail threshold by itself.
"""
import json,sys
from pathlib import Path
import numpy as np

def measure(folder, rear=False):
 doc=json.loads((folder/'poses.json').read_text());rows=[]
 for mesh in doc['meshes']:
  prefix=folder/mesh['prefix']
  def read(name,dtype):return np.fromfile(str(prefix)+'_'+name+'.bin',dtype)
  v=read('vertices',np.float32).reshape(-1,3);j=read('joints',np.int32).reshape(-1,mesh['stride']);w=read('weights',np.float32).reshape(j.shape);f=read('indices',np.int32).reshape(-1,3)
  prefixes=('rear_thigh.','rear_shin.','rear_foot.') if rear else ('thigh.','shin.','foot.')
  leg=np.array([n.startswith(prefixes) for n in mesh['bones']]);influence=(leg[j]*w).sum(1)
  triangle=v[f];area=np.linalg.norm(np.cross(triangle[:,1]-triangle[:,0],triangle[:,2]-triangle[:,0]),axis=1)
  f=f[(influence[f].min(1)>.7)&(area>1e-8)]
  if not len(f):continue
  used,remap=np.unique(f,return_inverse=True);v=v[used];j=j[used];w=w[used];f=remap.reshape(-1,3)
  triangle=v[f];area=np.linalg.norm(np.cross(triangle[:,1]-triangle[:,0],triangle[:,2]-triangle[:,0]),axis=1)
  for pose in doc['poses']:
   palette=np.asarray(pose['palettes'][mesh['mi']]).reshape(-1,3,4);posed=np.zeros_like(v)
   for k in range(j.shape[1]):
    matrix=palette[j[:,k]];posed+=(np.einsum('nij,nj->ni',matrix[:,:,:3],v)+matrix[:,:,3])*w[:,k,None]
   t=posed[f];ratio=np.linalg.norm(np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]),axis=1)/area
   worst=int(ratio.argmin())
   rows.append({'action':pose['action'],'frame':pose['frame'],'min_area_ratio':float(ratio[worst]),'p01_area_ratio':float(np.quantile(ratio,.01)),'area_fraction_below_half':float(area[ratio<.5].sum()/area.sum()),'worst_rest_point':triangle[worst].mean(0).tolist()})
 return {'id':doc['id'],'poses':rows,'worst':min(rows,key=lambda r:r['min_area_ratio'])}
if __name__=='__main__':
 for source in [arg for arg in sys.argv[1:] if arg!='--rear']:
  root=Path(source);report=[measure(folder, rear='--rear' in sys.argv) for folder in sorted(root.iterdir()) if (folder/'poses.json').exists()]
  Path(str(root)+'-surface.json').write_text(json.dumps(report,indent=2))
  for model in report:print(source,model['id'],model['worst'],flush=True)
