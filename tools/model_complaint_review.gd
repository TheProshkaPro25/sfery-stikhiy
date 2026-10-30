extends SceneTree
const ReviewState := preload("res://tools/model_review_state.gd")
## Opaque exterior only, bright background and tinted back faces expose holes/folds.
func _initialize():call_deferred('run')
func run():
 var args:=OS.get_cmdline_user_args()
 var batch:=args[0]=='batch';var out:=args[1]
 var ids:Array[StringName]=[]
 if batch:
  for species in ['dragnar','gorgul','levian']:
   for attr in ['fire','gale','light','stone','shadow','tide']:ids.append(StringName('creature_'+species+'_'+attr))
  ids.append(&'creature_rogozhuk_stone');ids.append(&'creature_rogozhuk_light')
 else:
  for id in args[0].split(','):ids.append(StringName(id))
 DirAccess.make_dir_recursive_absolute(out);root.size=Vector2i(720,720)
 var stage:=Node3D.new();root.add_child(stage)
 var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color('ea35b8');env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.6;stage.add_child(env)
 var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,-30,0);sun.light_energy=1.1;stage.add_child(sun)
 for id in ids:
  # A raw GLB backup lives in an ignored directory and has no .import file.
  # Load it explicitly for reproducible before/after comparisons.
  var source_path := ''
  for arg in args:
   if arg.begins_with('source-dir='):source_path=arg.trim_prefix('source-dir=')+'/'+String(id).trim_prefix('creature_')+'.glb'
   elif arg.begins_with('source='):source_path=arg.trim_prefix('source=')
  if not source_path.is_empty():
   var document:=GLTFDocument.new();var state:=GLTFState.new()
   assert(document.append_from_file(source_path,state)==OK)
   var original:=document.generate_scene(state);var packed:=PackedScene.new()
   assert(packed.pack(original)==OK);original.free()
   CreatureModels._scenes['hd:'+String(id).trim_prefix('creature_')]=packed
  var a:=CreatureAnim.new();stage.add_child(a);a.set_process(false);a.set_model(CreatureModels.build(CardDB.creature(id)),CardDB.creature(id));a.idle_on=true;a._phase=0;a._clock=0
  if args.has("no-support"):a._support=null
  for arg in args:
   if arg.begins_with("phase="):a._phase=float(arg.trim_prefix("phase="))
  var surface:=ShaderMaterial.new();surface.shader=Shader.new();surface.shader.code='shader_type spatial; render_mode cull_disabled,specular_disabled; void fragment(){ALBEDO=FRONT_FACING?vec3(.65,.7,.75):vec3(.25,.55,.85);ROUGHNESS=1.;}'
  var hidden:=ShaderMaterial.new();hidden.shader=Shader.new();hidden.shader.code='shader_type spatial; void fragment(){discard;}'
  var stack:Array[Node]=[a]
  while not stack.is_empty():
   var n:Node=stack.pop_back()
   for ch in n.get_children():stack.append(ch)
   if n is MeshInstance3D and n.skin!=null and args.has('legs-only'):
    # Diagnostic cutaway only: expose lower legs hidden behind the tail/body.
    var skeleton:Skeleton3D=n.get_node(n.skeleton)
    var isolated:=ArrayMesh.new()
    for s in range(n.mesh.get_surface_count()):
     var arrays:Array=n.mesh.surface_get_arrays(s)
     var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
     var joints:PackedInt32Array=arrays[Mesh.ARRAY_BONES]
     var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
     var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
     var stride:int=weights.size()/vertices.size()
     var influence:=PackedFloat32Array();influence.resize(vertices.size())
     for i in range(vertices.size()):
      for k in range(stride):
       var slot:=joints[i*stride+k];var bone:int=n.skin.get_bind_bone(slot)
       var bone_name:String=String(skeleton.get_bone_name(bone)) if bone>=0 else String(n.skin.get_bind_name(slot))
       if bone_name.begins_with('thigh.') or bone_name.begins_with('shin.') or bone_name.begins_with('foot.'):
        influence[i]+=weights[i*stride+k]
     var selected:=PackedInt32Array()
     for i in range(0,indices.size(),3):
      if (influence[indices[i]]+influence[indices[i+1]]+influence[indices[i+2]])/3.0>.5:
       selected.append_array(indices.slice(i,i+3))
     if selected.is_empty():continue
     arrays[Mesh.ARRAY_INDEX]=selected
     isolated.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if stride==8 else 0)
    n.mesh=isolated
   if n is MeshInstance3D and n.skin!=null and not args.has('textured'):
    for s in range(n.mesh.get_surface_count()):n.set_surface_override_material(s,surface)
  var cam:=Camera3D.new();stage.add_child(cam);cam.current=true;cam.fov=32
  var h:=a.get_height()
  var pose_frames:=24
  for arg in args:
   if arg.begins_with('frames='):pose_frames=int(arg.trim_prefix('frames='))
  var poses:PackedStringArray = ['rest','idle60','idle120','idle240','attack24']
  for arg in args:
   if arg.begins_with('poses='):poses=arg.trim_prefix('poses=').split(',')
  for pose in poses:
   ReviewState.reset_actor(a);a.idle_on=pose!='rest'
   if pose=='rest':
    var bones:Array[Node]=[a]
    while not bones.is_empty():
     var node:Node=bones.pop_back();bones.append_array(node.get_children())
     if node is Skeleton3D:node.reset_bone_poses()
   var action := 'idle';var frame_count:=pose_frames
   for name in ['idle','appear','roar','attack','hit','brace','ability']:
    if pose.begins_with(name):
     action=name
     var suffix:=pose.trim_prefix(name)
     if not suffix.is_empty():frame_count=int(suffix)
     break
   match action:
    'appear':a.appear()
    'roar':a.roar()
    'attack':a.lunge(h*.22)
    'hit':a.hit(Color.WHITE,h*.075)
    'brace':a.brace()
    'ability':a.ability_pulse()
   if pose!='rest':
    for frame in range(frame_count):a._process(1.0/60)
   var box:=posed_bounds(a, String(id));var center:=box.get_center()
   var distance:=box.size.length()*.5/sin(deg_to_rad(cam.fov*.5))*1.12
   for side in range(4 if batch else 8):
    var angle:=PI*.25+side*TAU/(4 if batch else 8)
    var elevation:=.65 if "rogozhuk_stone" in String(id) or "levian" in String(id) else .10
    for arg in args:
     if arg.begins_with("elevation="):elevation=float(arg.trim_prefix("elevation="))
    cam.look_at_from_position(center+Vector3(sin(angle),elevation,cos(angle)).normalized()*distance,center)
    await process_frame;await process_frame;RenderingServer.force_draw(false)
    root.get_texture().get_image().save_png('%s/%s_%s_%d.png'%[out,id,pose,side] if batch or ids.size()>1 else '%s/%s_%d.png'%[out,pose,side])
  print('SURFACE REVIEW ',id)
  a.free();cam.free();CreatureModels.clear()
 quit()

func posed_bounds(actor:Node3D, id:String)->AABB:
 var stack:Array[Node]=[actor];var box:=AABB();var has:=false
 while not stack.is_empty():
  var node:Node=stack.pop_back();stack.append_array(node.get_children())
  if not node is MeshInstance3D or node.skin==null:continue
  var mesh:=node as MeshInstance3D;var sk:=mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
  if sk==null:continue
  var palette:Array[Transform3D]=[]
  for slot in range(mesh.skin.get_bind_count()):
   var bone:=mesh.skin.get_bind_bone(slot)
   if bone<0:bone=sk.find_bone(mesh.skin.get_bind_name(slot))
   palette.append(sk.get_bone_global_pose(bone)*mesh.skin.get_bind_pose(slot))
  for surface in range(mesh.mesh.get_surface_count()):
   var arrays:=mesh.mesh.surface_get_arrays(surface);var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var bones:PackedInt32Array=arrays[Mesh.ARRAY_BONES];var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS];var stride:=weights.size()/vertices.size()
   for i in range(0,vertices.size(),8):
    var selected := false
    if "levian" in id: selected = vertices[i].y < -.15
    elif "rogozhuk_stone" in id: selected = vertices[i].y > .025
    elif "rogozhuk_light" in id: selected = vertices[i].y < .02
    else:
     var leg_weight := 0.0
     for k in range(stride):
      var slot := bones[i*stride+k]
      var bind_bone := mesh.skin.get_bind_bone(slot)
      var name: StringName = sk.get_bone_name(bind_bone) if bind_bone >= 0 else mesh.skin.get_bind_name(slot)
      if String(name).begins_with("thigh.") or String(name).begins_with("shin.") or String(name).begins_with("foot."): leg_weight += weights[i*stride+k]
     selected = leg_weight > .5
    if not selected:continue
    var p:=Vector3.ZERO
    for k in range(stride):p+=(palette[bones[i*stride+k]]*vertices[i])*weights[i*stride+k]
    p=mesh.global_transform*p
    if has:box=box.expand(p)
    else:box=AABB(p,Vector3.ZERO);has=true
 return box
