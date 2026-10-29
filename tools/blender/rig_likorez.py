"""Textured six-arm Likorez rig. Blender -b -P this.py -- input.glb output.glb.
Coordinates follow the approved concept; UVs and painted surfaces are preserved.
"""
import os,sys,math
import bpy
import numpy as np
from mathutils import Vector
sys.path.insert(0,os.path.dirname(__file__))
import rig_species as base
args=sys.argv[sys.argv.index('--')+1:]
src,dst=args[:2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.abspath(src))
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:o.select_set(True)
bpy.context.view_layer.objects.active=meshes[0]
if len(meshes)>1: bpy.ops.object.join()
mesh=bpy.context.object
# Canonical frame: height 2, ground Z=0, front -Y.
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
co=np.array([v.co[:] for v in mesh.data.vertices]);lo=co.min(0);hi=co.max(0)
k=2/(hi[2]-lo[2]); center=np.array([(hi[0]+lo[0])/2,(hi[1]+lo[1])/2,lo[2]])
co=(co-center)*k
for v,p in zip(mesh.data.vertices,co):v.co=p
print('BOUNDS',co.min(0),co.max(0),flush=True)
sx=co[:,0].max()-co[:,0].min()
# Image-space landmarks (approved concept 1254x1254), with local depth fitted to mesh.
def p(u,v,depth=None):
 x=(u/1254-.5)*sx/.98;z=(1-v/1254)*2
 if depth is None:
  dist=(co[:,0]-x)**2+(co[:,2]-z)**2
  near=co[np.argsort(dist)[:220],1]
  depth=float(np.median(near))
 return (x,depth,z)
H=p(633,672,0);C=p(643,438,0);N=p(643,320,-.025);HD=p(644,220,-.055)
spec=[('root',(0,0,0),(0,0,.13),None,False),('hips',H,C,'root',True),('chest',C,N,'hips',True),('neck',N,HD,'chest',True),('head',HD,p(644,125,-.055),'neck',True)]
# Three separated shoulder/elbow/wrist/blade-tip chains per side.
chains={
 '0.L':[(464,349),(326,352),(194,279),(399,29)],
 '0.R':[(807,397),(934,398),(1093,344),(919,29)],
 '1.L':[(463,444),(307,512),(184,592),(52,286)],
 '1.R':[(820,487),(941,547),(1081,600),(1215,286)],
 '2.L':[(499,547),(414,665),(305,750),(54,879)],
 '2.R':[(805,564),(862,685),(946,760),(1193,884)],
}
for suffix,points in chains.items():
 a,b,c,d=[p(*q) for q in points]
 hand_end=Vector(c).lerp(Vector(d),.12)
 spec += [('arm'+suffix,a,b,'chest',True),('forearm'+suffix,b,c,'arm'+suffix,True),('hand'+suffix,c,tuple(hand_end),'forearm'+suffix,True),('blade'+suffix,tuple(hand_end),d,'hand'+suffix,True)]
for side,points in {'L':[(545,690),(436,862),(365,1075),(296,1168)],'R':[(746,687),(862,858),(914,1045),(1050,1133)]}.items():
 a,b,c,d=[p(*q) for q in points]
 spec += [('thigh.'+side,a,b,'hips',True),('shin.'+side,b,c,'thigh.'+side,True),('foot.'+side,c,d,'shin.'+side,True)]
rig=base.build_armature(spec)
base.RIGID_ISLAND=.002
base.SMOOTH_ITERS=14
base.skin(mesh,rig,spec)
# The long blade bones provide an explicit local chain for all six weapons.
rig.animation_data_create();bpy.context.scene.render.fps=30
frame_axes=(Vector((0,-1,0)),Vector((0,0,1)),Vector((-1,0,0)),Vector(H))
deps=bpy.context.evaluated_depsgraph_get()
for clip,seconds in [('idle',2.0),('attack',1.2),('hit',.8),('roar',1.1),('stance',1.1)]:
 act=bpy.data.actions.new(clip);rig.animation_data.action=act
 n=round(seconds*30)
 for fr in range(n+1):
  t=fr/n;cycle=t*4*math.pi;env=math.sin(t*math.pi)
  strike=(max(0,min(1,(t-.17)/(.3333-.17)))**2*(3-2*max(0,min(1,(t-.17)/(.3333-.17))))) * (1-max(0,min(1,(t-.52)/.48))) if clip=='attack' else 0
  wind=math.sin(min(t/.3333,1)*math.pi) if clip=='attack' else 0
  poses={'hips':(0,0,1.8*math.sin(cycle)), 'chest':(1.8*math.sin(cycle),0,2*math.sin(cycle+.4)), 'neck':(1,0,-2*math.sin(cycle)), 'head':(1.5*math.sin(cycle*2),0,3*math.sin(cycle+.6))}
  for row in range(3):
   for side in ['L','R']:
    sign=-1 if side=='L' else 1;phase=cycle+row*.8+sign*.5
    poses['arm%d.%s'%(row,side)]=(2.4*math.sin(phase)-35*strike+12*wind,2*math.sin(phase*1.5)-8*strike,4*math.sin(phase)-sign*8*strike)
    poses['forearm%d.%s'%(row,side)]=(3*math.sin(phase+.7)-22*strike,0,4*math.sin(phase))
    poses['hand%d.%s'%(row,side)]=(2*math.sin(phase),0,3*math.sin(phase+1))
  for side,sign in [('L',1),('R',-1)]:
   bounce=max(0,math.sin(cycle)*sign)**3 if clip=='idle' else math.sin(t*math.pi)*(.5 if side=='L' else .15)
   poses['thigh.'+side]=(-8*bounce,0,1*sign*bounce)
   poses['shin.'+side]=(12*bounce,0,0)
   poses['foot.'+side]=(-4*bounce,0,0)
  if clip=='attack':
   poses['chest']=(4*wind-7*strike,0,-8*strike)
   poses['hips']=(2*wind,0,3*strike)
  elif clip in ['roar','stance']:
   poses['chest']=(-6*env,0,0);poses['head']=(-7*env,0,3*math.sin(t*math.tau)*env)
  elif clip=='hit':poses['chest']=(8*env,0,5*env);poses['head']=(5*env,0,-4*env)
  bpy.context.scene.frame_set(fr+1)
  base.key(rig,fr+1,poses,frame_axes)
  root=rig.pose.bones['root'];root.location=Vector((0,0,0))
  bpy.context.view_layer.update()
  evaluated=mesh.evaluated_get(deps)
  em=evaluated.to_mesh()
  vertices=np.empty(len(em.vertices)*3,dtype=np.float32);em.vertices.foreach_get('co',vertices)
  floor=float(vertices.reshape(-1,3)[:,2].min());evaluated.to_mesh_clear()
  root.location.z=-floor
  root.keyframe_insert('location',frame=fr+1)
 track=rig.animation_data.nla_tracks.new();track.name=clip
 strip=track.strips.new(clip,1,act)
 if hasattr(strip,'action_slot') and act.slots:strip.action_slot=act.slots[0]
 rig.animation_data.action=None
rig.pose.bones['root'].location=Vector((0,0,0))
for pb in rig.pose.bones:pb.rotation_quaternion=(1,0,0,0)
bpy.context.view_layer.update()
bpy.ops.object.select_all(action='DESELECT');mesh.select_set(True);rig.select_set(True)
bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=os.path.abspath(dst),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_apply=False)
print('RIGGED',dst,flush=True)
