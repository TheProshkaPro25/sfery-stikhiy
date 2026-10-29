extends SceneTree
## Детерминированная запись движений: godot -s res://tools/animation_review.gd -- creature_kolossar_light /tmp/anim
## 30 кадров/с, последовательность: появление, рёв, атака, попадание и восстановление.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var id := StringName(args[0]) if args.size() > 0 else &"creature_kolossar_light"
	var out: String = args[1] if args.size() > 1 else "/tmp/animation_review"
	DirAccess.make_dir_recursive_absolute(out)
	CardDB.load_all()
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.06, 0.075, 0.11)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 1.5
	world.add_child(sun)
	var actor := CreatureAnim.new()
	world.add_child(actor)
	var model := CreatureModels.build(CardDB.creature(id))
	actor.set_model(model, CardDB.creature(id))
	actor.set_process(false)
	actor.idle_on = true
	var h := actor.get_height()
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	var distance := maxf(h, actor.get_extent()) * 2.8
	cam.fov = 36.0
	cam.look_at_from_position(Vector3(distance * 0.6, h * 0.6, distance), Vector3(0, h * 0.5, 0))
	for frame in range(174):
		match frame:
			0: actor.appear()
			42: actor.roar()
			84: actor.lunge(h * 0.23)
			126: actor.hit(Color(0.7, 0.8, 1.0), h * 0.075)
		actor._process(1.0 / 30.0)
		await process_frame
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png("%s/frame_%04d.png" % [out, frame])
	actor.reset()
	world.queue_free()
	CreatureModels.clear()
	await process_frame
	quit()
