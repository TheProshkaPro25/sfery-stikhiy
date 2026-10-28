class_name Arena
extends Node3D
## Арена: бескрайнее поле боя (пол уходит за горизонт), 6 слотов ворот (сетка 2x3) в освещённом центре,
## дальние ориентиры для масштаба. Слоты 0..2 дальний ряд (z<0), 3..5 ближний.
## Карты крупные и портретные (как карты ворот): в бою на одной карте помещаются два существа
## по трети её длины с третью пустоты между ними.

## Масштаб мира относительно шара: карты и поле огромные, шар маленький (как в Бакуганах).
const WORLD := 3.5
## Увеличение карт ворот и сетки на бескрайнем поле (существа растут вместе с картой: 0.85–1.0 её длины).
## Ближний край ворот (z ≈ 18) остаётся перед точкой броска main.THROW_Z = 20.65.
const CARD_SCALE := 1.25
## Единица узоров зоны ворот (круг призыва, рисунок карт): WORLD с учётом увеличения карт.
const UNIT := WORLD * CARD_SCALE
const STEP_X := 3.7 * UNIT
const STEP_Z := 4.7 * UNIT
## Зона попадания = карта: прямоугольник CARD_W x CARD_H. Между картами просторно (~1.2·UNIT).
const CARD_W := 2.5 * UNIT
const CARD_H := 3.5 * UNIT
## Размер освещённой зоны ворот (бывший пол-коробка): по нему считаются частицы и подсветка центра.
const FLOOR_SIZE := Vector3(13.4 * UNIT, 0.2, 13.6 * UNIT)
## Видимый пол: огромная плоскость, края тонут в тумане.
const GROUND_SIZE := 5000.0
## Физический пол и невидимый бортик далеко за слотами: промах укатывается в даль, но не бесконечно.
const PHYS_HALF := 90.0
const WALL_HEIGHT := 6.0

var _decor: Node3D
## Парящие осколки: [узел, базовая высота, фаза, скорость вращения].
var _floaters: Array = []

var markers: Array[Marker3D] = []
var _highlights: Array[MeshInstance3D] = []
var _built := false


func _ready() -> void:
	_build()


func _process(_delta: float) -> void:
	if _floaters.is_empty():
		return
	var t := Time.get_ticks_msec() * 0.001
	for f in _floaters:
		var n: Node3D = f[0]
		n.position.y = float(f[1]) + sin(t * 0.35 + float(f[2])) * 2.5
		n.rotation.y = t * float(f[3]) + float(f[2])


func _build() -> void:
	if _built:
		return
	_built = true
	_decor = Node3D.new()
	_decor.name = "Decor"
	add_child(_decor)

	var mat := PhysicsMaterial.new()
	mat.friction = 0.6
	mat.bounce = 0.15

	# Физический пол (верх на y = 0) и невидимые стены за горизонтом слотов
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.physics_material_override = mat
	add_child(floor_body)
	var fcs := CollisionShape3D.new()
	var fshape := BoxShape3D.new()
	fshape.size = Vector3(PHYS_HALF * 2.0 + 20.0, 1.0, PHYS_HALF * 2.0 + 20.0)
	fcs.shape = fshape
	fcs.position = Vector3(0, -0.5, 0)
	floor_body.add_child(fcs)
	for w in [[Vector3(PHYS_HALF * 2.0, WALL_HEIGHT, 2.0), Vector3(0, WALL_HEIGHT * 0.5, -PHYS_HALF)],
			[Vector3(PHYS_HALF * 2.0, WALL_HEIGHT, 2.0), Vector3(0, WALL_HEIGHT * 0.5, PHYS_HALF)],
			[Vector3(2.0, WALL_HEIGHT, PHYS_HALF * 2.0), Vector3(-PHYS_HALF, WALL_HEIGHT * 0.5, 0)],
			[Vector3(2.0, WALL_HEIGHT, PHYS_HALF * 2.0), Vector3(PHYS_HALF, WALL_HEIGHT * 0.5, 0)]]:
		var wcs := CollisionShape3D.new()
		var ws := BoxShape3D.new()
		ws.size = w[0]
		wcs.shape = ws
		wcs.position = w[1]
		floor_body.add_child(wcs)

	# Видимый пол до горизонта: линии силы, круг призыва в центре, туман к краям
	var fmesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	plane.subdivide_width = 8
	plane.subdivide_depth = 8
	fmesh.mesh = plane
	var fsm := ShaderMaterial.new()
	fsm.shader = Shader.new()
	fsm.shader.code = FLOOR_SHADER
	fsm.set_shader_parameter("world", UNIT)
	fmesh.material_override = fsm
	fmesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fmesh)

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


## Пол до горизонта (координаты в единицах «поля» = мир / world): в центре — освещённая зона ворот
## с гравированным кругом призыва; от неё во все стороны расходятся линии силы (лучи и кольца),
## по которым бегут волны свечения. Мелкие детали и свечение гаснут с расстоянием, цвет уходит
## в цвет горизонта — края плоскости не видно (остальное прячет туман окружения).
const FLOOR_SHADER := """
shader_type spatial;
uniform float world = 3.5;
uniform vec4 line_col : source_color = vec4(0.35, 0.75, 1.0, 1.0);
uniform vec4 line_col2 : source_color = vec4(0.75, 0.45, 1.0, 1.0);
uniform vec4 far_col : source_color = vec4(0.035, 0.03, 0.06, 1.0);
varying vec3 wp;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
// линия по расстоянию d с шириной w (в единицах поля) и сглаживанием по экранной производной
float aline(float d, float w) {
	float fw = fwidth(d) * 1.2;
	return 1.0 - smoothstep(w, w + fw, abs(d));
}
float line_seg(vec2 p, vec2 a, vec2 b, float w) {
	vec2 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return aline(length(pa - ba * h), w);
}
float ring(float r, float rad, float w) { return aline(r - rad, w); }

void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 p = wp.xz / world;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float near = smoothstep(9.0, 5.5, r);          // освещённая зона ворот
	float detail = smoothstep(60.0, 12.0, r);      // мелкие детали гаснут вдали (без ряби)
	// камень: крупные пятна + плиты 2x2 в центре
	float big = vnoise(p * 0.08) * 0.6 + vnoise(p * 0.31) * 0.4;
	vec2 tile = floor(p / 2.0);
	vec2 tf = fract(p / 2.0);
	float seam = (1.0 - smoothstep(0.0, 0.015 + fwidth(p.x) * 0.5, min(min(tf.x, 1.0 - tf.x), min(tf.y, 1.0 - tf.y)))) * near;
	float tone = mix(0.75 + 0.5 * big, 0.85 + 0.3 * hash(tile), near);
	vec3 base = mix(vec3(0.03, 0.03, 0.042), vec3(0.055, 0.058, 0.07), near) * tone;
	base *= 1.0 - seam * 0.6;
	// трещины-жилы в дальнем камне
	float vein = aline(vnoise(p * 0.12) - 0.5, 0.012) * (1.0 - near) * detail;
	// круг призыва (как раньше: кольца, руны, гексаграмма)
	float circ = ring(r, 2.3, 0.03) + ring(r, 3.5, 0.045) + ring(r, 3.75, 0.02) + ring(r, 5.6, 0.035) + ring(r, 5.85, 0.015);
	float runes = step(0.55, fract(ang * 24.0 / 6.28318)) * step(3.55, r) * step(r, 3.7);
	runes += step(0.7, fract(ang * 48.0 / 6.28318 + 0.5)) * step(5.63, r) * step(r, 5.8) * 0.8;
	float hexa = 0.0;
	for (int i = 0; i < 6; i++) {
		float a0 = float(i) * 1.0472 + 0.5236;
		float a2 = a0 + 2.0944;
		hexa += line_seg(p, vec2(cos(a0), sin(a0)) * 5.6, vec2(cos(a2), sin(a2)) * 5.6, 0.03);
	}
	float spokes = aline(sin(ang * 6.0) * r, 0.006) * step(2.3, r) * step(r, 3.5);
	float g = clamp(circ + runes + hexa * 0.7 + spokes * 0.6, 0.0, 1.0);
	// линии силы: 24 луча от центра и кольца каждые 6 единиц за пределами круга
	float sector = ang * 24.0 / 6.28318;
	float sid = floor(sector + 0.5);
	float ray = aline((fract(sector + 0.5) - 0.5) * 6.28318 / 24.0 * r, 0.025 + 0.0015 * r);
	float main_ray = step(0.5, fract(sid / 3.0 + 0.1)) ;  // каждый третий луч ярче
	float rings = aline((fract(r / 6.0 + 0.5) - 0.5) * 6.0, 0.02 + 0.0008 * r) * detail;
	float outside = smoothstep(5.9, 6.6, r);
	float far_fade = smoothstep(220.0, 15.0, r);
	// волны свечения бегут по лучам наружу, у каждого луча своя фаза
	float pulse = pow(0.5 + 0.5 * sin(r * 0.22 - TIME * 1.4 + hash(vec2(sid, 1.0)) * 6.28), 10.0);
	float force = (ray * (0.25 + 0.5 * main_ray) * (0.35 + 1.6 * pulse) + rings * 0.25) * outside * far_fade;
	// волна в круге призыва
	float wave = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(r * 1.6 - TIME * 1.3), 4.0);
	vec3 lc = mix(line_col.rgb, line_col2.rgb, 0.5 + 0.5 * sin(ang * 3.0 + TIME * 0.2));
	vec3 alb = mix(base, lc * 0.35, g * 0.5);
	alb += vec3(0.04, 0.06, 0.09) * vein;
	// к горизонту — ровный цвет дали
	float horizon = smoothstep(40.0, 400.0, r);
	ALBEDO = mix(alb, far_col.rgb, horizon);
	EMISSION = lc * g * (0.6 + 1.6 * wave) + lc * force * 0.45 + lc * vein * 0.08
		+ vec3(1.0, 0.82, 0.55) * 0.05 * smoothstep(9.5, 0.0, r);
	METALLIC = mix(0.08, 0.6, near);
	ROUGHNESS = mix(0.9, 0.35 + 0.3 * hash(tile + 3.1) - seam * 0.1, near);
}
"""

## Дальний ориентир-столб света: полупрозрачный, мягко гаснет кверху.
const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 col : source_color = vec4(1.0);
void fragment() {
	float v = UV.y;                        // 0 верх, 1 низ
	float edge = pow(abs(sin(UV.x * 3.14159)), 2.0);
	float flick = 0.85 + 0.15 * sin(TIME * 1.7 + UV.y * 9.0);
	ALBEDO = col.rgb * (0.6 + 1.4 * v * v) * flick;
	ALPHA = clamp(edge * smoothstep(0.0, 0.8, v) * 0.55, 0.0, 1.0);
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
	ALBEDO = mix(stone, col.rgb * 0.7, g * 0.8);
	EMISSION = col.rgb * (g * 1.0 + inner * 0.9);
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
	sm.set_shader_parameter("dims", Vector2(CARD_W, CARD_H) / UNIT)
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
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent != null else (_decor if _decor != null else self)).add_child(mi)
	return mi


func _crystal(pos: Vector3, c: Color, height: float, tilt_seed: int, light: bool = true) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = tilt_seed
	var root := Node3D.new()
	root.position = pos
	root.scale = Vector3.ONE * WORLD  # кристалл задан в единицах поля
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


## Дальние ориентиры (в мировых единицах): кольцо кристаллов стихий вокруг ворот, руины,
## парящие острова и осколки, столбы света, силуэты гор у горизонта. Всё без теней и коллизий.
func _build_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var stone := _stone(Color(0.30, 0.30, 0.34), 0.8, 0.12, 0.6)
	var dark := _stone(Color(0.12, 0.12, 0.15), 0.9, 0.08, 0.8)

	# Свет над зоной ворот: центр — освещённая «сцена», даль тонет в полутьме
	var spot := SpotLight3D.new()
	spot.position = Vector3(0, 70.0, 6.0)
	spot.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	spot.spot_range = 110.0
	spot.spot_angle = 26.0
	spot.spot_angle_attenuation = 1.6
	spot.light_energy = 1.4
	spot.light_color = Color(1.0, 0.9, 0.78)
	_decor.add_child(spot)

	# Кристаллы стихий — средний план вокруг ворот (дают масштаб существам и шару)
	for k in range(6):
		var a: float = TAU * (k + 0.5) / 6.0
		var r: float = 40.0 + 4.0 * (k % 2)
		_crystal(Vector3(cos(a) * r, 0.0, sin(a) * r), VisualUtil.attr_color(k).lightened(0.1), 1.8 + 0.3 * (k % 3), 100 + k, true)

	# Руины: обломки колонн и арок группами на дальнем плане
	var col_mesh := CylinderMesh.new()
	col_mesh.top_radius = 1.0
	col_mesh.bottom_radius = 1.15
	col_mesh.height = 1.0
	col_mesh.radial_segments = 10
	col_mesh.rings = 1
	var block := BoxMesh.new()
	for g in range(7):
		var ga: float = TAU * g / 7.0 + rng.randf_range(-0.2, 0.2)
		var gr: float = rng.randf_range(80.0, 150.0)
		var gc := Vector3(cos(ga) * gr, 0.0, sin(ga) * gr)
		var s: float = rng.randf_range(2.2, 3.4)
		for c in range(rng.randi_range(3, 5)):
			var off := Vector3(rng.randf_range(-14, 14), 0, rng.randf_range(-14, 14))
			var h: float = rng.randf_range(6.0, 26.0) * (1.0 if c > 0 else 1.4)
			var mi := _mi(col_mesh, stone, gc + off + Vector3(0, h * 0.5 - 0.5, 0))
			mi.scale = Vector3(s, h, s)
			mi.rotation = Vector3(rng.randf_range(-0.12, 0.12), rng.randf() * TAU, rng.randf_range(-0.12, 0.12))
		# перекладина-арка на двух колоннах
		if g % 2 == 0:
			var span: float = rng.randf_range(14.0, 20.0)
			var yaw: float = rng.randf() * TAU
			var axis := Vector3(cos(yaw), 0, sin(yaw))
			for side in [-1.0, 1.0]:
				var pm := _mi(col_mesh, stone, gc + axis * span * 0.5 * side + Vector3(0, 11.0, 0))
				pm.scale = Vector3(s, 23.0, s)
			var top := _mi(block, dark, gc + Vector3(0, 23.5, 0))
			top.scale = Vector3(span + s * 3.0, 3.0, s * 2.4)
			top.rotation.y = -yaw
			top.rotation.z = rng.randf_range(-0.08, 0.08)
		# обвалившиеся блоки
		for b in range(4):
			var bm := _mi(block, dark, gc + Vector3(rng.randf_range(-18, 18), 1.0, rng.randf_range(-18, 18)))
			bm.scale = Vector3(rng.randf_range(3, 8), rng.randf_range(2, 4), rng.randf_range(3, 7))
			bm.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))

	# Парящие острова (скала-перевёрнутый конус с кристаллом сверху) и осколки
	var cone := CylinderMesh.new()
	cone.top_radius = 1.0
	cone.bottom_radius = 0.05
	cone.height = 1.0
	cone.radial_segments = 7
	cone.rings = 2
	var shard := CylinderMesh.new()
	shard.top_radius = 0.0
	shard.bottom_radius = 0.5
	shard.height = 1.0
	shard.radial_segments = 5
	shard.rings = 1
	for k in range(9):
		var a: float = rng.randf() * TAU
		var r: float = rng.randf_range(110.0, 320.0)
		var y: float = rng.randf_range(25.0, 75.0) * (r / 200.0)
		var isl := Node3D.new()
		isl.position = Vector3(cos(a) * r, y, sin(a) * r)
		_decor.add_child(isl)
		var w: float = rng.randf_range(10.0, 26.0)
		var rock := _mi(cone, stone, Vector3(0, -w * 0.5, 0), isl)
		rock.scale = Vector3(w, w * rng.randf_range(0.9, 1.5), w * rng.randf_range(0.7, 1.0))
		var cc: Color = VisualUtil.attr_color(k % 6)
		var cm := _glow_mat(cc, 2.4)
		for q in range(3):
			var sh := _mi(shard, cm, Vector3(rng.randf_range(-w, w) * 0.35, 0.0, rng.randf_range(-w, w) * 0.3), isl)
			var sh_h: float = w * rng.randf_range(0.4, 0.9)
			sh.scale = Vector3(w * 0.12, sh_h, w * 0.12)
			sh.position.y = sh_h * 0.5
			sh.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))
		_floaters.append([isl, y, rng.randf() * TAU, rng.randf_range(-0.03, 0.03)])
	for k in range(26):
		var a: float = rng.randf() * TAU
		var r: float = rng.randf_range(55.0, 200.0)
		var y: float = rng.randf_range(12.0, 55.0)
		var n := Node3D.new()
		n.position = Vector3(cos(a) * r, y, sin(a) * r)
		_decor.add_child(n)
		var glow: bool = k % 3 == 0
		var sm: Material = _glow_mat(VisualUtil.attr_color(k % 6).lightened(0.2), 2.0) if glow else dark
		var len: float = rng.randf_range(2.5, 7.0)
		# ромб из двух пирамид
		var up := _mi(shard, sm, Vector3(0, len * 0.5, 0), n)
		up.scale = Vector3(len * 0.45, len, len * 0.45)
		var dn := _mi(shard, sm, Vector3(0, -len * 0.5, 0), n)
		dn.scale = Vector3(len * 0.45, len, len * 0.45)
		dn.rotation.x = PI
		n.rotation = Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
		_floaters.append([n, y, rng.randf() * TAU, rng.randf_range(0.1, 0.4) * (1.0 if k % 2 == 0 else -1.0)])

	# Столбы света стихий вдали
	var beam_sh := Shader.new()
	beam_sh.code = BEAM_SHADER
	var beam := CylinderMesh.new()
	beam.top_radius = 1.0
	beam.bottom_radius = 1.0
	beam.height = 1.0
	beam.cap_top = false
	beam.cap_bottom = false
	beam.radial_segments = 16
	for k in range(6):
		var a: float = TAU * k / 6.0 + 0.35 + rng.randf_range(-0.15, 0.15)
		var r: float = rng.randf_range(260.0, 420.0)
		var bmat := ShaderMaterial.new()
		bmat.shader = beam_sh
		bmat.set_shader_parameter("col", VisualUtil.attr_color(k).lightened(0.15))
		var bh := 900.0
		var bw: float = rng.randf_range(6.0, 11.0)
		var bi := _mi(beam, bmat, Vector3(cos(a) * r, bh * 0.5 - 5.0, sin(a) * r))
		bi.scale = Vector3(bw, bh, bw)

	# Силуэты гор у горизонта
	var mount := CylinderMesh.new()
	mount.top_radius = 0.04
	mount.bottom_radius = 1.0
	mount.height = 1.0
	mount.radial_segments = 6
	mount.rings = 2
	var mmat := StandardMaterial3D.new()
	mmat.albedo_color = Color(0.05, 0.045, 0.08)
	mmat.roughness = 1.0
	for k in range(22):
		var a: float = TAU * k / 22.0 + rng.randf_range(-0.1, 0.1)
		var r: float = rng.randf_range(850.0, 1300.0)
		var mh: float = rng.randf_range(90.0, 260.0)
		var mi := _mi(mount, mmat, Vector3(cos(a) * r, mh * 0.5 - 10.0, sin(a) * r))
		mi.scale = Vector3(rng.randf_range(140.0, 260.0), mh, rng.randf_range(120.0, 220.0))
		mi.rotation.y = rng.randf() * TAU
