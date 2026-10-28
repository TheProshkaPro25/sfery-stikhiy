extends RefCounted
## Эффекты удара победителя по стихии (после рывка): Пламя — столб и конусы огня + взрыв, Буря — вихрь и серпы,
## Свет — копьё-луч и вспышка, Камень — пыльный взрыв и осколки, Тень — щупальца и разрыв, Прилив — водяной столб и брызги.
## Шейдеры: scenes/shaders/fx_attack.gdshader (аддитивный, режимы mode 0..5) и fx_attack_dark.gdshader (Тень).
## Каждый материал один на шейдер, различия — instance uniform (col / fade / mode / seed). Все узлы временные:
## Tween + queue_free, как в VisualUtil. Подключается через preload (const AttackFx := preload(...)).
## Размеры считаются от цели: высота фигуры h и размер size (`figure_height()` / `figure_size()`).

const SHADER := preload("res://scenes/shaders/fx_attack.gdshader")
const SHADER_DARK := preload("res://scenes/shaders/fx_attack_dark.gdshader")

enum Mode { FIRE, WIND, BEAM, WATER, SLASH, ORB }

static var _mat: ShaderMaterial
static var _mat_dark: ShaderMaterial
static var _meshes: Dictionary = {}
static var _seed: int = 0


## Запускает удар стихии attr. from_pos/to_pos — точки на полу под атакующим и целью (мировые), tgt_h/tgt_size — рост и
## размер цели, src_h — рост атакующего (для луча). Возвращает длительность эффекта (с).
static func play(parent: Node3D, attr: int, from_pos: Vector3, to_pos: Vector3, tgt_h: float, tgt_size: float, src_h: float = -1.0) -> float:
	if parent == null or not parent.is_inside_tree():
		return 0.0
	var c: Color = VisualUtil.attr_color(attr)
	var q: int = GraphicsSettings.current()
	var h: float = maxf(tgt_h, 0.5)
	var rad: float = clampf(tgt_size * 0.4, h * 0.3, h * 0.6)
	if src_h < 0.0:
		src_h = h
	match attr:
		0:
			return _fire(parent, c, to_pos, h, rad, q)
		1:
			return _gale(parent, c, to_pos, from_pos, h, rad, q)
		2:
			return _light(parent, c, from_pos + Vector3(0, src_h * 0.5, 0), to_pos, h, q)
		3:
			return _stone(parent, c, to_pos, h, rad, q)
		4:
			return _shadow(parent, c, to_pos, h, rad, q)
		5:
			return _tide(parent, c, to_pos, h, rad, q)
	return 0.0


# ---------- стихии ----------

static func _fire(parent: Node3D, c: Color, b: Vector3, h: float, rad: float, q: int) -> float:
	var dur := 0.75
	# центральный столб
	_part(parent, _cyl(0.5, 0.38), Mode.FIRE, c, b, Vector3(rad * 0.3, h * 0.3, rad * 0.3), Vector3(rad * 1.2, h * 1.6, rad * 1.2), dur, 0.0, 0.0, 1.6)
	# конусы вокруг
	var n: int = [2, 3, 4][q]
	for i in n:
		var a: float = TAU * float(i) / float(n) + 0.6
		var off := Vector3(cos(a), 0, sin(a)) * rad * 0.5
		_part(parent, _cone(), Mode.FIRE, c, b + off, Vector3(rad * 0.25, h * 0.3, rad * 0.25), Vector3(rad * 0.8, h * (1.1 + 0.15 * float(i % 2)), rad * 0.8), dur * 0.9, 0.05 * float(i), 0.0, 1.6)
	# взрыв
	_part(parent, _sphere(), Mode.ORB, c.lightened(0.15), b + Vector3(0, h * 0.4, 0), Vector3.ONE * h * 0.3, Vector3.ONE * h * 0.9, dur * 0.4, 0.0, 0.0, 0.55)
	return dur


static func _gale(parent: Node3D, c: Color, b: Vector3, from: Vector3, h: float, rad: float, q: int) -> float:
	var dur := 0.7
	# вихрь вокруг цели (крутится)
	_part(parent, _cyl(0.5, 0.5), Mode.WIND, c, b, Vector3(rad * 1.0, h * 0.6, rad * 1.0), Vector3(rad * 1.7, h * 1.5, rad * 1.7), dur, 0.0, 3.5, 1.5)
	if q >= 1:
		_part(parent, _cyl(0.4, 0.5), Mode.WIND, c, b, Vector3(rad * 0.7, h * 0.5, rad * 0.7), Vector3(rad * 1.2, h * 1.3, rad * 1.2), dur, 0.05, -4.5, 1.5)
	# серпы-разрезы: квады лицом поперёк линии удара, видны сбоку; крест-накрест
	var dir: Vector3 = b - from
	dir.y = 0
	var yaw: float = atan2(dir.x, dir.z) + PI * 0.5 if dir.length() > 0.01 else 0.0
	var angles: Array = [-35.0, 40.0, 95.0]
	var count: int = 2 if q == 0 else 3
	for i in count:
		var s: float = h * 1.25
		var pv := _part(parent, _quad(), Mode.SLASH, c, b + Vector3(0, h * 0.5, 0), Vector3(s * 0.4, s * 0.4, s), Vector3(s, s, s), dur * 0.7, 0.04 + 0.08 * float(i), 0.0, 1.0)
		pv.rotation = Vector3(0, yaw, deg_to_rad(float(angles[i])))
	return dur


static func _light(parent: Node3D, c: Color, from: Vector3, b: Vector3, h: float, q: int) -> float:
	var dur := 0.6
	var to: Vector3 = b + Vector3(0, h * 0.5, 0)
	var d: Vector3 = to - from
	var len: float = maxf(d.length(), 0.1)
	var mid: Vector3 = from + d * 0.5
	var w: float = h * 0.2
	var pv := _part(parent, _cyl(0.5, 0.5), Mode.BEAM, c, mid, Vector3(w * 0.3, len, w * 0.3), Vector3(w, len, w), dur, 0.0, 0.0, 1.0, true)
	pv.rotation = _aim(d)
	if q >= 1:
		var pv2 := _part(parent, _cyl(0.5, 0.5), Mode.BEAM, c.lightened(0.3), mid, Vector3(w * 0.8, len, w * 0.8), Vector3(w * 1.5, len, w * 1.5), dur * 0.8, 0.0, 0.0, 0.25, true)
		pv2.rotation = pv.rotation
	_part(parent, _sphere(), Mode.ORB, c.lightened(0.4), to, Vector3.ONE * h * 0.2, Vector3.ONE * h * 0.65, dur * 0.5, 0.04, 0.0, 0.8, true)
	return dur


static func _stone(parent: Node3D, c: Color, b: Vector3, h: float, rad: float, q: int) -> float:
	var dur := 0.8
	var dust: Color = c.lerp(Color(0.85, 0.72, 0.52), 0.55)
	_part(parent, _sphere(), Mode.ORB, dust, b + Vector3(0, h * 0.35, 0), Vector3.ONE * h * 0.3, Vector3.ONE * h * 0.8, dur * 0.5, 0.0, 0.0, 0.5, true)
	# осколки: баллистика, вращение, затухание размера
	var n: int = [5, 8, 12][q]
	var m := StandardMaterial3D.new()
	m.albedo_color = c.darkened(0.15)
	m.roughness = 0.9
	m.emission_enabled = true
	m.emission = c.darkened(0.4)
	m.emission_energy_multiplier = 0.6
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + _seed
	_seed += 1
	for i in n:
		var mi := MeshInstance3D.new()
		if i % 2 == 0:
			var bm := BoxMesh.new()
			bm.size = Vector3(1.0, 0.8, 0.6)
			mi.mesh = bm
		else:
			var pm := PrismMesh.new()
			pm.size = Vector3(1.0, 1.0, 0.7)
			mi.mesh = pm
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.top_level = true
		parent.add_child(mi)
		var s: float = h * rng.randf_range(0.05, 0.12)
		var a: float = rng.randf() * TAU
		var p0: Vector3 = b + Vector3(cos(a), 0, sin(a)) * rad * 0.2 + Vector3(0, h * 0.2, 0)
		var v := Vector3(cos(a) * rng.randf_range(0.8, 2.0) * rad, rng.randf_range(1.8, 3.2) * h, sin(a) * rng.randf_range(0.8, 2.0) * rad)
		var spin := Vector3(rng.randf_range(-8, 8), rng.randf_range(-8, 8), rng.randf_range(-8, 8))
		var life: float = rng.randf_range(0.55, 0.8)
		mi.global_position = p0
		mi.scale = Vector3.ONE * s
		var tw := mi.create_tween()
		tw.tween_method(func(t: float) -> void:
			var tt: float = t * life
			mi.global_position = p0 + v * tt + Vector3(0, -4.5 * h, 0) * tt * tt * 0.5
			mi.rotation = spin * tt
			mi.scale = Vector3.ONE * s * (1.0 - smoothstep(0.6, 1.0, t)), 0.0, 1.0, life)
		tw.tween_callback(mi.queue_free)
	return dur


static func _shadow(parent: Node3D, c: Color, b: Vector3, h: float, rad: float, q: int) -> float:
	var dur := 0.8
	var n: int = [3, 5, 6][q]
	for i in n:
		var a: float = TAU * float(i) / float(n) + 0.3
		var off := Vector3(cos(a), 0, sin(a)) * rad * 0.95
		# щупальце растёт из-под цели и тянется к ней: наклон к центру вокруг касательной оси
		var pv := _part(parent, _cyl(0.1, 0.5, 10), Mode.WIND, c, b + off, Vector3(rad * 0.2, h * 0.2, rad * 0.2), Vector3(rad * 0.3, h * (1.2 + 0.2 * float(i % 3)), rad * 0.3), dur, 0.05 * float(i), 0.0, 1.0, false, true)
		var inward := Vector3(-off.x, 0, -off.z).normalized()
		pv.basis = Basis(Vector3.UP.cross(inward).normalized(), deg_to_rad(38.0 + 6.0 * float(i % 2)))
	# разрыв: тёмная сфера схлопывается
	_part(parent, _sphere(), Mode.ORB, c, b + Vector3(0, h * 0.5, 0), Vector3.ONE * h * 0.2, Vector3.ONE * h * 0.8, dur * 0.7, 0.2, 0.0, 1.0, false, true)
	VisualUtil.ring_wave(parent, b + Vector3(0, 0.05, 0), c, rad * 2.0, 0.6)
	return dur


static func _tide(parent: Node3D, c: Color, b: Vector3, h: float, rad: float, q: int) -> float:
	var dur := 0.8
	# столб поднимается и опадает
	_part(parent, _cyl(0.42, 0.5), Mode.WATER, c, b, Vector3(rad * 1.0, h * 0.2, rad * 1.0), Vector3(rad * 1.3, h * 1.35, rad * 1.3), dur, 0.0, 0.0, 1.6, false, false, Vector3(rad * 1.5, h * 0.35, rad * 1.5))
	if q >= 1:
		_part(parent, _cyl(0.5, 0.5), Mode.WATER, c.lightened(0.2), b, Vector3(rad * 1.6, h * 0.1, rad * 1.6), Vector3(rad * 2.1, h * 0.6, rad * 2.1), dur * 0.8, 0.08, 0.0, 1.2, false, false, Vector3(rad * 2.6, h * 0.1, rad * 2.6))
	VisualUtil.ring_wave(parent, b + Vector3(0, 0.05, 0), c.lightened(0.25), rad * 2.4, 0.7)
	return dur


# ---------- общее ----------

## Временная часть эффекта: опорный узел-пивот на полу (anchor_base — меш стоит на пивоте снизу, иначе центрирован), рост
## масштаба s0 → s1 (→ s2 к концу), огибающая прозрачности, вращение spin (рад/с вокруг Y). Возвращает пивот (для поворота).
static func _part(parent: Node3D, mesh: Mesh, mode: int, c: Color, pos: Vector3, s0: Vector3, s1: Vector3, dur: float, delay: float,
		spin: float, amp: float = 1.0, centered: bool = false, dark: bool = false, s2: Vector3 = Vector3(-1, 0, 0)) -> Node3D:
	var pv := Node3D.new()
	pv.top_level = true
	parent.add_child(pv)
	pv.global_position = pos
	pv.scale = s0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material(dark)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pv.add_child(mi)
	if not centered and mode != Mode.ORB and mode != Mode.SLASH:
		mi.position.y = 0.5  # меш единичной высоты стоит основанием на пивоте
	mi.set_instance_shader_parameter("col", c)
	mi.set_instance_shader_parameter("fade", 0.0)
	mi.set_instance_shader_parameter("seed", float(_seed % 17))
	if not dark:
		mi.set_instance_shader_parameter("mode", mode)
	_seed += 1
	var end: Vector3 = s1 if s2.x < 0.0 else s2
	var tw := pv.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_method(func(p: float) -> void:
		var k: float = 1.0 - pow(1.0 - minf(p / 0.55, 1.0), 2.0)
		var sc: Vector3 = s0.lerp(s1, k)
		if p > 0.55:
			sc = s1.lerp(end, (p - 0.55) / 0.45)
		pv.scale = sc
		if spin != 0.0:
			pv.rotation.y = spin * p * dur
		mi.set_instance_shader_parameter("fade", _env(p) * amp), 0.0, 1.0, dur)
	tw.tween_callback(pv.queue_free)
	return pv


## Огибающая прозрачности: быстро нарастает, держится, к концу гаснет.
static func _env(p: float) -> float:
	return clampf(p / 0.15, 0.0, 1.0) * (1.0 - smoothstep(0.55, 1.0, p))


## Углы (Euler), при которых ось Y узла смотрит вдоль d.
static func _aim(d: Vector3) -> Vector3:
	var y: Vector3 = d.normalized()
	var ref: Vector3 = Vector3.RIGHT if absf(y.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var x: Vector3 = ref.cross(y).normalized()
	var z: Vector3 = x.cross(y).normalized()
	return Basis(x, y, z).get_euler()


static func _material(dark: bool) -> ShaderMaterial:
	if dark:
		if _mat_dark == null:
			_mat_dark = ShaderMaterial.new()
			_mat_dark.shader = SHADER_DARK
		return _mat_dark
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
	return _mat


static func _cyl(top: float, bottom: float, seg: int = 20) -> Mesh:
	var key := "cyl%.2f_%.2f_%d" % [top, bottom, seg]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = 1.0
		m.radial_segments = seg
		m.rings = 6
		m.cap_top = false
		m.cap_bottom = false
		_meshes[key] = m
	return _meshes[key]


static func _cone() -> Mesh:
	return _cyl(0.0, 0.5, 16)


static func _sphere() -> Mesh:
	if not _meshes.has("sph"):
		var m := SphereMesh.new()
		m.radius = 0.5
		m.height = 1.0
		m.radial_segments = 24
		m.rings = 12
		_meshes["sph"] = m
	return _meshes["sph"]


static func _quad() -> Mesh:
	if not _meshes.has("quad"):
		var m := QuadMesh.new()
		m.size = Vector2.ONE
		_meshes["quad"] = m
	return _meshes["quad"]
