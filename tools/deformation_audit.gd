extends SceneTree
## Export actual imported geometry and skin palettes AFTER animation and procedural IK.
var out := "tools/_tmp/deformation027"
func _initialize():call_deferred('run')
func run():
 var args:=OS.get_cmdline_user_args()
 if args.size()>0:out=args[0]
 var defs:=CardDB.all_creatures();defs.append(CardDB.creature(CardDB.RARE_SHADOW_ID))
 for d in defs:
  if args.size()>1 and args[1]!="clip" and not String(d.id) in args[1].split(","):continue
  var a:=CreatureAnim.new();root.add_child(a);a.set_process(false)
  a.set_model(CreatureModels.build(d),d);a.idle_on=true;a._phase=0;a.reset()
  if args.has("clip"):a._support=null
  var sk:Skeleton3D
  var meshes:Array[MeshInstance3D]=[]
  var stack:Array[Node]=[a]
  while not stack.is_empty():
   var node:Node=stack.pop_back()
   for ch in node.get_children():stack.append(ch)
   if node is Skeleton3D:sk=node
   if node is MeshInstance3D and node.skin!=null:meshes.append(node)
  var dir:=out+'/'+String(d.id);DirAccess.make_dir_recursive_absolute(dir)
  var info:={"id":String(d.id),"height":a.get_height(),"meshes":[],"poses":[]}
  for mi in range(meshes.size()):
   var m:=meshes[mi]
   var names:Array[String]=[]
   for slot in range(m.skin.get_bind_count()):
    var bone:=m.skin.get_bind_bone(slot)
    if bone<0:bone=sk.find_bone(m.skin.get_bind_name(slot))
    names.append(sk.get_bone_name(bone))
   for surf in range(m.mesh.get_surface_count()):
    var arrays:=m.mesh.surface_get_arrays(surf)
    var prefix:='%d_%d'%[mi,surf]
    var verts:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
    var joints:PackedInt32Array=arrays[Mesh.ARRAY_BONES]
    var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
    var idx:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
    for item in [["vertices",verts.to_byte_array()],["joints",joints.to_byte_array()],["weights",weights.to_byte_array()],["indices",idx.to_byte_array()]]:
     var file:=FileAccess.open(dir+'/'+prefix+'_'+item[0]+'.bin',FileAccess.WRITE);file.store_buffer(item[1]);file.close()
    info.meshes.append({"prefix":prefix,"mi":mi,"vertices":verts.size(),"stride":weights.size()/verts.size(),"bones":names})
  for action in ['idle','appear','roar','attack','hit','brace','ability']:
   a.reset();a._clock=0;a.idle_on=true
   match action:
    'appear':a.appear()
    'roar':a.roar()
    'attack':a.lunge(a.get_height()*.22)
    'hit':a.hit(Color.WHITE,a.get_height()*.075)
    'brace':a.brace()
    'ability':a.ability_pulse()
   var duration:float=4.0 if action=='idle' else a._duration
   var frames:=ceili(duration*60)
   for frame in range(frames+1):
    if frame>0:a._process(1.0/60)
    if frame%maxi(1,frames/8)!=0 and frame!=frames:continue
    var palettes:=[]
    for m in meshes:
     var pal:PackedFloat32Array=[]
     for slot in range(m.skin.get_bind_count()):
      var bone:=m.skin.get_bind_bone(slot)
      if bone<0:bone=sk.find_bone(m.skin.get_bind_name(slot))
      var t:Transform3D=sk.get_bone_global_pose(bone)*m.skin.get_bind_pose(slot)
      for row in range(3):
       pal.append(t.basis.x[row]);pal.append(t.basis.y[row]);pal.append(t.basis.z[row]);pal.append(t.origin[row])
     palettes.append(Array(pal))
    info.poses.append({"action":action,"frame":frame,"palettes":palettes})
  var file:=FileAccess.open(dir+'/poses.json',FileAccess.WRITE);file.store_string(JSON.stringify(info));file.close()
  print('DEFORM ',d.id)
  a.free();CreatureModels.clear();await process_frame
 quit()
