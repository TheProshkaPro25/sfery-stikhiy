"""Measure real skinned triangle distortion across captured action poses."""
import json,sys
from pathlib import Path
import numpy as np
root=Path(sys.argv[1] if len(sys.argv)>1 else 'tools/_tmp/deformation027')
report=[]
for folder in sorted(root.iterdir()):
 if not (folder/'poses.json').exists():continue
 doc=json.loads((folder/'poses.json').read_text());worst=[]
 for mesh in doc['meshes']:
  prefix=folder/mesh['prefix'];read=lambda name,dtype:np.fromfile(str(prefix)+'_'+name+'.bin',dtype)
  v=read('vertices',np.float32).reshape(-1,3);j=read('joints',np.int32).reshape(-1,mesh['stride']);w=read('weights',np.float32).reshape(j.shape);f=read('indices',np.int32).reshape(-1,3)
  edges=np.sort(np.concatenate([f[:,[0,1]],f[:,[1,2]],f[:,[2,0]]]),axis=1);edges=np.unique(edges,axis=0)
  lengths=np.linalg.norm(v[edges[:,0]]-v[edges[:,1]],axis=1);valid=lengths>np.ptp(v,axis=0).max()*.001
  edges=edges[valid];lengths=lengths[valid]
  for pose in doc['poses']:
   if pose['frame']==0:continue
   pal=np.asarray(pose['palettes'][mesh['mi']],np.float32).reshape(-1,3,4)
   deformed=np.zeros_like(v)
   for k in range(j.shape[1]):
    m=pal[j[:,k]];deformed+=(np.einsum('nij,nj->ni',m[:,:,:3],v)+m[:,:,3])*w[:,k,None]
   posed_lengths=np.linalg.norm(deformed[edges[:,0]]-deformed[edges[:,1]],axis=1)
   ratio=posed_lengths/lengths
   bad=np.flatnonzero(ratio>2.0)
   if len(bad):
    ei=int(np.argmax(ratio));a,b=edges[ei];weights={}
    for vi in [a,b]:
     for slot,weight in zip(j[vi],w[vi]):
      if weight>.05:weights[mesh['bones'][slot]]=round(float(weight),2)
    worst.append({'action':pose['action'],'frame':pose['frame'],'max':round(float(ratio[ei]),2),'p999':round(float(np.quantile(ratio,.999)),2),'extension_height':round(float((posed_lengths-lengths).max()/np.ptp(v[:,1])),4),'over2':len(bad),'over3':int((ratio>3).sum()),'bones':weights,'rest_mid':((v[a]+v[b])/2).tolist()})
 worst.sort(key=lambda x:x['max'],reverse=True)
 report.append({'id':doc['id'],'worst':worst[:8]})
 print(doc['id'],worst[:1],flush=True)
Path(str(root)+'-report.json').write_text(json.dumps(report,indent=2))
