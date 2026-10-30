"""Blender motion audit confined to Stone's measured coil sliver neighborhood.
Usage: -- EXPORT_ROOT OUTPUT_DIR. Run full lower-region audit independently.
"""
import json,sys,os,numpy as np
from pathlib import Path
from mathutils.bvhtree import BVHTree
root=Path(sys.argv[sys.argv.index('--')+1]);output=Path(sys.argv[sys.argv.index('--')+2]);output.mkdir(exist_ok=True,parents=True);report=[]
for folder in sorted(root.iterdir()):
 if not (folder/'poses.json').exists():continue
 d=json.loads((folder/'poses.json').read_text());vs=[];js=[];ws=[];fs=[];meshes=[];offset=0
 for mesh in d['meshes']:
  prefix=folder/mesh['prefix'];read=lambda n,t:np.fromfile(str(prefix)+'_'+n+'.bin',t);v=read('vertices',np.float32).reshape(-1,3);j=read('joints',np.int32).reshape(-1,mesh['stride']);w=read('weights',np.float32).reshape(j.shape);f=read('indices',np.int32).reshape(-1,3);sel=(np.linalg.norm(v-np.array([.2228,-.2677,-.1385]),axis=1)[f].max(1)<.025);used,remap=np.unique(f[sel],return_inverse=True);vs.append(v[used]);js.append(j[used]);ws.append(w[used]);fs.append(remap.reshape(-1,3)+offset);meshes.append(mesh);offset+=len(used)
 rest=np.concatenate(vs);f=np.concatenate(fs);_,uid=np.unique(np.round(rest,6),axis=0,return_inverse=True);rows=[];worst=-1;bad=set()
 for pose in d['poses']:
  posed=[]
  for v,j,w,mesh in zip(vs,js,ws,meshes):
   palette=np.asarray(pose['palettes'][mesh['mi']]).reshape(-1,3,4);pos=np.zeros_like(v)
   for k in range(j.shape[1]):
    m=palette[j[:,k]];pos+=(np.einsum('nij,nj->ni',m[:,:,:3],v)+m[:,:,3])*w[:,k,None]
   posed.append(pos)
  posed=np.concatenate(posed);tree=BVHTree.FromPolygons(posed.tolist(),f.tolist(),all_triangles=True,epsilon=0);pairs=np.array([(a,b) for a,b in tree.overlap(tree) if a<b],dtype=int).reshape(-1,2)
  if len(pairs):pairs=pairs[~(uid[f[pairs[:,0]]][:,:,None]==uid[f[pairs[:,1]]][:,None,:]).any((1,2))]
  row={'action':pose['action'],'frame':pose['frame'],'pairs':len(pairs)};rows.append(row)
  bad.update(f[pairs].ravel().tolist())
  if len(pairs)>worst:
   worst=len(pairs);worst_row=row;np.savez(output/(d['id']+'-worst.npz'),rest=rest,posed=posed,f=f,pairs=pairs,j=np.concatenate(js),w=np.concatenate(ws),bones=meshes[0]['bones'])
 np.savez(output/(d['id']+'-affected.npz'),rest=rest,affected=np.array(sorted(bad)),f=f,j=np.concatenate(js),w=np.concatenate(ws),bones=meshes[0]['bones'])
 report.append({'id':d['id'],'worst':worst_row,'poses':rows});print(d['id'],worst_row,flush=True)
(output/'report.json').write_text(json.dumps(report,indent=2));sys.stdout.flush();os._exit(0)
