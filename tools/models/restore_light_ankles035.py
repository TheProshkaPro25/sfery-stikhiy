"""Restore real Light middle ankles removed by the historical paddle cut.

Python with numpy/scipy/Pillow. Arguments: socket_candidate pre029_source output.
Retains unchanged closure components and all previously retained source faces.
"""
from pathlib import Path
import sys,numpy as np
from scipy.spatial import cKDTree
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
sys.path.insert(0,'tools/models')
from inspect_geometry import read_glb,accessor,triangles
from upgrade_rigs import Writer,globals_of
from repair_water_beetle import cap_mesh,read_weights
from repair_beetles import store_weights
from compact_glb import compact
assert len(sys.argv)==4,'SOCKET_CANDIDATE PRE029_SOURCE OUTPUT required';src=sys.argv[1];d,b=read_glb(src);parts=list(triangles(d,b));p,cv,cf=parts[0];cw=read_weights(d,b,p,len(d['skins'][0]['joints']))
o,ob=read_glb(sys.argv[2]);op,v,f=next(triangles(o,ob));n=accessor(o,ob,op['attributes']['NORMAL']);uv=accessor(o,ob,op['attributes']['TEXCOORD_0']);w=read_weights(o,ob,op,len(d['skins'][0]['joints']));names=[d['nodes'][i]['name'] for i in d['skins'][0]['joints']]
def keys(v,f):
 q=np.round(v*1e6).astype(np.int64);return [tuple(sorted(tuple(q[i]) for i in tri)) for tri in f]
assert [o['nodes'][i]['name'] for i in o['skins'][0]['joints']]==names,'source skin slot order changed'
old=set(keys(cv,cf));keep=np.array([k in old for k in keys(v,f)]);assert int(keep.sum())==len(cf),'accepted exterior is not a subset of this source';middle=[i for i,s in enumerate(names) if s in ['thigh.L','shin.L','foot.L','thigh.R','shin.R','foot.R']];mass=w[:,middle].sum(1);gs=globals_of(d);node={n.get('name'):i for i,n in enumerate(d['nodes'])};center=gs[node['chest']][:3,3];fw=gs[node['head']][:3,3]-center;fw[1]=0;fw/=np.linalg.norm(fw);long=(v-center)@fw
restore=(mass>.65)&(v[:,1]<-.20)&(long>-.30);add=restore[f].all(1)&~keep;keep|=add;print('restored',add.sum(),flush=True)
# Existing repaired weights retained exactly wherever geometry existed.
dist,ix=cKDTree(cv).query(v);matched=dist<1e-6;w[matched]=cw[ix[matched]]
# Restored ankle surface must follow the genuine middle-leg chain only.
for side in ['L','R']:
 chain=[names.index(s+'.'+side) for s in ['thigh','shin','foot']];use=(~matched)&(w[:,chain].sum(1)>.5);ww=w[use][:,chain];ww/=ww.sum(1,keepdims=True);w[use]=0;w[np.ix_(use,chain)]=ww
base=f[keep]
# Keep every old closure component whose boundary remains unchanged. This retains
# the accepted rear plate cut while replacing only damaged ankle closures.
lookup={tuple(q):i for i,q in enumerate(np.round(v,6))};oldcap=parts[1][2];mapped=np.array([[lookup[tuple(np.round(cv[i],6))] for i in tri] for tri in oldcap]);_,uid=np.unique(np.round(v,6),axis=0,return_inverse=True)
edge=np.concatenate([uid[base[:,[0,1]]],uid[base[:,[1,2]]],uid[base[:,[2,0]]]]);key=np.sort(edge,axis=1);uniq,cnt=np.unique(key,axis=0,return_counts=True);bound={tuple(e) for e in uniq[cnt==1]}
# Components share vertices, so a contiguous folded cap is replaced as a unit.
inc=coo_matrix((np.ones(mapped.size),(np.repeat(np.arange(len(mapped)),3),uid[mapped].ravel())),shape=(len(mapped),uid.max()+1)).tocsr();_,labels=connected_components(inc@inc.T,directed=False)
retain=[]
for label in np.unique(labels):
 group=mapped[labels==label];edges=np.sort(np.concatenate([uid[group[:,[0,1]]],uid[group[:,[1,2]]],uid[group[:,[2,0]]]]),axis=1);e,c=np.unique(edges,axis=0,return_counts=True)
 if all(tuple(x) in bound for x in e[c==1]):retain.extend(group)
retained=np.asarray(retain).reshape(-1,3);combined=np.concatenate([base,retained]);vv,nn,uu,ww,closed,loops=cap_mesh(v,n,uv,w,combined);caps=closed[len(base):];print('closed',len(caps),'retained old',len(retained),'loops',loops,flush=True)
writer=Writer(d,b);attrs={'POSITION':writer.add(vv,'VEC3'),'NORMAL':writer.add(nn,'VEC3'),'TEXCOORD_0':writer.add(uu,'VEC2')};outputs=[]
for faces,mat in [(base,p['material']),(caps,parts[1][0]['material'])]:
 out={'attributes':dict(attrs),'indices':writer.add(faces.ravel()[:,None],'SCALAR',5125),'material':mat};store_weights(writer,out,ww);outputs.append(out)
d['meshes'][0]['primitives']=outputs+[x[0] for x in parts[2:]];d['asset']['extras']['light_original_feet_restored']=1;dest=Path(sys.argv[3]);dest.parent.mkdir(parents=True,exist_ok=True);writer.save(dest);compact(dest)
