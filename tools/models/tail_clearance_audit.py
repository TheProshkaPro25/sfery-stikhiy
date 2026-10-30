"""Measure the repaired cap-to-torso gap in actual imported idle poses.

Input: a deformation_audit directory containing all six repaired Levians.
This is a local regression, not a claim about all possible self-intersections.
"""
import json,sys
from pathlib import Path
import numpy as np
from scipy.spatial import cKDTree

root=Path(sys.argv[1]);reports=[]
for folder in sorted(root.iterdir()):
    if not (folder/'poses.json').exists():continue
    doc=json.loads((folder/'poses.json').read_text());parts=[]
    for mesh in doc['meshes']:
        prefix=folder/mesh['prefix']
        read=lambda name,dtype:np.fromfile(str(prefix)+'_'+name+'.bin',dtype)
        v=read('vertices',np.float32).reshape(-1,3);j=read('joints',np.int32).reshape(-1,mesh['stride']);w=read('weights',np.float32).reshape(j.shape)
        parts.append((v,j,w,mesh['mi']))
    assert len(parts)==2,(doc['id'],'missing sealed cut surface')
    body=parts[0][0];cap=parts[1][0]
    tip=(cap[:,0]<-.17)&(cap[:,2]>.02)&(cap[:,1]<-.16)
    torso=(body[:,0]>-.07)&(body[:,2]>.08)&(body[:,1]<.1)
    assert tip.any() and torso.any(),doc['id']
    gaps=[]
    for pose in doc['poses']:
        if pose['action']!='idle':continue
        points=[]
        for (v,j,w,mi),selected in zip(parts,[torso,tip]):
            v=v[selected];j=j[selected];w=w[selected];palette=np.asarray(pose['palettes'][mi]).reshape(-1,3,4);pos=np.zeros_like(v)
            for k in range(j.shape[1]):
                m=palette[j[:,k]];pos+=(np.einsum('nij,nj->ni',m[:,:,:3],v)+m[:,:,3])*w[:,k,None]
            points.append(pos)
        gap=float(cKDTree(points[0]).query(points[1])[0].min());gaps.append(gap)
        assert gap>.02,(doc['id'],pose['frame'],'tail cap approached torso',gap)
    reports.append(dict(id=doc['id'],idle_samples=len(gaps),min_gap=min(gaps)))
    print(reports[-1],flush=True)
Path(str(root)+'-clearance.json').write_text(json.dumps(reports,indent=2))
