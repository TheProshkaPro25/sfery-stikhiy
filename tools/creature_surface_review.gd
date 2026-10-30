extends SceneTree
## Opaque exterior only, bright background and tinted back faces expose holes/folds.
func _initialize():call_deferred('run')
func run():
 var args:=OS.get_cmdline_user_args()
 var batch:=args[0]=='batch';var out:=args[1]
 var ids:Array[StringName]=[]
 if batch:
  for species in ['dragnar','grifalon','gorgul','klykar','kolossar','levian']:
   for attr in ['fire','gale','light','stone','shadow','tide']:ids.append(StringName('creature_'+species+'_'+attr))
 else:ids.append(StringName(args[0]))
 DirAccess.make_dir_recursive_absolute(out);root.size=Vector2i(640,640) if batch else Vector2i(960,960)
 var stage:=Node3D.new();root.add_child(stage)
 var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color('ea35b8');env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.6;stage.add_child(env)
 var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,-30,0);sun.light_energy=1.1;stage.add_child(sun)
 for id in ids:
  var a:=CreatureAnim.new();stage.add_child(a);a.set_process(false);a.set_model(CreatureModels.build(CardDB.creature(id)),CardDB.creature(id));a.idle_on=true
  var surface:=ShaderMaterial.new();surface.shader=Shader.new();surface.shader.code='shader_type spatial; render_mode cull_disabled,specular_disabled; void fragment(){ALBEDO=FRONT_FACING?vec3(.65,.7,.75):vec3(.25,.55,.85);ROUGHNESS=1.;}'
  var hidden:=ShaderMaterial.new();hidden.shader=Shader.new();hidden.shader.code='shader_type spatial; void fragment(){discard;}'
  var stack:Array[Node]=[a]
  while not stack.is_empty():
   var n:Node=stack.pop_back()
   for ch in n.get_children():stack.append(ch)
   if n is MeshInstance3D and n.skin!=null:
    for s in range(n.mesh.get_surface_count()):n.set_surface_override_material(s,surface if s==0 else hidden)
  var cam:=Camera3D.new();stage.add_child(cam);cam.current=true;cam.fov=32
  var h:=a.get_height();var distance:=maxf(h,a.get_extent())*2.2
  for pose in ['rest','idle','appear','attack']:
   a.reset();a.idle_on=pose!='rest'
   if pose=='appear':a.appear()
   if pose=='attack':a.lunge(h*.22)
   if pose!='rest':
    for frame in range(24):a._process(1.0/60)
   for side in range(4 if batch else 8):
    var angle:=side*TAU/(4 if batch else 8)
    cam.look_at_from_position(Vector3(sin(angle)*distance,h*.62,cos(angle)*distance),Vector3(0,h*.5,0))
    await process_frame;await process_frame;RenderingServer.force_draw(false)
    root.get_texture().get_image().save_png('%s/%s_%s_%d.png'%[out,id,pose,side] if batch else '%s/%s_%d.png'%[out,pose,side])
  print('SURFACE REVIEW ',id)
  a.free();cam.free();CreatureModels.clear()
 quit()
