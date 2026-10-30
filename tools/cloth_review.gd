extends SceneTree
## Actual GPU buffers, pinned seam, reset/teleport/hide/free and visual motion.
signal sampled(positions: PackedByteArray, targets: PackedByteArray)
var failures:=0
var checks:=0
func check(ok:bool,message:String):
 checks+=1
 if not ok:failures+=1;push_error(message)
func _initialize():call_deferred('run')
func accept_sample(p:PackedByteArray,t:PackedByteArray):sampled.emit(p,t)
func capture(solver):
 RenderingServer.call_on_render_thread(func():
  var p:PackedByteArray=solver._rd.buffer_get_data(solver._positions_buffer)
  var t:PackedByteArray=solver._rd.buffer_get_data(solver._skinned_targets_buffer)
  call_deferred('accept_sample',p,t))
 return await sampled
func run():
 var args:=OS.get_cmdline_user_args();var ids:PackedStringArray=(args[0] if args.size()>0 else 'creature_ratnik_fire').split(',');var out:=args[1] if args.size()>1 else 'tools/_tmp/review028/cloth-qa'
 DirAccess.make_dir_recursive_absolute(out);root.size=Vector2i(960,960)
 var world:=Node3D.new();root.add_child(world)
 var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color('141923');env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.65;world.add_child(env)
 var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,-30,0);sun.light_energy=1.3;world.add_child(sun)
 var cam:=Camera3D.new();world.add_child(cam);cam.current=true;cam.fov=36
 var report:=[]
 for id in ids:
  var a:=CreatureAnim.new();world.add_child(a);a.set_process(false);a.set_model(CreatureModels.build(CardDB.creature(StringName(id))),CardDB.creature(StringName(id)));a.idle_on=true
  var s=a._cloth;check(s!=null,'GPU solver exists: '+id)
  if s==null:a.free();continue
  s.set_process(false)
  for i in range(10):await process_frame
  check(s._gpu_init_done,'GPU initialization: '+id)
  var folder:=out+'/'+id;DirAccess.make_dir_recursive_absolute(folder)
  var max_displacement:=0.;var pinned_error:=0.;var minimum_y:=INF;var minimum_world_y:=INF;var measurements:=[];var started:=Time.get_ticks_msec()
  for f in range(300):
   if f==0:a.appear()
   if f==90:a.lunge(a.get_height()*.22)
   if f==135:a.hit(Color.WHITE,a.get_height()*.075)
   if f==180:a.hide()
   if f==186:a.show()
   if f==210:a.set_base(Vector3(a.get_height(),0,0))
   if f==240:a.reset();a.set_base(Vector3.ZERO)
   a._process(1./60);s._process(1./60)
   var h:=a.get_height();var dist:=maxf(h,a.get_extent())*2.5
   cam.look_at_from_position(a._base+Vector3(-dist*.6,h*.7,-dist),a._base+Vector3(0,h*.5,0))
   await process_frame;RenderingServer.force_draw(false)
   if f%4==0:root.get_texture().get_image().save_png('%s/frame_%04d.png'%[folder,f/4])
   if f in [30,60,100,140,175,188,212,242,290]:
    var buffers:Array=await capture(s);var pos:PackedFloat32Array=buffers[0].to_float32_array();var target:PackedFloat32Array=buffers[1].to_float32_array();var displacement:=0.;var pin:=0.
    for i in range(s._particle_count):
     var p:=Vector3(pos[i*4],pos[i*4+1],pos[i*4+2]);var t:=Vector3(target[i*4],target[i*4+1],target[i*4+2]);check(p.is_finite(),'finite particle '+id)
     var error:=p.distance_to(t);displacement=maxf(displacement,error);minimum_y=minf(minimum_y,p.y)
     minimum_world_y=minf(minimum_world_y,(s._ref_node.global_transform*p).y)
     if pos[i*4+3]==0:pin=maxf(pin,error)
    max_displacement=maxf(max_displacement,displacement);pinned_error=maxf(pinned_error,pin);measurements.append({'frame':f,'displacement':displacement,'pinned_error':pin})
    for pair in [['positions',buffers[0]],['targets',buffers[1]]]:
     var file:=FileAccess.open('%s/gpu_%03d_%s.bin'%[folder,f,pair[0]],FileAccess.WRITE);file.store_buffer(pair[1]);file.close()
  check(max_displacement>.005,'visible physical displacement '+id);check(max_displacement<.115,'bounded physical displacement '+id);check(pinned_error<.0001,'pinned seam follows body '+id);check(minimum_world_y>-.02*a.get_height(),'cloth stays above floor '+id)
  report.append({'id':id,'particles':s._particle_count,'triangles':s._tri_count,'collider_triangles':s._collider_tris.size(),'max_displacement':max_displacement,'pinned_error':pinned_error,'minimum_y':minimum_y,'minimum_world_y':minimum_world_y,'wall_seconds':(Time.get_ticks_msec()-started)/1000.,'samples':measurements})
  a.free();CreatureModels.clear()
  for f in range(5):await process_frame;RenderingServer.force_draw(false)
 var file:=FileAccess.open(out+'/report.json',FileAccess.WRITE);file.store_string(JSON.stringify({'checks':checks,'failures':failures,'models':report},'  '));file.close();print('Cloth GPU: ',checks,' checks, ',failures,' failures')
 world.queue_free();await process_frame;await process_frame;quit(1 if failures else 0)
