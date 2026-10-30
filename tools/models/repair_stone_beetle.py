"""Reconstruct the stone beetle's exterior as one closed, textured skin.

Python environment: /home/loq/ai/Hunyuan3D-2/.venv/bin/python (trimesh,
skimage, scipy). Uses Blender CLI only for surface simplification. Source is
backed up before editing. No interior proxy primitives survive this repair.
"""
from pathlib import Path
import json
import subprocess
import numpy as np
from scipy import ndimage
from scipy.spatial import cKDTree
from skimage.measure import marching_cubes
import trimesh

from inspect_geometry import read_glb, accessor, triangles
from upgrade_rigs import Writer, globals_of

ROOT = Path(__file__).resolve().parents[2]
TARGET = ROOT/'assets/creatures_hd/rogozhuk_stone.glb'
BACKUP = ROOT/'tools/_tmp/stone028-base/rogozhuk_stone.glb'
WORK = Path('/tmp/stone028-repair')


def closest(points, vertices, faces, tree):
    """Actual closest point among nearby source triangles, not nearest vertex."""
    face_ids = tree.query(points, k=24)[1]
    tri = vertices[faces[face_ids]]
    p = np.broadcast_to(points[:, None, :], tri.shape[:2]+(3,))
    near = trimesh.triangles.closest_point(tri.reshape(-1, 3, 3), p.reshape(-1, 3)).reshape(p.shape)
    best = np.linalg.norm(near-p, axis=2).argmin(1)
    ids = face_ids[np.arange(len(points)), best]
    q = near[np.arange(len(points)), best]
    bary = trimesh.triangles.points_to_barycentric(vertices[faces[ids]], q)
    return ids, bary, q


def repair():
    WORK.mkdir(exist_ok=True)
    BACKUP.parent.mkdir(parents=True, exist_ok=True)
    if not BACKUP.exists(): BACKUP.write_bytes(TARGET.read_bytes())
    doc, binary = read_glb(BACKUP)
    prim, old_v, old_f = next(triangles(doc, binary))
    source = trimesh.Trimesh(old_v, old_f, process=True)
    pitch = .0035
    print('Rasterizing original exterior only', flush=True)
    origin=old_v.min(0)-12*pitch
    shape=np.ceil(np.ptp(old_v,axis=0)/pitch).astype(int)+25
    surface=np.zeros(shape,dtype=bool)
    tri=old_v[old_f]
    edge_lengths=np.stack([np.linalg.norm(tri[:,i]-tri[:,(i+1)%3],axis=1) for i in range(3)],axis=1)
    density=np.maximum(1,np.ceil(edge_lengths.max(1)/(pitch*.6)).astype(int))
    # Adaptive barycentric rasterization avoids recursively materializing tens
    # of millions of child triangles just to mark occupied surface voxels.
    for n in np.unique(density):
        bary=np.array([[i/n,j/n,1-(i+j)/n] for i in range(n+1) for j in range(n+1-i)])
        ids=np.flatnonzero(density==n)
        for start in range(0,len(ids),256):
            samples=np.einsum('ki,nij->nkj',bary,tri[ids[start:start+256]]).reshape(-1,3)
            grid=np.rint((samples-origin)/pitch).astype(int)
            surface[tuple(grid.T)]=True
    print('Surface grid',surface.shape,int(surface.sum()),flush=True)
    # A morphological wrap fills real tunnels between generated armour plates.
    # Erosion restores the exterior after sealing; it does not insert a sphere.
    radius = .0245/pitch
    surface_distance=ndimage.distance_transform_edt(~surface)
    expanded = surface_distance <= radius
    solid = ndimage.binary_fill_holes(expanded)
    repaired = ndimage.distance_transform_edt(solid) > radius
    # The plate joins at the crown contain a wider tunnel. Seal that part of
    # the carapace with a larger local wrap, without joining or thickening legs.
    crown_radius=.0385/pitch
    crown=ndimage.distance_transform_edt(ndimage.binary_fill_holes(surface_distance<=crown_radius))>crown_radius
    rest=globals_of(doc);named={n.get('name'):i for i,n in enumerate(doc['nodes'])}
    center=rest[named['chest']][:3,3]
    forward=rest[named['head']][:3,3]-center;forward[1]=0;forward/=np.linalg.norm(forward)
    xx=origin[0]+np.arange(shape[0])[:,None,None]*pitch
    yy=origin[1]+np.arange(shape[1])[None,:,None]*pitch
    zz=origin[2]+np.arange(shape[2])[None,None,:]*pitch
    longitudinal=(xx-center[0])*forward[0]+(zz-center[2])*forward[2]
    upper=(yy>.045)&(longitudinal<.26)
    repaired |= crown&upper
    # The largest crown passage is wider than the local closing diameter.
    # Reconstruct its solid carapace cross-section between the existing front
    # and rear walls. This fills the plate junction from actual outer contours;
    # the horn (forward of the .17 cut) and all lower limbs remain untouched.
    carapace=(yy>.045)&(longitudinal<.17)
    for axis in [2,0,2]:
        section=repaired&carapace
        reverse=np.flip(np.maximum.accumulate(np.flip(section,axis=axis),axis=axis),axis=axis)
        repaired |= np.maximum.accumulate(section,axis=axis)&reverse&carapace
    del crown,surface_distance,solid,expanded
    # A continuous subvoxel field avoids edge-only contacts between diagonal
    # occupied voxels, which otherwise create four-face nonmanifold edges.
    field=ndimage.gaussian_filter(repaired.astype(np.float32), .65)
    vertices, faces, _, _ = marching_cubes(field, .501, spacing=(pitch,)*3, allow_degenerate=False)
    vertices += origin
    np.savez(WORK/'wrapped.npz', v=vertices, f=faces)
    print('Wrapped exterior', len(vertices), len(faces), flush=True)
    helper = WORK/'simplify.py'
    helper.write_text('''import bpy,numpy as np,os
bpy.ops.wm.read_factory_settings(use_empty=True)
d=np.load('/tmp/stone028-repair/wrapped.npz')
m=bpy.data.meshes.new('joined_exterior');m.from_pydata(d['v'].tolist(),[],d['f'].tolist());m.update()
o=bpy.data.objects.new('joined_exterior',m);bpy.context.collection.objects.link(o);bpy.context.view_layer.objects.active=o;o.select_set(True)
s=o.modifiers.new('subvoxel_surface','SMOOTH');s.factor=.55;s.iterations=3;bpy.ops.object.modifier_apply(modifier=s.name)
s=o.modifiers.new('surface_density','DECIMATE');s.ratio=min(1,180000/len(m.polygons));bpy.ops.object.modifier_apply(modifier=s.name)
m.calc_loop_triangles();v=np.array([x.co[:] for x in m.vertices]);f=np.array([x.vertices[:] for x in m.loop_triangles]);n=np.array([x.normal[:] for x in m.vertices]);np.savez('/tmp/stone028-repair/exterior.npz',v=v,f=f,n=n)
os._exit(0)
''')
    subprocess.run(['blender','-b','-t','4','-P',str(helper)], check=True)
    data=np.load(WORK/'exterior.npz');v=data['v'];f=data['f'];normals=data['n']
    rebuilt=trimesh.Trimesh(v,f,process=True)
    assert rebuilt.is_watertight, 'The reconstructed exterior must be watertight'
    if rebuilt.volume < 0:
        f=f[:,::-1].copy();normals=-normals
        rebuilt=trimesh.Trimesh(v,f,process=True)
    print('Closed mesh', len(v), len(f), 'Euler', rebuilt.euler_number, flush=True)
    uv=accessor(doc,binary,prim['attributes']['TEXCOORD_0'])
    skin=doc['skins'][0];weights=np.zeros((len(old_v),len(skin['joints'])))
    for k in [0,1]:
        js=accessor(doc,binary,prim['attributes'][f'JOINTS_{k}']).astype(int)
        ws=accessor(doc,binary,prim['attributes'][f'WEIGHTS_{k}'])
        np.add.at(weights,(np.arange(len(old_v))[:,None],js),ws)
    tree=cKDTree(old_v[old_f].mean(1));new_w=[];distances=[]
    for start in range(0,len(v),4000):
        ids,bary,q=closest(v[start:start+4000],old_v,old_f,tree)
        new_w.append(np.einsum('ni,nij->nj',bary,weights[old_f[ids]]))
        distances.extend(np.linalg.norm(q-v[start:start+4000],axis=1))
    new_w=np.concatenate(new_w)
    # New exterior bridges need a continuous attachment across head/chest/shell,
    # rather than copying a hard nearest-surface discontinuity at the new seam.
    edge=np.unique(np.sort(np.concatenate([f[:,[0,1]],f[:,[1,2]],f[:,[2,0]]]),axis=1),axis=0)
    for _ in range(10):
        sums=new_w.copy();count=np.ones(len(v))
        np.add.at(sums,edge[:,0],new_w[edge[:,1]]);np.add.at(sums,edge[:,1],new_w[edge[:,0]])
        np.add.at(count,edge[:,0],1);np.add.at(count,edge[:,1],1)
        new_w=.5*new_w+.5*sums/count[:,None]
    new_w/=new_w.sum(1,keepdims=True)
    # Choose one source texture triangle for each tiny new face. Its three UVs
    # are interpolated together so no face traverses unrelated atlas islands.
    out_uv=[]
    for start in range(0,len(f),4000):
        faces_here=f[start:start+4000]
        ids,_,_=closest(v[faces_here].mean(1),old_v,old_f,tree)
        src=old_v[old_f[ids]]
        uv_tri=[]
        for corner in range(3):
            q=trimesh.triangles.closest_point(src,v[faces_here[:,corner]])
            bary=trimesh.triangles.points_to_barycentric(src,q)
            uv_tri.append(np.einsum('ni,nij->nj',bary,uv[old_f[ids]]))
        out_uv.append(np.stack(uv_tri,axis=1))
    out_uv=np.concatenate(out_uv).reshape(-1,2)
    indices=f.ravel();vv=v[indices];nn=normals[indices];ww=new_w[indices]
    top=np.argsort(-ww,axis=1)[:,:8];ws=np.take_along_axis(ww,top,axis=1);ws/=ws.sum(1,keepdims=True)
    writer=Writer(doc,binary)
    attrs={'POSITION':writer.add(vv,'VEC3'),'NORMAL':writer.add(nn,'VEC3'),'TEXCOORD_0':writer.add(out_uv,'VEC2')}
    for k in [0,1]:
        attrs[f'JOINTS_{k}']=writer.add(top[:,k*4:k*4+4],'VEC4',5123)
        attrs[f'WEIGHTS_{k}']=writer.add(ws[:,k*4:k*4+4],'VEC4')
    idx=writer.add(np.arange(len(vv))[:,None],'SCALAR',5125)
    doc['accessors'][attrs['POSITION']].update(min=vv.min(0).tolist(),max=vv.max(0).tolist())
    doc['meshes'][0]['primitives']=[{'attributes':attrs,'indices':idx,'material':prim.get('material',0)}]
    doc['asset'].setdefault('extras',{})['stone_exterior_repair']='0.2.8-manifold-wrap'
    writer.save(TARGET)
    report={'vertices':len(v),'triangles':len(f),'watertight':rebuilt.is_watertight,'euler':rebuilt.euler_number,'surface_distance_quantiles':np.quantile(distances,[.5,.95,.99,1]).tolist(),'removed_inner_primitives':2,'pitch':pitch,'closure_radius':radius*pitch}
    (WORK/'report.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2),flush=True)


if __name__=='__main__':repair()
