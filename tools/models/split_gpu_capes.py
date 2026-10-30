"""Separate the already-rigged Ratnik cape without changing its surface.

Only the fully cloth-weighted region is simulated. The mixed upper attachment
stays native with all eight influences; the new cape has four normalized
influences and pinned shared boundary vertices. All original triangles, UVs,
materials, skeleton nodes, bind poses and animations survive.
"""
import argparse,copy,json,shutil
from pathlib import Path
import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import dijkstra
from inspect_geometry import read_glb,accessor
from upgrade_rigs import Writer
from repair_capes import weights_of,smooth
from compact_glb import compact

root=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser();parser.add_argument('--output',default='assets/creatures_hd');args=parser.parse_args()
backup=root/'tools/_tmp/gpucloth028-base';backup.mkdir(parents=True,exist_ok=True);out=root/args.output;out.mkdir(parents=True,exist_ok=True);reports=[]
for path in sorted((root/'assets/creatures_hd').glob('ratnik_*.glb')):
 source=backup/path.name
 if not source.exists():shutil.copy2(path,source)
 d,b=read_glb(source);assert not d['asset']['extras'].get('sfery_gpu_cape'),'backup must precede splitting'
 assert len(d['meshes'])==1 and len(d['meshes'][0]['primitives'])==1
 p=d['meshes'][0]['primitives'][0];v=accessor(d,b,p['attributes']['POSITION']);f=accessor(d,b,p['indices']).reshape(-1,3);skin=d['skins'][0];names=[d['nodes'][n]['name'] for n in skin['joints']];w=weights_of(d,b,p,len(names));slots=[i for i,n in enumerate(names) if n.startswith('cape_soft.')];mask=w[:,slots].sum(1)
 selection=mask[f].min(1)>.99999
 ci=np.unique(f[selection]);bi=np.unique(f[~selection])
 # UV copies can use distinct vertex indices on either side of the split.
 # The pinned seam is geometric, not just an intersection of accessor IDs.
 _,all_uid=np.unique(np.round(v,6),axis=0,return_inverse=True)
 shared=np.intersect1d(all_uid[ci],all_uid[bi]);boundary=ci[np.isin(all_uid[ci],shared)]
 # Welded geodesic distance to the native/simulated seam gives a pinned rim
 # and smooth freedom, including around irregular shoulder attachments.
 points,uid=np.unique(np.round(v[ci],6),axis=0,return_inverse=True);local=np.full(len(v),-1);local[ci]=np.arange(len(ci));cf=local[f[selection]];edges=np.unique(np.sort(np.concatenate([uid[cf[:,[0,1]]],uid[cf[:,[1,2]]],uid[cf[:,[2,0]]]]),axis=1),axis=0);a,e=edges.T;length=np.linalg.norm(points[a]-points[e],axis=1);graph=coo_matrix((np.r_[length,length],(np.r_[a,e],np.r_[e,a])),shape=(len(points),len(points))).tocsr();seam=np.unique(uid[local[boundary]])
 distance=dijkstra(graph,directed=False,indices=seam,min_only=True);free=smooth((distance[uid]-.012)/.12)
 # The top of cape never detaches from the shoulders, even if the source has
 # an isolated pure-cloth component without a shared boundary.
 free*=smooth((.27-v[ci,1])/.25)
 top=np.argsort(-w,axis=1)[:,:4];values=np.take_along_axis(w,top,axis=1);loss=1-values.sum(1);assert loss[ci].max()<1.2e-5
 values/=values.sum(1,keepdims=True)
 writer=Writer(d,b)
 def part(indices,faces,cloth):
  remap=np.full(len(v),-1);remap[indices]=np.arange(len(indices));attrs={}
  for name,index in p['attributes'].items():
   if cloth and name in ['JOINTS_0','JOINTS_1','WEIGHTS_0','WEIGHTS_1']:continue
   data=accessor(d,b,index);a=d['accessors'][index];attrs[name]=writer.add(data[indices],a['type'],a['componentType'])
   if name=='POSITION':d['accessors'][attrs[name]].update(min=v[indices].min(0).tolist(),max=v[indices].max(0).tolist())
  colors=np.zeros((len(indices),4));colors[:,3]=1
  if cloth:
   colors[:,0]=free;attrs['JOINTS_0']=writer.add(top[indices],'VEC4',5123);attrs['WEIGHTS_0']=writer.add(values[indices],'VEC4')
  attrs['COLOR_0']=writer.add(colors,'VEC4')
  return {'attributes':attrs,'indices':writer.add(remap[faces].ravel()[:,None],'SCALAR',5125),'material':p.get('material',0)}
 body=part(bi,f[~selection],False);cape=part(ci,f[selection],True);d['meshes'][0]['primitives']=[body];d['meshes'].append({'name':'CapeGPU','primitives':[cape]})
 original_node=next(i for i,n in enumerate(d['nodes']) if n.get('mesh')==0);node=copy.deepcopy(d['nodes'][original_node]);node['mesh']=1;node['name']='CapeGPU';node.pop('children',None);new=len(d['nodes']);d['nodes'].append(node)
 parent=next((n for n in d['nodes'] if original_node in n.get('children',[])),None)
 if parent is not None:parent['children'].append(new)
 else:
  for scene in d['scenes']:
   if original_node in scene.get('nodes',[]):scene['nodes'].append(new)
 d['asset']['extras']['sfery_gpu_cape']=1;target=out/path.name;writer.save(target);compact(target)
 reports.append({'model':path.stem,'cloth_faces':int(selection.sum()),'cloth_particles':len(points),'free_vertices':int((free>.01).sum()),'seam_vertices':len(boundary),'max_omitted_weight':float(loss[ci].max()),'body_faces':int((~selection).sum())})
print(json.dumps(reports,indent=2));(root/'tools/_tmp/review028/cape-split.json').write_text(json.dumps(reports,indent=2))
