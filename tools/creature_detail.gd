extends SceneTree
## Крупный вид текстурированной модели с тем же материалом, что в матче.
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var args := OS.get_cmdline_user_args()
 var id := StringName(args[0] if args.size() > 0 else "creature_likorez_shadow")
 var output := args[1] if args.size() > 1 else "/tmp/creature-detail.png"
 root.size = Vector2i(1280, 1080)
 var world := Node3D.new()
 root.add_child(world)
 var env := WorldEnvironment.new()
 env.environment = Environment.new()
 env.environment.background_mode = Environment.BG_COLOR
 env.environment.background_color = Color("141923")
 env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 env.environment.ambient_light_color = Color.WHITE
 env.environment.ambient_light_energy = 0.6
 world.add_child(env)
 var light := DirectionalLight3D.new()
 light.rotation_degrees = Vector3(-35, -28, 0)
 light.light_energy = 1.25
 world.add_child(light)
 var actor := CreatureAnim.new()
 world.add_child(actor)
 actor.set_model(CreatureModels.build(CardDB.creature(id)), CardDB.creature(id))
 actor.set_process(false)
 actor.idle_on = true
 if args.size() < 3 or args[2] != "rest":
  for f in range(90): actor._process(1.0/60)
 var h := actor.get_height()
 var camera := Camera3D.new()
 world.add_child(camera)
 camera.current = true
 camera.fov = 32
 var distance := maxf(h, actor.get_extent()) * 2.15
 camera.look_at_from_position(Vector3(distance*.12, h*.65, distance), Vector3(0,h*.52,0))
 await process_frame
 await process_frame
 RenderingServer.force_draw(false)
 root.get_texture().get_image().save_png(output)
 world.queue_free()
 await process_frame
 quit()
