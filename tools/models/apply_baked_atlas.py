"""Apply Blender UV-loop atlas to a repaired GLB without re-exporting its rig."""
import sys,json,numpy as np
from pathlib import Path
from scipy.spatial import cKDTree
from inspect_geometry import read_glb,accessor
from upgrade_rigs import Writer
path=Path(sys.argv[1]);prefix=Path(sys.argv[2]);doc,binary=read_glb(path)
assert len(doc['meshes'])==1 and len(doc['meshes'][0]['primitives'])==1
p=doc['meshes'][0]['primitives'][0];v=accessor(doc,binary,p['attributes']['POSITION'])
loops=np.asarray(json.loads(Path(str(prefix)+'-loops.json').read_text()),np.float32)
# Blender stores UVs from bottom-left; glTF and the saved PNG use top-left.
loops[:,4]=1-loops[:,4]
distance,order=cKDTree(v).query(loops[:,:3]);assert distance.max()<1e-5,('coordinate mismatch',distance.max())
_,geom=np.unique(np.round(v,7),axis=0,return_inverse=True)
keys=np.column_stack([geom[order],np.round(loops[:,3:],7)])
_,first,indices=np.unique(keys,axis=0,return_index=True,return_inverse=True)
writer=Writer(doc,binary);n=len(v)
for name,index in list(p['attributes'].items()):
 if name=='TEXCOORD_0':continue
 data=accessor(doc,binary,index)
 assert len(data)==n
 component=doc['accessors'][index]['componentType'];kind=doc['accessors'][index]['type']
 p['attributes'][name]=writer.add(data[order[first]],kind,component)
 if name=='POSITION':
  doc['accessors'][p['attributes'][name]].update(min=data.min(0).tolist(),max=data.max(0).tolist())
p['attributes']['TEXCOORD_0']=writer.add(loops[first,3:],'VEC2')
p['indices']=writer.add(indices.astype(np.uint32)[:,None],'SCALAR',5125)
png=Path(str(prefix)+'.png').read_bytes();writer.binary.extend(b'\0'*((-len(writer.binary))%4));start=len(writer.binary);writer.binary.extend(png)
view=len(doc['bufferViews']);doc['bufferViews'].append({'buffer':0,'byteOffset':start,'byteLength':len(png)})
image=len(doc['images']);doc['images'].append({'name':path.stem+'_repaired_atlas','bufferView':view,'mimeType':'image/png'})
texture=len(doc['textures']);doc['textures'].append({'source':image,'sampler':0})
mat=doc['materials'][p['material']]
for key in ['normalTexture','occlusionTexture','emissiveTexture']:mat.pop(key,None)
mat['pbrMetallicRoughness']={'baseColorTexture':{'index':texture},'baseColorFactor':[1,1,1,1],'metallicFactor':0,'roughnessFactor':1}
doc['asset'].setdefault('extras',{})['sfery_baked_repair_atlas']=1
writer.save(path)
print('Applied atlas:',len(first),'render vertices;',len(indices)//3,'triangles; max mapping error',float(distance.max()),flush=True)
