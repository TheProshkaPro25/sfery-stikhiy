extends SceneTree
## Детерминированная запись движений: godot -s res://tools/animation_review.gd -- creature_kolossar_light /tmp/anim
## 30 кадров/с, последовательность: появление, рёв, атака, попадание и восстановление.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	root.size = Vector2i(960, 960)
	var ids: PackedStringArray = (args[0] if args.size() > 0 else "creature_kolossar_light").split(",")
	var out: String = args[1] if args.size() > 1 else "/tmp/animation_review"
	for id in ids:
		await _record(StringName(id), out if ids.size() == 1 else out + "/" + id, args.has("idle"), args.has("back"))
	quit()


func _record(id: StringName, out: String, idle_review: bool = false, back: bool = false) -> void:
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
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
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
	var hover := actor.get_hover_height()
	var distance := maxf(h + hover, actor.get_extent()) * 2.2
	cam.fov = 36.0
	var side := -1.0 if back else 1.0
	cam.look_at_from_position(Vector3(distance * 0.6 * side, h * 0.6 + hover, distance * side), Vector3(0, h * 0.5 + hover, 0))
	var floor_node := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(h * 8.0, h * 8.0)
	floor_node.mesh = plane
	floor_node.position.y = -0.025
	var floor_material := ShaderMaterial.new()
	floor_material.shader = Shader.new()
	floor_material.shader.code = "shader_type spatial; varying vec3 wp; void vertex(){ wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; } void fragment(){ vec2 q=abs(fract(wp.xz/2.0)-0.5); float line=1.0-smoothstep(0.475,0.49,max(q.x,q.y)); ALBEDO=mix(vec3(0.14,0.17,0.2),vec3(0.075,0.09,0.12),line); ROUGHNESS=1.0; }"
	floor_node.material_override = floor_material
	world.add_child(floor_node)
	for frame in range(360 if idle_review else 270):
		if idle_review:
			if frame == 240: actor.lunge(h * 0.23)
			if frame == 300: actor.hit(Color(0.7, 0.8, 1.0), h * 0.075)
		else:
			match frame:
				0: actor.appear()
				105: actor.roar()
				147: actor.lunge(h * 0.23)
				195: actor.hit(Color(0.7, 0.8, 1.0), h * 0.075)
		actor._process(1.0 / 30.0)
		await process_frame
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png("%s/frame_%04d.png" % [out, frame])
	actor.reset()
	world.queue_free()
	CreatureModels.clear()
	await process_frame
