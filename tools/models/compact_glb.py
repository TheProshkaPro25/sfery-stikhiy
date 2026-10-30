"""Remove unreferenced GLB buffers/accessors/materials; retain live data byte-for-byte."""
import copy,sys
from pathlib import Path
from inspect_geometry import read_glb
from upgrade_rigs import Writer

def compact(path):
 d,b=read_glb(path);d=copy.deepcopy(d)
 prims=[p for m in d.get('meshes',[]) for p in m['primitives']]
 def remap_list(key,used):
  old=d.get(key,[]);ids=sorted(set(used));mapping={i:n for n,i in enumerate(ids)};d[key]=[old[i] for i in ids];return mapping
 materials=remap_list('materials',[p['material'] for p in prims if 'material'in p])
 for p in prims:
  if 'material'in p:p['material']=materials[p['material']]
 texture_refs=[]
 def visit(value):
  if isinstance(value,dict):
   for k,v in value.items():
    if k.endswith('Texture') and isinstance(v,dict) and 'index'in v:texture_refs.append(v)
    else:visit(v)
  elif isinstance(value,list):
   for v in value:visit(v)
 visit(d.get('materials',[]));tm=remap_list('textures',[r['index'] for r in texture_refs])
 for r in texture_refs:r['index']=tm[r['index']]
 image_refs=[]
 for t in d.get('textures',[]):
  if 'source'in t:image_refs.append(t)
  for ex in t.get('extensions',{}).values():
   if 'source'in ex:image_refs.append(ex)
 im=remap_list('images',[r['source'] for r in image_refs])
 for r in image_refs:r['source']=im[r['source']]
 refs=[]
 for p in prims:
  for name in p['attributes']:refs.append((p['attributes'],name))
  if 'indices'in p:refs.append((p,'indices'))
  for target in p.get('targets',[]):
   for name in target:refs.append((target,name))
 for s in d.get('skins',[]):
  if 'inverseBindMatrices'in s:refs.append((s,'inverseBindMatrices'))
 for a in d.get('animations',[]):
  for s in a['samplers']:refs.extend([(s,'input'),(s,'output')])
 am=remap_list('accessors',[r[k] for r,k in refs])
 for r,k in refs:r[k]=am[r[k]]
 views=[]
 for a in d['accessors']:
  if 'bufferView'in a:views.append(a)
  if 'sparse'in a:views.extend([a['sparse']['indices'],a['sparse']['values']])
 for im in d.get('images',[]):
  if 'bufferView'in im:views.append(im)
 vm=remap_list('bufferViews',[r['bufferView'] for r in views])
 for r in views:r['bufferView']=vm[r['bufferView']]
 packed=bytearray()
 for view in d['bufferViews']:
  assert view.get('buffer',0)==0
  packed.extend(b'\0'*((-len(packed))%4));start=len(packed);old=view.get('byteOffset',0)
  packed.extend(b[old:old+view['byteLength']]);view['byteOffset']=start;view['buffer']=0
 d['buffers']=[{'byteLength':len(packed)}]
 Writer(d,packed).save(path)
 print(path.name,'compacted',len(b),'->',len(packed),flush=True)
if __name__=='__main__':
 for arg in sys.argv[1:]:compact(Path(arg))
