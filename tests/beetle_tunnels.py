"""Probe the actual Stone crown passages that were clear in v0.2.7.

Watertightness alone cannot distinguish a solid shell from a closed tunnel.
These fixed side-to-side rays crossed the old armour without hitting it.
"""
from pathlib import Path
import sys,json,numpy as np
root=Path(__file__).resolve().parents[1];sys.path.insert(0,str(root/'tools/models'))
from inspect_geometry import read_glb,triangles

def intersections(v,f,origin,direction):
 tri=v[f].astype(float);e1=tri[:,1]-tri[:,0];e2=tri[:,2]-tri[:,0];h=np.cross(direction,e2);det=(e1*h).sum(1);valid=np.abs(det)>1e-10;inv=np.divide(1,det,out=np.zeros_like(det),where=valid);s=origin-tri[:,0];u=inv*(s*h).sum(1);q=np.cross(s,e1);t=inv*(q*e2).sum(1);a=inv*(q*direction).sum(1)
 return np.sort(t[valid&(u>=0)&(a>=0)&(u+a<=1)&(t>0)])
probes=json.loads((root/'tests/fixtures/stone028_tunnel_probes.json').read_text());d,b=read_glb(root/'assets/creatures_hd/rogozhuk_stone.glb');_,v,f=next(triangles(d,b))
reference=root/'tools/_tmp/stone028-base/rogozhuk_stone.glb';old=None
if reference.exists():
 od,ob=read_glb(reference);_,ov,of=next(triangles(od,ob));old=(ov,of)
for probe in probes:
 o=np.array(probe['origin']);direction=np.array(probe['direction']);hits=intersections(v,f,o,direction)
 assert len(hits)>=2 and hits[-1]-hits[0]>.04,('Stone crown tunnel reopened',probe,hits)
 if old:assert len(intersections(*old,o,direction))==0,'before probe no longer reproduces the source defect'
print(f'Stone: {len(probes)} former clear passages now hit the reconstructed exterior')
