"""Evaluate changed weights against previously captured real poses without reimporting textures."""
import sys,json,numpy as np
from pathlib import Path
from scipy.spatial import cKDTree
from inspect_geometry import read_glb,accessor,triangles
key=sys.argv[1];folder=Path('tools/_tmp/deformation027/creature_'+key);meta=json.loads((folder/'poses.json').read_text());m=meta['meshes'][0]
v=np.fromfile(folder/'0_0_vertices.bin',np.float32).reshape(-1,3);f=np.fromfile(folder/'0_0_indices.bin',np.int32).reshape(-1,3)
d,b=read_glb('assets/creatures_hd/'+key+'.glb');p,pv,_=next(triangles(d,b));_,order=cKDTree(pv).query(v)
mapping=np.array([m['bones'].index(d['nodes'][n]['name']) for n in d['skins'][0]['joints']]);groups=[0,1] if 'JOINTS_1' in p['attributes'] else [0]
js=mapping[np.concatenate([accessor(d,b,p['attributes']['JOINTS_'+str(i)]) for i in groups],1).astype(int)[order]];ws=np.concatenate([accessor(d,b,p['attributes']['WEIGHTS_'+str(i)]) for i in groups],1)[order]
e=np.unique(np.sort(np.concatenate([f[:,[0,1]],f[:,[1,2]],f[:,[2,0]]]),1),axis=0);length=np.linalg.norm(v[e[:,0]]-v[e[:,1]],axis=1);valid=length>np.ptp(v,axis=0).max()*.001;e=e[valid];length=length[valid];worst={}
for pose in meta['poses']:
 if not pose['frame']:continue
 pal=np.array(pose['palettes'][m['mi']],np.float32).reshape(-1,3,4);o=np.zeros_like(v)
 for k in range(js.shape[1]):
  mat=pal[js[:,k]];o+=(np.einsum('nij,nj->ni',mat[:,:,:3],v)+mat[:,:,3])*ws[:,k,None]
 ratio=np.linalg.norm(o[e[:,0]]-o[e[:,1]],axis=1)/length
 val=(round(float(ratio.max()),1),int((ratio>8).sum()),pose['frame'])
 if val>worst.get(pose['action'],(0,0,0)):worst[pose['action']]=val
print(key,worst,flush=True)
