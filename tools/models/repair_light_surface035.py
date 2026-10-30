"""Apply reviewed Light surface retopology and local clearance corrections.

Arguments: 035 motion candidate, output candidate. The adjacent JSON is a
versioned sculpt delta: it pins its source geometry, keeps the complete original
knee spur, and protects all 137 accepted030 rear cut triangles. It does not
install game assets. Validate topology, attachment and real Godot poses after use.
"""
from pathlib import Path
import hashlib,json,sys,numpy as np
sys.path.insert(0,'tools/models')
from inspect_geometry import read_glb,accessor,triangles
from repair_water_beetle import read_weights
from repair_beetles import store_weights
from upgrade_rigs import Writer
from compact_glb import compact
assert len(sys.argv)==3,'INPUT OUTPUT required'
patch=json.loads(Path(__file__).with_name('light_surface035.json').read_text());d,b=read_glb(sys.argv[1]);parts=list(triangles(d,b));p,v,f=parts[0];cap=parts[1][2];sha=lambda a:hashlib.sha256(np.asarray(a).tobytes()).hexdigest()
assert sha(v)==patch['source_position_sha256'],'unexpected source vertices'
assert sha(f)==patch['source_body_indices_sha256'],'unexpected source topology'
assert sha(cap)==patch['source_cap_indices_sha256'],'unexpected closure topology'
keep=np.ones(len(f),bool);keep[patch['remove_before_retopology']]=False;faces=np.concatenate([f[keep],np.asarray(patch['add_faces'],dtype=int),f[patch['restore_spur_faces']]])
positions=v.copy();normals=accessor(d,b,p['attributes']['NORMAL']).copy()
for edit in patch['position_edits']:
 i=edit['vertex'];assert np.array_equal(positions[i],np.asarray(edit['before'],dtype=np.float32));positions[i]=edit['after']
for edit in patch['normal_edits']:normals[edit['vertex']]=edit['after']
protected=np.unique(cap[patch['protected_030_cap_indices']]);assert np.array_equal(positions[protected],v[protected]),'accepted030 rear cut moved'
weights=read_weights(d,b,p,len(d['skins'][0]['joints'])) if patch.get('skin_edits') else None
writer=Writer(d,b);pi=writer.add(positions,'VEC3');ni=writer.add(normals,'VEC3');p['indices']=writer.add(faces.ravel()[:,None],'SCALAR',5125)
if patch.get('cap_remove_faces'):
 assert not (set(patch['cap_remove_faces'])&set(patch['protected_030_cap_indices'])),'accepted030 rear cut topology changed'
 keep_cap=np.ones(len(cap),bool);keep_cap[patch['cap_remove_faces']]=False
 cap_faces=np.concatenate([cap[keep_cap],np.asarray(patch['cap_add_faces'],dtype=int).reshape(-1,3)])
 parts[1][0]['indices']=writer.add(cap_faces.ravel()[:,None],'SCALAR',5125)
for i in [0,1]:parts[i][0]['attributes']['POSITION']=pi;parts[i][0]['attributes']['NORMAL']=ni
if patch.get('skin_edits'):
 w=weights
 for edit in patch['skin_edits']:w[edit['vertex']]=edit['after']
 for i in [0,1]:store_weights(writer,parts[i][0],w)
for node in d['nodes']:
 if 'mesh' in node:node.setdefault('extras',{})['sfery_stride_by_bone']={'thigh.R':.6}
d['asset'].setdefault('extras',{})['light_surface_repair035']=1
out=Path(sys.argv[2]);out.parent.mkdir(parents=True,exist_ok=True);writer.save(out);compact(out)
