extends SceneTree
## Compare the current GLB and Godot's imported scene by named bones and bind poses.
var failures:Array[String]=[]
func _initialize():call_deferred('run')
func flat(t:Transform3D)->Array:
 return [t.basis.x.x,t.basis.y.x,t.basis.z.x,t.origin.x,t.basis.x.y,t.basis.y.y,t.basis.z.y,t.origin.y,t.basis.x.z,t.basis.y.z,t.basis.z.z,t.origin.z]
func error_between(a:Array,b:Array)->float:
 if a.size()!=b.size():return INF
 var error:=0.0
 for i in range(a.size()):error=maxf(error,absf(float(a[i])-float(b[i])))
 return error
func inspect(model:Node,label:String)->Dictionary:
 root.add_child(model)
 var bones:={};var bindings:={};var mesh_info:={};var tracks:=0;var bind_error:=0.0
 var stack:Array[Node]=[model]
 while not stack.is_empty():
  var node:Node=stack.pop_back();stack.append_array(node.get_children())
  if node is Skeleton3D:
   for i in range(node.get_bone_count()):
    var name:String=node.get_bone_name(i)
    bones[name]={"rest":flat(node.get_bone_global_rest(i)),"parent":node.get_bone_name(node.get_bone_parent(i)) if node.get_bone_parent(i)>=0 else ""}
  if node is MeshInstance3D and node.skin!=null:
   var sk:Skeleton3D=node.get_node_or_null(node.skeleton)
   if sk==null:failures.append(label+': missing skeleton');continue
   var slots:=[]
   for slot in range(node.skin.get_bind_count()):
    var bone:int=node.skin.get_bind_bone(slot)
    if bone<0:bone=sk.find_bone(node.skin.get_bind_name(slot))
    if bone<0:failures.append(label+': missing bone binding');continue
    var pose:Transform3D=node.skin.get_bind_pose(slot)
    slots.append({"name":sk.get_bone_name(bone),"inverse":flat(pose)})
    bind_error=maxf(bind_error,error_between(flat(sk.get_bone_global_rest(bone)*pose),flat(Transform3D.IDENTITY)))
   bindings[String(node.name)]=slots
   var surfaces:=[]
   for surf in range(node.mesh.get_surface_count()):
    var arrays:Array=node.mesh.surface_get_arrays(surf)
    surfaces.append({"vertices":arrays[Mesh.ARRAY_VERTEX].size(),"indices":arrays[Mesh.ARRAY_INDEX].size(),"weight_stride":arrays[Mesh.ARRAY_WEIGHTS].size()/arrays[Mesh.ARRAY_VERTEX].size()})
   mesh_info[String(node.name)]=surfaces
  if node is AnimationPlayer:
   var animation_root:Node=node.get_node(node.root_node)
   for anim_name in node.get_animation_list():
    var anim:Animation=node.get_animation(anim_name)
    for track in range(anim.get_track_count()):
     if not anim.track_get_type(track) in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D]:continue
     tracks+=1
     var path:NodePath=anim.track_get_path(track)
     var target:Node=animation_root.get_node_or_null(NodePath(path.get_concatenated_names()))
     if target==null:failures.append(label+': animation target missing '+String(path));continue
     if path.get_subname_count()>0 and target is Skeleton3D and target.find_bone(path.get_subname(0))<0:
      failures.append(label+': animation bone missing '+String(path))
 if bind_error>0.00002:failures.append(label+': rest bind displacement '+str(bind_error))
 var result:={"bones":bones,"bindings":bindings,"meshes":mesh_info,"tracks":tracks,"rest_bind_error":bind_error}
 model.free()
 return result
func run():
 var reports:=[]
 for definition in CardDB.all_creatures():
  var id:=String(definition.id).trim_prefix('creature_')
  if not (id.begins_with('levian_') or id.begins_with('gorgul_') or id.begins_with('dragnar_') or id in ['rogozhuk_light','rogozhuk_stone']):continue
  var path:='res://assets/creatures_hd/'+id+'.glb'
  var config:=ConfigFile.new();assert(config.load(path+'.import')==OK)
  var imported_path:String=config.get_value('remap','path')
  var md5_path:=imported_path.get_basename()+'.md5'
  var fresh:=FileAccess.get_file_as_string(md5_path).contains('source_md5="'+FileAccess.get_md5(path)+'"')
  if not fresh:failures.append(id+': stale imported source hash')
  var document:=GLTFDocument.new();var state:=GLTFState.new();assert(document.append_from_file(path,state)==OK)
  var raw:=inspect(document.generate_scene(state),id+' raw')
  var packed:=load(path) as PackedScene
  var imported:=inspect(packed.instantiate(),id+' imported')
  var rest_error:=0.0;var inverse_error:=0.0
  if raw.bones.keys()!=imported.bones.keys():failures.append(id+': bone inventory mismatch')
  for bone in raw.bones:
   if not imported.bones.has(bone):continue
   rest_error=maxf(rest_error,error_between(raw.bones[bone].rest,imported.bones[bone].rest))
   if raw.bones[bone].parent!=imported.bones[bone].parent:failures.append(id+': bone hierarchy mismatch '+bone)
  if raw.bindings.keys()!=imported.bindings.keys():failures.append(id+': bound mesh inventory mismatch')
  for mesh in raw.bindings:
   if not imported.bindings.has(mesh):continue
   var a:Array=raw.bindings[mesh];var b:Array=imported.bindings[mesh]
   if a.size()!=b.size():failures.append(id+': joint count mismatch');continue
   for slot in range(a.size()):
    if a[slot].name!=b[slot].name:failures.append(id+': joint slot mismatch')
    inverse_error=maxf(inverse_error,error_between(a[slot].inverse,b[slot].inverse))
  if rest_error>0.00002 or inverse_error>0.00002:failures.append(id+': raw/imported bind transforms differ')
  reports.append({"id":id,"source_cache_current":fresh,"rest_difference":rest_error,"inverse_bind_difference":inverse_error,"raw":raw,"imported":imported})
  print('BIND AUDIT ',id,' cache=',fresh,' rest=',rest_error,' inverse=',inverse_error)
  await process_frame
 var args:=OS.get_cmdline_user_args()
 var output:String=args[0] if not args.is_empty() else 'tools/_tmp/model-binding-audit.json'
 DirAccess.make_dir_recursive_absolute(output.get_base_dir())
 var file:=FileAccess.open(output,FileAccess.WRITE)
 file.store_string(JSON.stringify({"models":reports,"failures":failures}));file.close()
 print('BIND AUDIT models=',reports.size(),' failures=',failures)
 quit(1 if not failures.is_empty() else 0)
