"""Distributed Ratnik cloth rig, preserving mesh, UV, materials and bind pose.

Run after repair_skin.py. Existing cape weights seed a harmonic surface mask;
geometry only identifies body-side constraints, never reassigns an entire depth
slice. Three five-joint strips give the hem a delayed, independently bending
motion. The old joints and all non-cape animation channels are retained.
Idempotent: originals are saved to --backup before the first application.
"""
import argparse, copy, json, shutil
from pathlib import Path
import numpy as np
from scipy.sparse import coo_matrix, diags
from scipy.sparse.linalg import spsolve
from scipy.spatial.transform import Rotation
from inspect_geometry import read_glb, accessor, triangles
from upgrade_rigs import Writer, globals_of, add_channel

VERSION = 2

def smooth(t):
    t=np.clip(t,0,1)
    return t*t*(3-2*t)

def weights_of(doc,binary,prim,count):
    w=np.zeros((doc['accessors'][prim['attributes']['POSITION']]['count'],count))
    for group in (0,1):
        if 'JOINTS_'+str(group) not in prim['attributes']:continue
        j=accessor(doc,binary,prim['attributes']['JOINTS_'+str(group)]).astype(int)
        a=accessor(doc,binary,prim['attributes']['WEIGHTS_'+str(group)])
        np.add.at(w,(np.arange(len(w))[:,None],j),a)
    return w

def surface_mask(v,f,c,forward,origin):
    # UV duplicates must share exactly the same cloth/body transition.
    points,uid=np.unique(np.round(v,6),axis=0,return_inverse=True)
    uid=uid.reshape(-1);n=len(points);counts=np.bincount(uid)
    seed=np.bincount(uid,weights=c)/counts
    depth=-(points-origin)@forward
    # A cloth seed has to agree with the original rig, not just its position.
    positive=seed>.80
    negative=(seed<.025)&((depth<(.125-.045*points[:,1]))|(points[:,1]>.31))
    edges=np.concatenate((uid[f[:,[0,1]]],uid[f[:,[1,2]]],uid[f[:,[2,0]]]))
    edges=np.unique(np.sort(edges,axis=1),axis=0);edges=edges[edges[:,0]!=edges[:,1]]
    length=np.linalg.norm(points[edges[:,0]]-points[edges[:,1]],axis=1)
    a,b=edges.T;values=1/np.maximum(length,1e-5)
    adj=coo_matrix((np.r_[values,values],(np.r_[a,b],np.r_[b,a])),shape=(n,n)).tocsr()
    lap=diags(np.asarray(adj.sum(1)).ravel())-adj
    # Tiny data term resolves isolated components without inventing cloth there.
    known=positive|negative;unknown=np.flatnonzero(~known)
    out=np.zeros(n);out[positive]=1
    if len(unknown):
        lhs=lap[unknown][:,unknown]+diags(np.full(len(unknown),.001))
        rhs=-(lap[unknown]@out)+seed[unknown]*.001
        out[unknown]=spsolve(lhs.tocsc(),rhs)
    return smooth(np.clip(out,0,1))[uid],uid

def repair(path,backup_dir):
    current,_=read_glb(path)
    if current.get('asset',{}).get('extras',{}).get('sfery_cape_repair')==VERSION:
        return {'model':path.stem,'skipped':'already repaired'}
    backup_dir.mkdir(parents=True,exist_ok=True);source=backup_dir/path.name
    if not source.exists():shutil.copy2(path,source)
    elif path.read_bytes()!=source.read_bytes() and not current.get('asset',{}).get('extras',{}).get('sfery_cape_repair'):
        raise ValueError(f'{path}: changed since cape backup; choose another --backup')
    doc,binary=read_glb(source);old=copy.deepcopy(doc);writer=Writer(doc,binary)
    gs=globals_of(doc);skin=doc['skins'][0];old_count=len(skin['joints'])
    names={doc['nodes'][n]['name']:n for n in skin['joints']}
    chest=names['chest'];origin=gs[chest][:3,3]
    forward=gs[names['head']][:3,3]-gs[names['hips']][:3,3]
    forward[1]=0;forward/=np.linalg.norm(forward);side=np.cross(forward,[0,1,0])
    cape_slots=[skin['joints'].index(names[x]) for x in ('cape1','cape2')]
    records=[]
    # Global bind orientations are identity: child local rotations have a clear
    # outward axis. Original bones are never reparented or moved.
    for col,lateral in enumerate((-.16,0,.16)):
        parent=chest
        for row,y in enumerate((.25,.10,-.05,-.20,-.35)):
            pos=origin+side*lateral-forward*(.13+(.25-y)*.35);pos[1]=y
            parent_global=gs[parent] if row==0 else records[-1]['global']
            target=np.eye(4);target[:3,3]=pos;local=np.linalg.inv(parent_global)@target
            node=len(doc['nodes'])
            doc['nodes'].append({'name':f'cape_soft.{col}.{row}',
                                 'translation':local[:3,3].tolist(),
                                 'rotation':Rotation.from_matrix(local[:3,:3]).as_quat().tolist()})
            doc['nodes'][parent].setdefault('children',[]).append(node)
            skin['joints'].append(node)
            records.append({'node':node,'col':col,'row':row,'global':target});parent=node
    new_count=len(skin['joints']);stats=[]
    for prim,v,f in list(triangles(old,binary)):
        old_w=weights_of(old,binary,prim,old_count)
        c=old_w[:,cape_slots].sum(1)
        mask,uid=surface_mask(v,f,c,forward,origin)
        cloth=np.zeros((len(v),new_count))
        # Smooth bilinear interpolation over lateral strips and vertical levels.
        x=(v-origin)@side
        cx=np.clip((x+.16)/.16,0,2);cy=np.clip((.25-v[:,1])/.15,0,4)
        for rec in records:
            wx=smooth(1-np.abs(cx-rec['col']));wy=smooth(1-np.abs(cy-rec['row']))
            cloth[:,skin['joints'].index(rec['node'])]=wx*wy
        cloth/=np.maximum(cloth.sum(1,keepdims=True),1e-12)
        w=np.pad(old_w,((0,0),(0,new_count-old_count)))
        # Where cloth replaces the old cape, remove the contaminated arm/sword
        # shares too. The harmonic mask makes this a continuous attachment.
        w=w*(1-mask[:,None])+cloth*mask[:,None]
        counts=np.bincount(uid);sums=np.zeros((len(counts),new_count));np.add.at(sums,uid,w)
        w=(sums/counts[:,None])[uid]
        top=np.argsort(-w,axis=1)[:,:8];values=np.take_along_axis(w,top,axis=1)
        values/=np.maximum(values.sum(1,keepdims=True),1e-12)
        target=next(p for p in doc['meshes'][0]['primitives'] if p['attributes']['POSITION']==prim['attributes']['POSITION'])
        for group in (0,1):
            target['attributes']['JOINTS_'+str(group)]=writer.add(top[:,4*group:4*group+4],'VEC4',5123)
            target['attributes']['WEIGHTS_'+str(group)]=writer.add(values[:,4*group:4*group+4],'VEC4')
        stats.append({'cloth_vertices':int((mask>.99).sum()),'attachment_vertices':int(((mask>.001)&(mask<.99)).sum()),'weight_error':float(np.abs(values.sum(1)-1).max())})
    new_gs=globals_of(doc)
    rest_error=max(float(np.abs(new_gs[i]-g).max()) for i,g in enumerate(gs))
    assert rest_error<2e-5
    inverse=np.array([np.linalg.inv(new_gs[n]).T.reshape(16) for n in skin['joints']])
    skin['inverseBindMatrices']=writer.add(inverse,'MAT4')
    for animation in doc.get('animations',[]):
        t0=min(float(accessor(old,binary,s['input'])[0,0]) for s in animation['samplers'])
        end=max(float(accessor(old,binary,s['input'])[-1,0]) for s in animation['samplers'])
        times=np.linspace(t0,end,121);p=(times-t0)/max(end-t0,1e-8)
        input_index=writer.add(times[:,None],'SCALAR');idle=animation.get('name')=='idle'
        scale={'attack':1,'hit':.65,'roar':.70,'stance':.45}.get(animation.get('name'),.5)
        for rec in records:
            row=rec['row'];col=rec['col'];delay=.055*row+.015*abs(col-1)
            if idle:
                phase=2*np.pi*p-.55*row+.28*(col-1)
                bend=(.32+.16*row)*(1+np.sin(phase))
                sway=.30*np.sin(phase-.6)
            else:
                q=np.clip((p-delay)/(1-delay),0,1)
                envelope=np.sin(np.pi*q)**2
                bend=scale*(.45+.65*row)*envelope
                sway=scale*.75*np.sin(2*np.pi*q+.35*(col-1))*envelope
            bend*=2.5 if idle else 2.0
            sway*=2.0
            if row==0:bend*=.18;sway*=.18
            # Outward-only bend: the cloth never swings through the back because
            # of its own secondary motion. Small lateral sway keeps the outline.
            angles=np.deg2rad(bend)[:,None]*(-side)+np.deg2rad(sway)[:,None]*forward
            delta=Rotation.from_rotvec(angles).as_quat()
            rest=np.array(doc['nodes'][rec['node']]['rotation'])
            from upgrade_rigs import qmul
            values=qmul(np.tile(rest,(len(times),1)),delta)
            add_channel(writer,animation,rec['node'],'rotation',input_index,values)
    extras=doc.setdefault('asset',{}).setdefault('extras',{})
    extras['sfery_cape_repair']=VERSION
    writer.save(path)
    return {'model':path.stem,'added_bones':len(records),'rest_error':rest_error,'primitives':stats}

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--backup',default='tools/_tmp/capes027-base');args=parser.parse_args()
    reports=[repair(p,Path(args.backup)) for p in sorted(Path('assets/creatures_hd').glob('ratnik_*.glb'))]
    Path('/tmp/sfery-cape027-report.json').write_text(json.dumps(reports,indent=2))
    print(json.dumps(reports,indent=2))
