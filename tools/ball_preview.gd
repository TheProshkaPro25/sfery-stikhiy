extends SceneTree
## Стенд сфер существ (оконный): godot -s res://tools/ball_preview.gd -- <папка> [режим] [качество]
## Поле арены и свет как в игре. Режимы:
##   sheet (по умолчанию) — для каждой из 6 стихий по очереди: шар крупно, бросок и полёт (камера погони игры),
##                          качение, касание, раскрытие (облёт камеры игры), сворачивание и возврат, нокаут;
##                          кадры <папка>/e<стихия>_<кадр>.png
##   still — 6 закрытых шаров в ряд крупным планом (шейдер оболочки), кадр still.png
## качество: low/medium/high (GraphicsSettings, без записи настроек).

const BALL_SCENE := preload("res://scenes/creature_ball.tscn")
const ARENA_SCENE := preload("res://scenes/arena.tscn")
const START := Vector3(0.0, 0.36, 5.9 * Arena.WORLD)

var _out := "user://ball_preview"
var _mode := "sheet"
var _world: Node3D
var _arena: Arena
var _rig: CameraRig
var _close: Camera3D
var _defs: Array = []
var _ball: CreatureBall
var _next := 0
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_mode = args[1]
	if args.size() > 2:
		GraphicsSettings.force_level(GraphicsSettings.level_from_name(args[2]))
	DirAccess.make_dir_recursive_absolute(_out)
	# проверки — с лимитом 60 fps (как tools/autoplay.gd, без записи в settings.cfg)
	GraphicsSettings.max_fps = 60
	Engine.max_fps = 60
	_rng.seed = 5
	_build_world()
	CardDB.load_all()
	for el in 6:
		for id in CardDB.creature_ids():
			var d := CardDB.creature(id)
			if d.attribute == el:
				_defs.append(d)
				break
	CreatureModels.preload_match(_defs)
	match _mode:
		"still":
			_still.call_deferred()
		_:
			_sheet.call_deferred()


func _build_world() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = Shader.new()
	sky_mat.shader.code = _sky_code()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.background_energy_multiplier = 1.5
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.52, 0.64)
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.1
	env.glow_strength = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.15, 0.13, 0.25)
	env.fog_density = 0.0025
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -30.0, 0.0)
	sun.light_color = Color(1.0, 0.9, 0.76)
	sun.light_energy = 2.6
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.6
	_world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35.0, 150.0, 0.0)
	fill.light_color = Color(0.45, 0.6, 1.0)
	fill.light_energy = 0.9
	_world.add_child(fill)
	_arena = ARENA_SCENE.instantiate()
	_world.add_child(_arena)
	GraphicsSettings.apply_world(root, env, sun)  # ставит Engine.max_fps = GraphicsSettings.max_fps (60)
	_rig = CameraRig.new()
	_world.add_child(_rig)
	_close = Camera3D.new()
	_close.fov = 40.0
	_world.add_child(_close)
	_rig.make_current()


## Шейдер неба игры — текстом из main.gd (main.gd не грузим: стенд не зависит от состояния геймплея).
func _sky_code() -> String:
	var src := FileAccess.get_file_as_string("res://scenes/main.gd")
	var a := src.find('const SKY_SHADER := """')
	if a < 0:
		return "shader_type sky;\nvoid sky() { COLOR = vec3(0.1, 0.08, 0.2); }"
	a = src.find("\n", a) + 1
	return src.substr(a, src.find('"""', a) - a)


func _spawn(d: CreatureDef, at: Vector3) -> CreatureBall:
	var b := BALL_SCENE.instantiate() as CreatureBall
	_world.add_child(b)
	b.setup(d, _next)
	_next += 1
	b.freeze_at(at)
	return b


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, name])


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _still() -> void:
	var balls: Array = []
	for i in 6:
		var b := _spawn(_defs[i], Vector3((i - 2.5) * 1.9, 0.36, 0.0))
		b.rotation = Vector3(0.5, i * 0.7, 0.2)
		balls.append(b)
	_close.make_current()
	_close.look_at_from_position(Vector3(0, 3.0, 10.5), Vector3(0, 0.75, 0))
	await _wait(1.0)
	await _shot("still")
	# полюс с эмблемой — вид сверху
	_close.look_at_from_position(Vector3(0, 11.0, 5.0), Vector3(0, 0.6, 0))
	for b in balls:
		b.rotation = Vector3.ZERO
	await _wait(0.3)
	await _shot("still_top")
	quit(0)


## Полный цикл одной стихии: крупно → бросок → полёт → касание → качение → раскрытие → сворачивание → нокаут.
func _sheet() -> void:
	for el in 6:
		var d: CreatureDef = _defs[el]
		var slot: int = [1, 4, 0, 2, 3, 5][el]
		var target := _arena.slot_position(slot) + Vector3(0, 0.36, 0)
		_ball = _spawn(d, START)
		_ball.slot = -1
		# крупно: шар в руке
		_close.make_current()
		_close.look_at_from_position(START + Vector3(1.6, 1.3, -2.4), START + Vector3(0, 0.5, 0))
		_ball.rotation = Vector3(0.4, 0.8, 0.0)
		await _wait(0.5)
		await _shot("e%d_0_close" % el)
		_ball.rotation = Vector3.ZERO
		# бросок: камера погони как в игре
		_rig.aim_view(START, 1.0, true)
		_rig.make_current()
		await _wait(0.1)
		var imp := ThrowController.impulse_for_target(START, target, 0.0, _rng)
		_rig.follow(_ball)
		_ball.launch(imp)
		await _wait(0.06)
		await _shot("e%d_1_throw" % el)
		var arc := CreatureBall.arc_for_speed(imp.length())
		await _wait(arc.x * 0.45)
		await _shot("e%d_2_flight" % el)
		await _wait(arc.x * 0.55 - 0.02)
		await _shot("e%d_3_touch" % el)
		await _wait(0.35)
		await _shot("e%d_4_roll" % el)
		while not _ball._done:
			await process_frame
		# встаёт на карту: раскрытие, облёт камеры игры
		_rig.zoom_slot(_arena.slot_position(slot))
		await _wait(0.4)
		var fpos := _arena.slot_position(slot) + Vector3(0.0, 0.38, 0.0)
		_ball.freeze_at(fpos)
		_ball.face_toward(fpos + Vector3(0, 0, -1))
		var h := _ball.figure_height()
		_rig.reveal_orbit(_arena.slot_position(slot), h, Vector3(0, 0, -1), _ball.figure_size())
		VisualUtil.ring_wave(_world, _arena.slot_position(slot) + Vector3(0, 0.08, 0), VisualUtil.attr_color(el), Arena.FIG_W * 0.7, 0.55)
		_ball.open_animated()
		# лепестки и знак на карте — крупно; затем кадр с облёта камеры игры
		_close.make_current()
		_close.look_at_from_position(fpos + Vector3(4.5, 5.0, 9.0), fpos + Vector3(0, 1.2, 0))
		await _wait(0.2)
		await _shot("e%d_5_open" % el)
		_rig.make_current()
		await _wait(0.25)
		await _shot("e%d_6_open" % el)
		await _wait(1.6)
		# сворачивание и возврат к владельцу — с общего плана поближе
		_close.make_current()
		var bp := _ball.global_position
		_close.look_at_from_position(bp + Vector3(9.0, 6.0, 16.0), bp + Vector3(0, 2.5, 0))
		var sig := _ball.vanish()
		await _wait(0.2)
		await _shot("e%d_7_close" % el)
		await _wait(0.3)
		await _shot("e%d_8_shut" % el)
		await _wait(0.2)
		await _shot("e%d_9_fly" % el)
		await sig
		_ball.queue_free()
		# нокаут
		var kb := _spawn(d, fpos)
		kb.open_animated()
		await _wait(1.0)
		var ks := kb.vanish(true)
		await _wait(0.75)
		await _shot("e%d_10_ko" % el)
		await ks
		kb.queue_free()
		await _wait(0.3)
	quit(0)

