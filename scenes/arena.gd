class_name Arena
extends Node3D
## Арена: пол, бортик, 6 слотов (сетка 2x3). Слоты 0..2 дальний ряд (z<0), 3..5 ближний.
## Карты крупные и портретные (как карты ворот): в бою на одной карте помещаются два существа
## по трети её длины с третью пустоты между ними.

## Масштаб мира относительно шара: карты и поле огромные, шар маленький (как в Бакуганах).
const WORLD := 3.5
const STEP_X := 3.7 * WORLD
const STEP_Z := 4.7 * WORLD
## Зона попадания = карта: прямоугольник CARD_W x CARD_H. Между картами просторно (~1.2·WORLD).
const CARD_W := 2.5 * WORLD
const CARD_H := 3.5 * WORLD
const FLOOR_SIZE := Vector3(13.4 * WORLD, 0.2, 13.6 * WORLD)
const RIM_HEIGHT := 0.6
const RIM_THICK := 0.3 * WORLD

var _decor: Node3D

var markers: Array[Marker3D] = []
var _highlights: Array[MeshInstance3D] = []
var _built := false


func _ready() -> void:
	_build()


func _build() -> void:
	if _built:
		return
	_built = true

	var mat := PhysicsMaterial.new()
	mat.friction = 0.6
	mat.bounce = 0.15

	# Пол
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.physics_material_override = mat
	add_child(floor_body)
	var fcs := CollisionShape3D.new()
	var fshape := BoxShape3D.new()
	fshape.size = FLOOR_SIZE
	fcs.shape = fshape
	fcs.position = Vector3(0, -FLOOR_SIZE.y * 0.5, 0)
	floor_body.add_child(fcs)
	var fmesh := MeshInstance3D.new()
	var fbox := BoxMesh.new()
	fbox.size = FLOOR_SIZE
	fmesh.mesh = fbox
	var fsm := ShaderMaterial.new()
	fsm.shader = Shader.new()
	fsm.shader.code = FLOOR_SHADER
	fsm.set_shader_parameter("world", WORLD)
	fmesh.material_override = fsm
	fmesh.position = Vector3(0, -FLOOR_SIZE.y * 0.5, 0)
	floor_body.add_child(fmesh)

	# Бортик: 4 коробки по краям
	var hx := FLOOR_SIZE.x * 0.5
	var hz := FLOOR_SIZE.z * 0.5
	_add_rim(Vector3(FLOOR_SIZE.x + RIM_THICK * 2.0, RIM_HEIGHT, RIM_THICK), Vector3(0, RIM_HEIGHT * 0.5, -hz - RIM_THICK * 0.5), mat)
	_add_rim(Vector3(FLOOR_SIZE.x + RIM_THICK * 2.0, RIM_HEIGHT, RIM_THICK), Vector3(0, RIM_HEIGHT * 0.5, hz + RIM_THICK * 0.5), mat)
	_add_rim(Vector3(RIM_THICK, RIM_HEIGHT, FLOOR_SIZE.z), Vector3(-hx - RIM_THICK * 0.5, RIM_HEIGHT * 0.5, 0), mat)
	_add_rim(Vector3(RIM_THICK, RIM_HEIGHT, FLOOR_SIZE.z), Vector3(hx + RIM_THICK * 0.5, RIM_HEIGHT * 0.5, 0), mat)

	# Маркеры слотов, рамки и подсветка
	for i in range(6):
		var m := Marker3D.new()
		m.name = "Slot%d" % i
		m.position = _local_slot_pos(i)
		add_child(m)
		markers.append(m)

		var frame := MeshInstance3D.new()
		var fb := PlaneMesh.new()
		fb.size = Vector2(CARD_W, CARD_H)
		frame.mesh = fb
		frame.material_override = _frame_material(i)
		frame.position = m.position + Vector3(0, 0.006, 0)
		frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(frame)

		var hl := MeshInstance3D.new()
		var hb := BoxMesh.new()
		hb.size = Vector3(CARD_W, 0.02, CARD_H)
		hl.mesh = hb
		var hm := StandardMaterial3D.new()
		hm.albedo_color = Color(1.0, 0.9, 0.2, 0.35)
		hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hl.material_override = hm
		hl.position = m.position + Vector3(0, 0.02, 0)
		hl.visible = false
		add_child(hl)
		_highlights.append(hl)
	_build_decor()
	_build_motes()


func _add_rim(size: Vector3, pos: Vector3, mat: PhysicsMaterial) -> void:
	var body := StaticBody3D.new()
	body.physics_material_override = mat
	body.position = pos
	add_child(body)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _stone(Color(0.22, 0.22, 0.25), 0.6, 0.9, 0.5)
	body.add_child(mi)


func _local_slot_pos(i: int) -> Vector3:
	var col: int = i % 3
	var row: int = floori(i / 3.0)
	return Vector3((col - 1) * STEP_X, 0.0, (row - 0.5) * STEP_Z)


## Мировая позиция центра слота (y = 0, уровень пола).
func slot_position(i: int) -> Vector3:
	if i < 0 or i > 5:
		return global_position
	if is_inside_tree():
		return to_global(_local_slot_pos(i))
	return position + _local_slot_pos(i)


## Слот, в чей прямоугольник (размер карты) попадает точка по XZ; иначе -1. y < -1 даёт -1.
func slot_at(world_pos: Vector3) -> int:
	if world_pos.y < -1.0:
		return -1
	var best := -1
	var best_d := INF
	for i in range(6):
		var c := slot_position(i)
		var dx := absf(world_pos.x - c.x)
		var dz := absf(world_pos.z - c.z)
		if dx <= CARD_W * 0.5 and dz <= CARD_H * 0.5:
			var d := dx * dx + dz * dz
			if d < best_d:
				best_d = d
				best = i
	return best


func set_highlight(slots: Array) -> void:
	_build()
	for i in range(_highlights.size()):
		_highlights[i].visible = slots.has(i)


# ------------------------------------------------------------ оформление

static var _noise_cache := {}


static func _noise_tex(freq: float, normal: bool, bump: float, ramp_lo: float, ramp_hi: float, ftype: int = FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> NoiseTexture2D:
	var key := "%s%s%s%s%s%s" % [freq, normal, bump, ramp_lo, ramp_hi, ftype]
	if _noise_cache.has(key):
		return _noise_cache[key]
	var n := FastNoiseLite.new()
	n.noise_type = ftype
	n.frequency = freq
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = 512
	t.height = 512
	t.seamless = true
	if normal:
		t.as_normal_map = true
		t.bump_strength = bump
	else:
		var g := Gradient.new()
		g.set_color(0, Color(ramp_lo, ramp_lo, ramp_lo))
		g.set_color(1, Color(ramp_hi, ramp_hi, ramp_hi))
		t.color_ramp = g
	_noise_cache[key] = t
	return t


## Каменный материал: процедурный альбедо-шум + нормал-карта, триплпланар в мировых координатах.
static func _stone(tint: Color, rough: float = 0.8, scale: float = 0.6, bump: float = 0.4) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = _noise_tex(0.012, false, 0.0, 0.35, 1.0, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	m.normal_enabled = true
	m.normal_texture = _noise_tex(0.03, true, 8.0 * bump, 0.0, 1.0)
	m.normal_scale = 1.2
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	return m


## Пол арены: тёмные металлические плиты со швами и большой гравированный круг призыва
## (кольца, руны, гексаграмма), по линиям которого медленно бегут волны свечения.
const FLOOR_SHADER := """
shader_type spatial;
uniform float world = 3.5;
uniform vec4 line_col : source_color = vec4(0.35, 0.75, 1.0, 1.0);
uniform vec4 line_col2 : source_color = vec4(0.75, 0.45, 1.0, 1.0);
varying vec3 lp;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float line_seg(vec2 p, vec2 a, vec2 b, float w) {
	vec2 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return smoothstep(w, w * 0.3, length(pa - ba * h));
}
float ring(float r, float rad, float w) { return smoothstep(w, w * 0.3, abs(r - rad)); }

void vertex() { lp = VERTEX; }

void fragment() {
	vec2 p = lp.xz / world;
	float r = length(p);
	float ang = atan(p.y, p.x);
	// плиты 2x2 со швами и разным тоном
	vec2 tile = floor(p / 2.0);
	vec2 tf = fract(p / 2.0);
	float seam = 1.0 - smoothstep(0.0, 0.015, min(min(tf.x, 1.0 - tf.x), min(tf.y, 1.0 - tf.y)));
	float tone = 0.85 + 0.3 * hash(tile);
	float grain = hash(floor(p * 60.0)) * 0.04;
	vec3 base = vec3(0.075, 0.08, 0.1) * tone + grain;
	base *= 1.0 - seam * 0.6;
	// круг призыва
	float circ = ring(r, 2.3, 0.03) + ring(r, 3.5, 0.045) + ring(r, 3.75, 0.02) + ring(r, 5.6, 0.035) + ring(r, 5.85, 0.015);
	float runes = step(0.55, fract(ang * 24.0 / 6.28318)) * step(3.55, r) * step(r, 3.7);
	runes += step(0.7, fract(ang * 48.0 / 6.28318 + 0.5)) * step(5.63, r) * step(r, 5.8) * 0.8;
	float hexa = 0.0;
	for (int i = 0; i < 6; i++) {
		float a0 = float(i) * 1.0472 + 0.5236;
		float a2 = a0 + 2.0944;
		hexa += line_seg(p, vec2(cos(a0), sin(a0)) * 5.6, vec2(cos(a2), sin(a2)) * 5.6, 0.03);
	}
	float spokes = smoothstep(0.02, 0.006, abs(sin(ang * 6.0)) * r) * step(2.3, r) * step(r, 3.5);
	float g = clamp(circ + runes + hexa * 0.7 + spokes * 0.6, 0.0, 1.0);
	// волна свечения от центра наружу
	float wave = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(r * 1.6 - TIME * 1.3), 4.0);
	vec3 lc = mix(line_col.rgb, line_col2.rgb, 0.5 + 0.5 * sin(ang * 3.0 + TIME * 0.2));
	ALBEDO = mix(base, lc * 0.35, g * 0.5);
	EMISSION = lc * g * (0.6 + 1.6 * wave) + lc * 0.04 * smoothstep(7.0, 0.0, r);
	METALLIC = 0.6;
	ROUGHNESS = 0.35 + 0.3 * hash(tile + 3.1) - seam * 0.1;
}
"""

const FRAME_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.8, 0.3, 1.0);
uniform vec2 dims = vec2(2.0, 2.1);
void fragment() {
	vec2 p = (UV - 0.5) * dims;
	vec2 q = dims * 0.5 - abs(p);          // расстояние до краёв
	float d = min(q.x, q.y);
	float edge = smoothstep(0.07, 0.04, d) * step(0.0, d);
	// рунические штрихи вдоль границы
	float along = (q.x < q.y) ? p.y : p.x;
	float dash = step(0.45, fract(along * 2.2)) ;
	float runes = smoothstep(0.17, 0.14, abs(d - 0.12)) * dash * step(0.16, min(q.x, q.y) + 0.0) ;
	runes *= 0.8;
	// уголки
	float corner = step(max(q.x, q.y), 0.34) * smoothstep(0.1, 0.06, d) ;
	float inner = smoothstep(0.35, 0.0, d) * 0.05;
	// тёмная гладкая плита под карту (без синусоидных пятен: на большом поле они выглядели как грязные тени)
	vec3 stone = vec3(0.075, 0.08, 0.10) + 0.025 * smoothstep(1.2, 0.0, length(p));
	float g = clamp(edge + runes * 0.7 + corner, 0.0, 1.0);
	// пустое место под карту ворот: приглушённая гравировка (ярко светится только подсветка выбора)
	ALBEDO = mix(stone, col.rgb * 0.5, g * 0.6);
	EMISSION = col.rgb * (g * 0.35 + inner * 0.6);
	ROUGHNESS = 0.85;
}
"""

var _frame_shader: Shader


func _frame_material(i: int) -> ShaderMaterial:
	if _frame_shader == null:
		_frame_shader = Shader.new()
		_frame_shader.code = FRAME_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = _frame_shader
	sm.set_shader_parameter("col", Color(1.0, 0.78, 0.35))
	sm.set_shader_parameter("dims", Vector2(CARD_W, CARD_H) / WORLD)
	return sm


func _glow_mat(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c.darkened(0.3)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.roughness = 0.15
	m.metallic_specular = 0.8
	return m


func _mi(mesh: Mesh, mat: Material, pos: Vector3, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	(parent if parent != null else (_decor if _decor != null else self)).add_child(mi)
	return mi


func _crystal(pos: Vector3, c: Color, height: float, tilt_seed: int, light: bool = true) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = tilt_seed
	var root := Node3D.new()
	root.position = pos
	(_decor if _decor != null else self).add_child(root)
	var mat := _glow_mat(c, 2.2)
	for k in range(3):
		var h := height * (1.0 if k == 0 else rng.randf_range(0.45, 0.7))
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.16 * h / height + 0.06 if k == 0 else 0.1
		cm.height = h
		cm.radial_segments = 6
		cm.rings = 1
		var mi := _mi(cm, mat, Vector3.ZERO, root)
		if k > 0:
			var a := rng.randf() * TAU
			mi.position = Vector3(cos(a), 0, sin(a)) * 0.2
			mi.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4))
		mi.position.y += h * 0.5
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not light:
		return
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = 1.4
	l.omni_range = 4.5 * WORLD
	l.position = Vector3(0, height * 0.6, 0)
	root.add_child(l)


## Медленно поднимающиеся искры над полем: пространство боя «живёт».
func _build_motes() -> void:
	var p := GPUParticles3D.new()
	p.amount = 260
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.visibility_aabb = AABB(Vector3(-FLOOR_SIZE.x, -2, -FLOOR_SIZE.z), Vector3(FLOOR_SIZE.x * 2, 30, FLOOR_SIZE.z * 2))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(FLOOR_SIZE.x * 0.6, 0.5, FLOOR_SIZE.z * 0.6)
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0, 0.15, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	var grad := Gradient.new()
	grad.set_color(0, Color(0.5, 0.8, 1.0, 0.0))
	grad.add_point(0.2, Color(0.6, 0.85, 1.0, 1.0))
	grad.add_point(0.75, Color(0.8, 0.55, 1.0, 0.8))
	grad.set_color(grad.get_point_count() - 1, Color(0.8, 0.5, 1.0, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.vertex_color_use_as_albedo = true
	qm.albedo_color = Color(2.0, 2.0, 2.0)
	qm.albedo_texture = VisualUtil.soft_dot()
	q.material = qm
	p.draw_pass_1 = q
	p.position = Vector3(0, 0.5, 0)
	add_child(p)


## Декор строится в исходных единицах (поле ~10x10) внутри узла, увеличенного в WORLD раз.
func _build_decor() -> void:
	_decor = Node3D.new()
	_decor.name = "Decor"
	_decor.scale = Vector3.ONE * WORLD
	add_child(_decor)
	var F := Vector3(FLOOR_SIZE.x / WORLD, FLOOR_SIZE.y, FLOOR_SIZE.z / WORLD)
	var hx := F.x * 0.5 + RIM_THICK / WORLD
	var hz := F.z * 0.5 + RIM_THICK / WORLD
	var stone := _stone(Color(0.36, 0.36, 0.39), 0.75, 0.5, 0.6)
	var dark := _stone(Color(0.16, 0.16, 0.18), 0.9, 0.35, 0.8)

	# Ступенчатое основание (только визуально, без коллизий): колизей-алтарь.
	for s in range(3):
		var sz := Vector3(hx * 2.0 + 0.6 + s * 1.6, 0.5, hz * 2.0 + 0.6 + s * 1.6)
		var bm := BoxMesh.new()
		bm.size = sz
		_mi(bm, dark if s % 2 == 0 else stone, Vector3(0, -0.45 - s * 0.45, 0))
	# золотая инкрустация по краю пола
	var gold := _glow_mat(Color(1.0, 0.72, 0.25), 1.2)
	gold.metallic = 0.8
	for e in [[Vector3(F.x - 0.1, 0.005, 0.06), Vector3(0, 0.003, -F.z * 0.5 + 0.2)],
			[Vector3(F.x - 0.1, 0.005, 0.06), Vector3(0, 0.003, F.z * 0.5 - 0.2)],
			[Vector3(0.06, 0.005, F.z - 0.1), Vector3(-F.x * 0.5 + 0.2, 0.003, 0)],
			[Vector3(0.06, 0.005, F.z - 0.1), Vector3(F.x * 0.5 - 0.2, 0.003, 0)]]:
		var bm2 := BoxMesh.new()
		bm2.size = e[0]
		var inl := _mi(bm2, gold, e[1])
		inl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Колонны по углам: задние высокие, передние — низкие постаменты, чтобы не закрывать арену в обзоре.
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
	for ci in range(4):
		var cx: float = corners[ci].x * (hx + 0.55)
		var cz: float = corners[ci].y * (hz + 0.55)
		var h: float = 3.2 if corners[ci].y < 0 else 0.7
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.42
		cyl.bottom_radius = 0.5
		cyl.height = h
		cyl.radial_segments = 10
		_mi(cyl, stone, Vector3(cx, h * 0.5 - 0.2, cz))
		var cap := BoxMesh.new()
		cap.size = Vector3(1.2, 0.3, 1.2)
		_mi(cap, dark, Vector3(cx, h - 0.05, cz))
		var base := BoxMesh.new()
		base.size = Vector3(1.2, 0.35, 1.2)
		_mi(base, dark, Vector3(cx, -0.02, cz))
		var orb := SphereMesh.new()
		orb.radius = 0.28
		orb.height = 0.56
		orb.radial_segments = 16
		orb.rings = 8
		var oc: Color = VisualUtil.attr_color(ci).lightened(0.15)
		var front: bool = corners[ci].y > 0
		_mi(orb, _glow_mat(oc, 1.2 if front else 2.5), Vector3(cx, h + 0.4, cz))
		var ol := OmniLight3D.new()
		ol.light_color = oc
		ol.light_energy = 0.6 if front else 1.6
		ol.omni_range = 7.0 * WORLD
		ol.position = Vector3(cx, h + 0.4, cz)
		_decor.add_child(ol)

	# 6 кристаллов стихий по периметру
	var cpos := [Vector3(-3.0, 0, -hz - 0.1), Vector3(3.0, 0, -hz - 0.1), Vector3(-hx - 0.1, 0, 0.2), Vector3(hx + 0.1, 0, 0.2), Vector3(-2.6, 0, hz + 0.1), Vector3(2.6, 0, hz + 0.1)]
	for k in range(6):
		_crystal(cpos[k] + Vector3(0, 0.0, 0), VisualUtil.attr_color(k).lightened(0.1), 1.4 + 0.2 * (k % 3), 100 + k)

	# Земля и кольцо скал до горизонта
	var ground := PlaneMesh.new()
	ground.size = Vector2(400, 400)
	var gm := _stone(Color(0.10, 0.10, 0.12), 0.95, 0.12, 0.6)
	var gmi := _mi(ground, gm, Vector3(0, -2.3, 0))
	gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var rock := SphereMesh.new()
	rock.radial_segments = 7
	rock.rings = 4
	var rmat := _stone(Color(0.17, 0.17, 0.2), 0.95, 0.2, 1.0)
	for k in range(70):
		var a := rng.randf() * TAU
		var r := rng.randf_range(13.0, 70.0)
		var s := rng.randf_range(1.2, 4.0) * (1.0 + (r - 13.0) * 0.04)
		var mi := _mi(rock, rmat, Vector3(cos(a) * r, -2.3 + s * 0.2, sin(a) * r))
		mi.scale = Vector3(s, s * rng.randf_range(0.8, 2.2), s * rng.randf_range(0.8, 1.4))
		mi.rotation.y = rng.randf() * TAU
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Парящие кристаллы вдали
	for k in range(10):
		var a := rng.randf() * TAU
		var r := rng.randf_range(12.0, 22.0)
		_crystal(Vector3(cos(a) * r, -2.3, sin(a) * r), VisualUtil.attr_color(k % 6), rng.randf_range(2.0, 4.5), 500 + k, false)
