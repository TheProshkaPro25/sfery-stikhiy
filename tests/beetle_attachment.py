"""Rear Tide legs must enter the torso at the hip and remain free at the foot.

A closed, correctly weighted limb can still float beside a closed body. Test
actual inside/outside relationships, including engine skin palettes when given
--poses <deformation_audit creature directory>.
"""
import argparse,json,sys
from pathlib import Path
import numpy as np
root=Path(__file__).resolve().parents[1];sys.path.insert(0,str(root/'tools/models'))
from inspect_geometry import read_glb,triangles
from upgrade_rigs import globals_of

def containment(vertices,faces,points):
 tri=vertices[faces].astype(float);e1=tri[:,1]-tri[:,0];e2=tri[:,2]-tri[:,0];direction=np.array([.371,.239,.897]);direction/=np.linalg.norm(direction);h=np.cross(direction,e2);det=(e1*h).sum(1);valid=np.abs(det)>1e-10;inv=np.divide(1,det,out=np.zeros_like(det),where=valid);out=[]
 for origin in points:
  s=origin-tri[:,0];u=inv*(s*h).sum(1);q=np.cross(s,e1);t=inv*(q*e2).sum(1);a=inv*(q*direction).sum(1);ts=np.sort(t[valid&(u>=0)&(a>=0)&(u+a<=1)&(t>1e-7)])
  ts=ts[np.r_[True,np.diff(ts)>1e-6]] if len(ts) else ts;out.append(len(ts)%2==1)
 return np.asarray(out)

def verify(parts,label,hip_points=None):
 vertices=np.concatenate([parts[0][0],parts[1][0]]);faces=np.concatenate([parts[0][1],parts[1][1]+len(parts[0][0])])
 if hip_points is not None:assert containment(vertices,faces,hip_points).all(),(label,'hip joints outside torso')
 for side,leg,cap in [('L',2,3),('R',4,5)]:
  cv,cf=parts[cap];rim=cv[np.unique(cf)];sample=rim[::max(1,len(rim)//12)]
  assert containment(vertices,faces,[rim.mean(0)])[0],(label,side,'detached root cap')
  assert containment(vertices,faces,sample).mean()>=.4,(label,side,'root has insufficient overlap')
  lv,lf=parts[leg];tip=lv[lv[:,1]<=np.quantile(lv[:,1],.04)].mean(0)
  assert not containment(vertices,faces,[tip])[0],(label,side,'foot fused into body')
 print('Tide attachment:',label,'hips enter torso; feet remain outside')

args=argparse.ArgumentParser();args.add_argument('--poses',type=Path);args=args.parse_args();d,b=read_glb(root/'assets/creatures_hd/rogozhuk_tide.glb');pr=list(triangles(d,b));g=globals_of(d);names={n.get('name'):i for i,n in enumerate(d['nodes'])};verify([(v,f) for p,v,f in pr],'rest',[g[names['rear_thigh.'+side]][:3,3] for side in ['L','R']])
if args.poses:
 doc=json.loads((args.poses/'poses.json').read_text());meshes=doc['meshes'];source=[]
 for mesh in meshes:
  prefix=args.poses/mesh['prefix'];read=lambda name,dtype:np.fromfile(str(prefix)+'_'+name+'.bin',dtype);v=read('vertices',np.float32).reshape(-1,3);j=read('joints',np.int32).reshape(-1,mesh['stride']);w=read('weights',np.float32).reshape(j.shape);f=read('indices',np.int32).reshape(-1,3);source.append((v,j,w,f,mesh['mi']))
 selected=[]
 for action,target in [('idle',90),('appear',32),('attack',20),('attack',40),('hit',18)]:
  pose=min((p for p in doc['poses'] if p['action']==action),key=lambda p:abs(p['frame']-target));parts=[]
  for v,j,w,f,mi in source:
   palette=np.array(pose['palettes'][mi]).reshape(-1,3,4);pos=np.zeros_like(v)
   for k in range(j.shape[1]):
    m=palette[j[:,k]];pos+=(np.einsum('nij,nj->ni',m[:,:,:3],v)+m[:,:,3])*w[:,k,None]
   parts.append((pos,f))
  verify(parts,action+' '+str(pose['frame']))
