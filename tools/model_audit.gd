extends SceneTree
## Four views per creature: front, side, back and strike contact; saved with game materials.
func _initialize(): call_deferred("run")
func run():
 root.size=Vector2i(640,640)
 var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size()>0 else "/tmp/sfery-model-audit"
 DirAccess.make_dir_recursive_absolute(out)
 var stage := Node3D.new()
 root.add_child(stage)
 var env := WorldEnvironment.new()
 env.environment=Environment.new()
 env.environment.background_mode=Environment.BG_COLOR
 env.environment.background_color=Color("19202b")
 env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
 env.environment.ambient_light_color=Color.WHITE
 env.environment.ambient_light_energy=.65
 stage.add_child(env)
 var sun:=DirectionalLight3D.new()
 sun.rotation_degrees=Vector3(-40,-30,0);sun.light_energy=1.25
 stage.add_child(sun)
 var cam:=Camera3D.new();stage.add_child(cam);cam.current=true;cam.fov=34
 for d in CardDB.all_creatures():
  var actor:=CreatureAnim.new();stage.add_child(actor);actor.set_process(false)
  actor.set_model(CreatureModels.build(d),d);actor.idle_on=true
  var h:=actor.get_height();var hover:=actor.get_hover_height();var distance:=maxf(h+hover,actor.get_extent())*2.15
  for view in range(4):
   actor.reset()
   if view==3:
    actor.lunge(h*.2)
    for f in range(30):actor._process(actor._contact_time/30)
   else:
    for f in range(45):actor._process(1.0/60)
   var angle:float=[.0,PI*.5,PI,.25][view]
   cam.look_at_from_position(Vector3(sin(angle)*distance,h*.65+hover,cos(angle)*distance),Vector3(0,h*.5+hover,0))
   await process_frame;await process_frame
   RenderingServer.force_draw(false)
   root.get_texture().get_image().save_png(out+"/"+String(d.id)+"_%d.png"%view)
  print("AUDIT ",d.id)
  actor.queue_free();await process_frame
  CreatureModels.clear()
 stage.queue_free();await process_frame
 quit()
