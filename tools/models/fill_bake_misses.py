"""Fill uncovered atlas texels by nearest source-surface colour projection.

Normal-ray bakes cannot hit the source where a repaired tunnel had no surface.
Use actual 3D texel positions and nearest source triangles only for those misses;
keep successful Cycles texels. Dilate the result for mip filtering.
"""
import io,json,sys
from pathlib import Path
import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.spatial import cKDTree
from inspect_geometry import read_glb,accessor,triangles
from repair_stone_beetle import closest

source,prefix=map(Path,sys.argv[1:3]);d,b=read_glb(source);p,v,f=next(triangles(d,b));uv=accessor(d,b,p['attributes']['TEXCOORD_0'])
t=d['materials'][p['material']]['pbrMetallicRoughness']['baseColorTexture']['index'];im=d['images'][d['textures'][t]['source']];bv=d['bufferViews'][im['bufferView']]
texture=np.asarray(Image.open(io.BytesIO(b[bv.get('byteOffset',0):bv.get('byteOffset',0)+bv['byteLength']])).convert('RGB'),float)/255
atlas=np.array(Image.open(str(prefix)+'.png').convert('RGBA'));h,w=atlas.shape[:2]
loops=np.array(json.loads(Path(str(prefix)+'-loops.json').read_text())).reshape(-1,3,5)
position=np.zeros((h,w,3),np.float32);covered=np.zeros((h,w),bool)
for tri in loops:
 q=tri[:,3:]*[w,-h]+[0,h];lo=np.maximum(np.floor(q.min(0)).astype(int),0);hi=np.minimum(np.ceil(q.max(0)).astype(int),[w-1,h-1])
 xx,yy=np.meshgrid(np.arange(lo[0],hi[0]+1),np.arange(lo[1],hi[1]+1));px=np.stack([xx+.5,yy+.5],axis=-1)
 a=q[1]-q[0];c=q[2]-q[0];den=a[0]*c[1]-a[1]*c[0]
 if abs(den)<1e-12:continue
 delta=px-q[0];bb=(delta[:,:,0]*c[1]-delta[:,:,1]*c[0])/den;cc=(a[0]*delta[:,:,1]-a[1]*delta[:,:,0])/den;aa=1-bb-cc;inside=(aa>=-1e-7)&(bb>=-1e-7)&(cc>=-1e-7)
 y=yy[inside];x=xx[inside];position[y,x]=aa[inside,None]*tri[0,:3]+bb[inside,None]*tri[1,:3]+cc[inside,None]*tri[2,:3];covered[y,x]=True
miss=covered&(atlas[:,:,3]<250);ys,xs=np.where(miss);tree=cKDTree(v[f].mean(1));dist=[]
for start in range(0,len(ys),3000):
 y,x=ys[start:start+3000],xs[start:start+3000];points=position[y,x];ids,bary,q=closest(points,v,f,tree);sample_uv=np.einsum('ni,nij->nj',bary,uv[f[ids]]);dist.extend(np.linalg.norm(points-q,axis=1))
 # glTF UVs use a top-left image origin (unlike Blender UVs).
 colour=np.stack([ndimage.map_coordinates(texture[:,:,channel],np.array([sample_uv[:,1]*texture.shape[0]-.5,sample_uv[:,0]*texture.shape[1]-.5]),order=1,mode='nearest') for channel in range(3)],axis=1)
 alpha=atlas[y,x,3:4]/255.;atlas[y,x,:3]=np.clip(atlas[y,x,:3]*alpha+colour*255*(1-alpha),0,255).astype(np.uint8);atlas[y,x,3]=255
# Extend all islands into unused atlas space; sampling outside never sees black.
_,nearest=ndimage.distance_transform_edt(~covered,return_indices=True);atlas[~covered]=atlas[tuple(nearest[:,~covered])];atlas[:,:,3]=255
Image.fromarray(atlas).save(str(prefix)+'.png')
report={'covered_texels':int(covered.sum()),'ray_misses_filled':len(ys),'nearest_source_distance_quantiles':np.quantile(dist,[.5,.95,1]).tolist() if dist else []}
Path(str(prefix)+'-coverage.json').write_text(json.dumps(report,indent=2));print(json.dumps(report),flush=True)
