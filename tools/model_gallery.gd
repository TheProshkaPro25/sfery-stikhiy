## Галерея 48 моделей: godot -s res://tools/model_gallery.gd -- /tmp/gallery
extends SceneTree
var stage: Node3D
func _initialize():
 call_deferred("run")
func run():
 CardDB.load_all()
 stage = Node3D.new()
 root.add_child(stage)
 var env := WorldEnvironment.new()
 env.environment = Environment.new()
 env.environment.background_mode = Environment.BG_COLOR
 env.environment.background_color = Color(0.055,0.07,0.105)
 env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 env.environment.ambient_light_color = Color(0.7,0.75,0.85)
 env.environment.ambient_light_energy = 0.65
 stage.add_child(env)
 var sun := DirectionalLight3D.new()
 sun.rotation_degrees = Vector3(-38,-35,0)
 sun.light_energy = 1.5
 stage.add_child(sun)
 var cam := Camera3D.new()
 stage.add_child(cam)
 cam.current = true
 cam.fov = 35
 var tag := "user://model_gallery"
 var args := OS.get_cmdline_user_args()
 if args.size()>0:tag=args[0]
 DirAccess.make_dir_recursive_absolute(tag)
 for definition in CardDB.all_creatures():
  var species: String = String(definition.id)
  var model := CreatureModels.build(definition)
  stage.add_child(model)
  var h: float = model.get_meta("height")
  var extent: float = model.get_meta("extent")
  var distance: float = maxf(h,extent)*2.8
  cam.position = Vector3(distance*0.35,h*0.65,distance)
  cam.look_at(Vector3(0,h*0.5,0))
  for i in range(10):await process_frame
  RenderingServer.force_draw(false)
  root.get_texture().get_image().save_png(tag+"/"+species+".png")
  model.queue_free()
  await process_frame
  CreatureModels.clear()
 stage.queue_free()
 await process_frame
 quit()
