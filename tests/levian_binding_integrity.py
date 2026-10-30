"""Validate a separated Levian tail against its preserved pre-repair GLB.

Checks actual exterior connectivity, protected surfaces, clips and bind data.
Animated intersections are checked separately from exported Godot poses.
"""
import argparse
import sys
from pathlib import Path
import numpy as np
import trimesh
from scipy.spatial import cKDTree
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools/models'))
from inspect_geometry import read_glb,accessor,triangles
from upgrade_rigs import globals_of,qmul,qconj,qfraction

parser=argparse.ArgumentParser()
parser.add_argument('--models',type=Path,default=ROOT/'assets/creatures_hd')
parser.add_argument('--source',type=Path,default=ROOT/'tools/_tmp/repair029/base')
args=parser.parse_args()
for path in sorted(args.models.glob('levian_*.glb')):
    doc,data=read_glb(path);old,old_data=read_glb(args.source/path.name)
    assert doc['asset'].get('extras',{}).get('sfery_tail_separation')==2,path.name
    parts=list(triangles(doc,data));op,ov,of=next(triangles(old,old_data))
    vertices=parts[0][1];faces=np.concatenate([p[2] for p in parts])
    mesh=trimesh.Trimesh(vertices,faces,process=True)
    original=trimesh.Trimesh(ov,of,process=True)
    assert mesh.is_watertight and mesh.is_winding_consistent,(path.name,'exterior topology')
    assert mesh.area_faces.min()>0,(path.name,'zero area')
    components=lambda m:sorted([len(c) for c in trimesh.graph.connected_components(m.edges_unique,min_len=1)],reverse=True)
    groups,old_groups=components(mesh),components(original)
    assert len(groups)==len(old_groups) and groups[1:]==old_groups[1:],(path.name,'detached detail',groups,old_groups)
    used=np.unique(faces)
    protected=(ov[:,2]>.24)|(ov[:,1]>.1)
    tree=cKDTree(vertices[used]);distance,nearest=tree.query(ov[protected])
    assert distance.max()<.000002,(path.name,'head/forefoot surface changed',distance.max())
    uv=accessor(doc,data,parts[0][0]['attributes']['TEXCOORD_0'])
    old_uv=accessor(old,old_data,op['attributes']['TEXCOORD_0'])
    old_points=np.column_stack([ov,old_uv]);new_points=np.column_stack([vertices,uv])
    _,old_ids=np.unique(np.round(old_points,6),axis=0,return_inverse=True)
    distances,mapped=cKDTree(old_points).query(new_points)
    mapped_ids=old_ids[mapped];mapped_ids[distances>.000002]=-1
    new_faces=set(map(tuple,np.sort(mapped_ids[faces],axis=1)))
    protected_faces=of[protected[of].all(1)]
    assert all(tuple(key) in new_faces for key in np.sort(old_ids[protected_faces],axis=1)),(path.name,'protected triangles/UVs changed')
    # No different skeleton or retimed animation may be slipped into this mesh repair.
    assert doc['nodes']==old['nodes'],(path.name,'skeleton nodes changed')
    assert doc['skins'][0]['joints']==old['skins'][0]['joints']
    assert np.array_equal(accessor(doc,data,doc['skins'][0]['inverseBindMatrices']),accessor(old,old_data,old['skins'][0]['inverseBindMatrices']))
    assert len(doc['animations'])==len(old['animations'])
    for new_anim,old_anim in zip(doc['animations'],old['animations']):
        assert new_anim['channels']==old_anim['channels']
        for sampler_index,(new_sampler,old_sampler) in enumerate(zip(new_anim['samplers'],old_anim['samplers'])):
            for name in ['input','output']:
                values=accessor(doc,data,new_sampler[name]);original_values=accessor(old,old_data,old_sampler[name])
                if np.array_equal(values,original_values):continue
                # The separately validated front035 motion repair changes only
                # these explicit output rotations. Key times and all other
                # channels retain the original031 equality requirement.
                targets=[c['target'] for c in new_anim['channels'] if c['sampler']==sampler_index]
                assert name=='output' and len(targets)==1,(path.name,'animation changed')
                target=targets[0];bone=doc['nodes'][target['node']]['name'];extras=doc['asset'].get('extras',{})
                factor=None
                if path.stem in ('levian_light','levian_stone') and new_anim.get('name')=='hit' and bone=='wing.R' and extras.get('sfery_hit_wing_clearance')==1:factor=.5
                if path.stem=='levian_stone' and new_anim.get('name')=='stance' and bone=='neck2' and extras.get('sfery_stone_stance_clearance')==1:factor=.75
                assert factor is not None and target['path']=='rotation',(path.name,'unexpected animation exception')
                factors=factor
                if new_anim.get('name')=='stance':
                    times=accessor(old,old_data,old_sampler['input']).ravel();progress=(times-times[0])/(times[-1]-times[0]);fade=np.clip((progress-.85)/.15,0,1)
                    factors=factor+(1-factor)*fade*fade*(3-2*fade)
                first=original_values[0].astype(float);expected=qmul(first,qfraction(qmul(qconj(first),original_values),factors)).astype(np.float32)
                expected[0],expected[-1]=original_values[0],original_values[-1]
                assert np.array_equal(values,expected),(path.name,'motion exception differs from accepted formula')
    for primitive,v,f in parts:
        weights=np.concatenate([accessor(doc,data,primitive['attributes']['WEIGHTS_'+str(k)]) for k in [0,1]],axis=1)
        joints=np.concatenate([accessor(doc,data,primitive['attributes']['JOINTS_'+str(k)]) for k in [0,1]],axis=1)
        assert np.isfinite(v).all() and np.isfinite(weights).all()
        assert (weights>=0).all() and np.abs(weights.sum(1)-1).max()<.000002
        assert joints.max()<len(doc['skins'][0]['joints'])
    print(path.stem,'closed exterior; original connected details, protected surface, skeleton, bind matrices and protected clip channels retained',flush=True)
