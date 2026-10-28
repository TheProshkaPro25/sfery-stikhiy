class_name BallFx
extends RefCounted
## Эффекты сферы существа: частицы стихий (след полёта, качение, раскрытие, нокаут), вспышки, кольцо
## ускорения броска, знак стихии на карте, короткая подсветка. Все материалы, меши, градиенты — в статическом
## кэше (общие для всех шаров); частиц — по уровню графики (GraphicsSettings: Низкие ×0.35, Средние ×0.7).
## Источник света — только OmniLight3D без теней, один на эффект, на доли секунды и не на «Низких».

const FLASH_SHADER: Shader = preload("res://scenes/shaders/fx_flash.gdshader")
const SIGIL_SHADER: Shader = preload("res://scenes/shaders/fx_sigil.gdshader")

## Стихии (порядок VisualUtil.ATTR_NAMES).
enum { FIRE, STORM, LIGHT, STONE, SHADOW, TIDE }

static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}
static var _grads: Dictionary = {}
static var _tex: Dictionary = {}
static var _flash_mat: ShaderMaterial
static var _sigil_mat: ShaderMaterial
static var _quad1: QuadMesh
static var _plane1: PlaneMesh
static var _torus: TorusMesh


## Множитель числа частиц по уровню графики.
static func level_k() -> float:
	match GraphicsSettings.current():
		GraphicsSettings.Level.LOW:
			return 0.35
		GraphicsSettings.Level.MEDIUM:
			return 0.7
	return 1.0


static func _n(base: int) -> int:
	return maxi(2, int(round(base * level_k())))


## Яркий цвет стихии для света и частиц (цвета существ в VisualUtil приглушённые).
static func elem_color(el: int) -> Color:
	match el:
		FIRE: return Color(1.0, 0.45, 0.12)
		STORM: return Color(0.35, 0.95, 0.78)
		LIGHT: return Color(1.0, 0.86, 0.45)
		STONE: return Color(0.95, 0.62, 0.3)
		SHADOW: return Color(0.62, 0.32, 1.0)
		TIDE: return Color(0.3, 0.68, 1.0)
	return Color(0.9, 0.9, 0.9)


# ------------------------------------------------------------------ текстуры

## Четырёхлучевая блёстка (Свет).
static func _sparkle() -> Texture2D:
	if not _tex.has("sparkle"):
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var u := (x + 0.5) / n * 2.0 - 1.0
				var v := (y + 0.5) / n * 2.0 - 1.0
				var r := sqrt(u * u + v * v)
				var a := maxf(pow(maxf(0.0, 1.0 - absf(u) * 9.0), 2.0) * (1.0 - absf(v)), pow(maxf(0.0, 1.0 - absf(v) * 9.0), 2.0) * (1.0 - absf(u)))
				a = maxf(a, pow(maxf(0.0, 1.0 - r * 2.2), 2.0))
				img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
		_tex["sparkle"] = ImageTexture.create_from_image(img)
	return _tex["sparkle"]


## Клуб дыма с рваным краем (Тень, пыль).
static func _puff() -> Texture2D:
	if not _tex.has("puff"):
		var n := 64
		var noise := FastNoiseLite.new()
		noise.seed = 7
		noise.frequency = 0.09
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var u := (x + 0.5) / n * 2.0 - 1.0
				var v := (y + 0.5) / n * 2.0 - 1.0
				var r := sqrt(u * u + v * v)
				var a := clampf(1.0 - r, 0.0, 1.0)
				a = clampf(a * (0.7 + 0.8 * noise.get_noise_2d(x, y)) * 1.6, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a * a))
		_tex["puff"] = ImageTexture.create_from_image(img)
	return _tex["puff"]


## Удлинённая искра (Пламя, Буря).
static func _streak_tex() -> Texture2D:
	if not _tex.has("streak"):
		var n := 32
		var img := Image.create(n, n * 2, false, Image.FORMAT_RGBA8)
		for y in n * 2:
			for x in n:
				var u := (x + 0.5) / n * 2.0 - 1.0
				var v := (y + 0.5) / (n * 2) * 2.0 - 1.0
				var a := pow(maxf(0.0, 1.0 - absf(u)), 3.0) * pow(maxf(0.0, 1.0 - absf(v)), 1.5)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_tex["streak"] = ImageTexture.create_from_image(img)
	return _tex["streak"]


# ------------------------------------------------------------------ материалы и меши частиц

## Материал частиц: add — аддитивный, alpha — обычная прозрачность (дым, пыль), shard — освещённый осколок.
static func _mat(kind: String, tex: String) -> Material:
	var key := kind + ":" + tex
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	if kind == "shard":
		m.roughness = 0.8
	else:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.disable_receive_shadows = true
		if kind == "add":
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.albedo_color = Color(1.6, 1.6, 1.6)
		else:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		match tex:
			"sparkle": m.albedo_texture = _sparkle()
			"puff": m.albedo_texture = _puff()
			"streak": m.albedo_texture = _streak_tex()
			_: m.albedo_texture = VisualUtil.soft_dot()
	_mats[key] = m
	return m


## Меш частицы (общий): квад заданного размера с материалом, для осколков — коробочка.
static func _mesh(kind: String, tex: String, size: Vector2) -> Mesh:
	var key := "%s:%s:%.3f:%.3f" % [kind, tex, size.x, size.y]
	if _meshes.has(key):
		return _meshes[key]
	var m: PrimitiveMesh
	if kind == "shard":
		var b := BoxMesh.new()
		b.size = Vector3(size.x, size.y, size.x * 0.6)
		m = b
	else:
		var q := QuadMesh.new()
		q.size = size
		m = q
	m.material = _mat(kind, tex)
	_meshes[key] = m
	return m


static func _grad(key: String, stops: Array) -> Gradient:
	if _grads.has(key):
		return _grads[key]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array()
	g.colors = PackedColorArray()
	for s in stops:
		g.add_point(float(s[0]), s[1])
	_grads[key] = g
	return g


static func _curve_grow() -> Curve:
	if not _grads.has("curve_grow"):
		var c := Curve.new()
		c.add_point(Vector2(0.0, 0.4))
		c.add_point(Vector2(1.0, 1.6))
		_grads["curve_grow"] = c
	return _grads["curve_grow"]


static func _curve_shrink() -> Curve:
	if not _grads.has("curve_shrink"):
		var c := Curve.new()
		c.add_point(Vector2(0.0, 1.0))
		c.add_point(Vector2(1.0, 0.1))
		_grads["curve_shrink"] = c
	return _grads["curve_shrink"]


## Частицы стихии. role: trail — хвост полёта, roll — от контакта с полом при качении,
## open — вихрь раскрытия, burst — разлёт (нокаут, захлопывание). s — размер шара (м).
static func particles(el: int, role: String, s: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var c := elem_color(el)
	var hot := c.lightened(0.55)
	var clear := Color(c.r, c.g, c.b, 0.0)
	p.local_coords = false
	p.emitting = false
	p.draw_order = CPUParticles3D.DRAW_ORDER_INDEX
	var tex := "dot"
	var kind := "add"
	var size := Vector2(0.18, 0.18) * s
	var ramp := _grad("def%d" % el, [[0.0, Color(1, 1, 1, 1)], [0.3, hot], [1.0, clear]])
	match el:
		FIRE:  # искры и угли: летят вверх, мерцают
			tex = "streak"
			size = Vector2(0.09, 0.2) * s
			ramp = _grad("fire", [[0.0, Color(1, 0.95, 0.7, 1)], [0.35, Color(1, 0.55, 0.15, 1)], [0.75, Color(0.8, 0.15, 0.05, 0.8)], [1.0, Color(0.3, 0.05, 0, 0)]])
			p.gravity = Vector3(0, 2.5 * s, 0)
		STORM:  # завихрения
			tex = "streak"
			size = Vector2(0.06, 0.24) * s
			ramp = _grad("storm", [[0.0, Color(0.9, 1, 1, 0)], [0.2, Color(0.75, 1, 0.95, 1)], [1.0, Color(0.3, 0.9, 0.75, 0)]])
			p.gravity = Vector3.ZERO
			p.tangential_accel_min = 6.0 * s
			p.tangential_accel_max = 12.0 * s
		LIGHT:  # блёстки
			tex = "sparkle"
			size = Vector2(0.2, 0.2) * s
			ramp = _grad("light", [[0.0, Color(1, 1, 1, 1)], [0.25, Color(1, 0.9, 0.5, 0.3)], [0.45, Color(1, 0.95, 0.7, 1)], [0.7, Color(1, 0.85, 0.4, 0.2)], [1.0, Color(1, 0.8, 0.3, 0)]])
			p.gravity = Vector3(0, 0.3 * s, 0)
		STONE:  # осколки
			kind = "shard"
			tex = ""
			size = Vector2(0.09, 0.07) * s
			ramp = _grad("stone", [[0.0, Color(0.55, 0.48, 0.4, 1)], [0.8, Color(0.4, 0.34, 0.28, 1)], [1.0, Color(0.3, 0.26, 0.22, 1)]])
			p.gravity = Vector3(0, -18.0, 0)
			p.angular_velocity_min = -720.0
			p.angular_velocity_max = 720.0
			p.scale_amount_curve = _curve_shrink()
			p.particle_flag_rotate_y = true
		SHADOW:  # дымные хлопья
			kind = "alpha"
			tex = "puff"
			size = Vector2(0.4, 0.4) * s
			ramp = _grad("shadow", [[0.0, Color(0.35, 0.15, 0.55, 0)], [0.15, Color(0.22, 0.08, 0.35, 0.85)], [1.0, Color(0.05, 0.02, 0.08, 0)]])
			p.gravity = Vector3(0, 0.6 * s, 0)
			p.scale_amount_curve = _curve_grow()
		TIDE:  # брызги
			size = Vector2(0.12, 0.12) * s
			ramp = _grad("tide", [[0.0, Color(0.9, 0.97, 1, 1)], [0.4, Color(0.45, 0.75, 1, 0.9)], [1.0, Color(0.2, 0.5, 1, 0)]])
			p.gravity = Vector3(0, -14.0, 0)
	p.color_ramp = ramp
	p.scale_amount_min = 0.55
	p.scale_amount_max = 1.15
	match role:
		"trail":
			p.amount = _n(26)
			p.lifetime = 0.55
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 0.45 * s
			p.direction = Vector3.UP
			p.spread = 180.0
			p.initial_velocity_min = 0.1 * s
			p.initial_velocity_max = 0.8 * s
			if el == TIDE or el == STONE:
				p.gravity *= 0.35
		"roll":
			p.amount = _n(30)
			p.lifetime = 0.5
			p.direction = Vector3.UP
			p.spread = 50.0
			p.initial_velocity_min = 1.5 * s
			p.initial_velocity_max = 4.5 * s
			if el != STONE and el != TIDE:
				p.gravity += Vector3(0, -6.0 * s, 0)
		"open":
			p.amount = _n(36)
			p.lifetime = 0.9
			p.one_shot = true
			p.explosiveness = 0.55
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
			p.emission_ring_axis = Vector3.UP
			p.emission_ring_radius = 1.2 * s
			p.emission_ring_inner_radius = 0.7 * s
			p.emission_ring_height = 0.1 * s
			p.direction = Vector3.UP
			p.spread = 12.0
			p.initial_velocity_min = 4.0 * s
			p.initial_velocity_max = 8.0 * s
			p.tangential_accel_min = 14.0 * s
			p.tangential_accel_max = 22.0 * s
			p.radial_accel_min = -3.0 * s
			p.radial_accel_max = 1.0 * s
			p.damping_min = 0.5 * s
			p.damping_max = 1.5 * s
			if el == STONE or el == TIDE:
				p.gravity = Vector3(0, -6.0 * s, 0)
			size *= 0.6  # частиц много и они крупного масштаба: мельче, чтобы вихрь не сливался в пятно
		"burst":
			p.amount = _n(36)
			p.lifetime = 0.8
			p.one_shot = true
			p.explosiveness = 0.95
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 0.6 * s
			p.direction = Vector3.UP
			p.spread = 180.0
			p.initial_velocity_min = 1.5 * s
			p.initial_velocity_max = 5.0 * s
			p.damping_min = 1.0 * s
			p.damping_max = 2.5 * s
	p.mesh = _mesh(kind, tex, size)
	return p


## Одноразовые частицы в мире: сами удаляются.
static func one_shot(parent: Node, world_pos: Vector3, el: int, role: String, s: float) -> CPUParticles3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var p := particles(el, role, s)
	parent.add_child(p)
	p.global_position = world_pos
	p.restart()
	p.emitting = true
	parent.get_tree().create_timer(p.lifetime + 0.4).timeout.connect(p.queue_free)
	return p


# ------------------------------------------------------------------ вспышки и кольца

static func _flash_material() -> ShaderMaterial:
	if _flash_mat == null:
		_flash_mat = ShaderMaterial.new()
		_flash_mat.shader = FLASH_SHADER
	return _flash_mat


## Вспышка-ореол (билборд): раздувается до size и гаснет за dur секунд.
static func flash(parent: Node, world_pos: Vector3, c: Color, size: float, dur: float = 0.35) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if _quad1 == null:
		_quad1 = QuadMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _quad1
	mi.material_override = _flash_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = world_pos
	mi.set_instance_shader_parameter("col", c)
	mi.set_instance_shader_parameter("mode", 0)
	mi.scale = Vector3.ONE * size * 0.3
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size, dur).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void: mi.set_instance_shader_parameter("fade", v), 1.0, 0.0, dur).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


## Кольцо ускорения: плоское кольцо поперёк направления dir, быстро расширяется (бросок).
static func speed_ring(parent: Node, world_pos: Vector3, dir: Vector3, c: Color, radius: float, dur: float = 0.3) -> void:
	if parent == null or not parent.is_inside_tree() or dir.length() < 0.01:
		return
	if _plane1 == null:
		_plane1 = PlaneMesh.new()
		_plane1.size = Vector2(2, 2)
	var mi := MeshInstance3D.new()
	mi.mesh = _plane1
	mi.material_override = _flash_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var y := dir.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var basis := Basis(x, y, x.cross(y))
	mi.global_transform = Transform3D(basis.scaled(Vector3.ONE * radius * 0.25), world_pos)
	mi.set_instance_shader_parameter("col", c)
	mi.set_instance_shader_parameter("mode", 1)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_method(func(v: float) -> void:
		mi.global_transform = Transform3D(basis.scaled(Vector3.ONE * radius * v), world_pos + y * radius * (v - 0.25) * 0.6), 0.25, 1.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void: mi.set_instance_shader_parameter("fade", v), 1.0, 0.0, dur)
	tw.chain().tween_callback(mi.queue_free)


## Знак стихии вспыхивает на карте (плоский квад на полу).
static func sigil_flash(parent: Node, floor_pos: Vector3, el: int, size: float, dur: float = 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if _sigil_mat == null:
		_sigil_mat = ShaderMaterial.new()
		_sigil_mat.shader = SIGIL_SHADER
	if _plane1 == null:
		_plane1 = PlaneMesh.new()
		_plane1.size = Vector2(2, 2)
	var mi := MeshInstance3D.new()
	mi.mesh = _plane1
	mi.material_override = _sigil_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = floor_pos
	mi.set_instance_shader_parameter("element", el)
	mi.set_instance_shader_parameter("col", elem_color(el))
	mi.scale = Vector3.ONE * size * 0.35
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size * 0.5, dur * 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "rotation:y", 0.6, dur)
	tw.tween_method(func(v: float) -> void: mi.set_instance_shader_parameter("fade", v), 1.0, 0.0, dur * 0.6).set_delay(dur * 0.4)
	tw.chain().tween_callback(mi.queue_free)


## Короткая подсветка без теней (не на «Низких»): energy → 0 за dur.
static func light_flash(parent: Node, world_pos: Vector3, c: Color, energy: float, rng: float, dur: float = 0.4) -> void:
	if parent == null or not parent.is_inside_tree() or GraphicsSettings.current() == GraphicsSettings.Level.LOW:
		return
	var l := OmniLight3D.new()
	l.shadow_enabled = false
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng
	l.light_specular = 0.6
	parent.add_child(l)
	l.global_position = world_pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur).set_ease(Tween.EASE_IN)
	tw.tween_callback(l.queue_free)
