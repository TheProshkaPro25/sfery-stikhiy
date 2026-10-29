class_name Arena
extends Node3D
## Арена: бескрайнее поле боя (пол уходит за горизонт), 6 слотов ворот (сетка 2x3) в освещённом центре,
## дальние ориентиры для масштаба. Слоты 0..2 дальний ряд (z<0), 3..5 ближний.
## Карты крупные и портретные (как карты ворот): в бою на одной карте помещаются два существа
## по трети её длины с третью пустоты между ними.

## Масштаб мира относительно шара: карты и поле огромные, шар маленький (как в Бакуганах).
const WORLD := 3.5
## Масштаб существ на бескрайнем поле (существа 0.85–1.0 длины FIG_H).
const CARD_SCALE := 1.25
## Единица узоров зоны ворот (рисунок карт) и масштаба существ.
const UNIT := WORLD * CARD_SCALE
## Масштаб существ: прежний размер карты ворот. От него считаются модели (CreatureModels), эффекты шара
## и расстановка двух существ в бою — сферы и фигуры не растут вместе с картами.
const FIG_W := 2.5 * UNIT
const FIG_H := 3.5 * UNIT
## Карты ворот почти вдвое больше существ (по стороне): поле — огромные плиты, существа и сферы прежние.
const GATE_SCALE := 1.9
## Зона попадания = карта: прямоугольник CARD_W x CARD_H. Между картами просторно (~1.2·UNIT).
const CARD_W := FIG_W * GATE_SCALE
const CARD_H := FIG_H * GATE_SCALE
const GAP := 1.2 * UNIT
const STEP_X := CARD_W + GAP
const STEP_Z := CARD_H + GAP
## Единица узора пола (круг призыва, плиты, освещённая зона): раздвинута под крупную сетку ворот.
## Ближний край ворот (z ≈ 31.7) остаётся перед точкой броска main.THROW_Z.
const FIELD := UNIT * 1.8
## Размер освещённой зоны ворот (бывший пол-коробка): по нему считаются частицы и подсветка центра.
const FLOOR_SIZE := Vector3(13.4 * FIELD, 0.2, 13.6 * FIELD)
## Видимый пол: огромная плоскость, края тонут в тумане.
const GROUND_SIZE := 5000.0
## Физический пол и невидимый бортик далеко за слотами: промах укатывается в даль, но не бесконечно.
const PHYS_HALF := 130.0
const WALL_HEIGHT := 6.0

var _decor: Node3D
## Парящие осколки: [узел, базовая высота, фаза, скорость вращения].
var _floaters: Array = []

var _motes: GPUParticles3D
var _crystal_lights: Array[OmniLight3D] = []
var _floaters_on := true

signal slot_clicked(slot: int)

var markers: Array[Marker3D] = []
## Силуэты мест под ворота (по слоту), видны только при выборе места.
var _highlights: Array[MeshInstance3D] = []
var _ghost_tw: Array = []
var _lit: Array = []
var _hover := -1
var _pick := false
var _built := false


func _ready() -> void:
	_build()


## Уровень графики (GraphicsSettings): число искр, подсветка кристаллов, движение парящих осколков.
func apply_quality() -> void:
	_build()
	var n: int = int(GraphicsSettings.param("motes"))
	if _motes != null and _motes.amount != n:
		_motes.amount = n
	for l in _crystal_lights:
		l.visible = bool(GraphicsSettings.param("lights"))
	_floaters_on = bool(GraphicsSettings.param("floaters"))
	set_process(_floaters_on and not _floaters.is_empty())


func _process(_delta: float) -> void:
	if _floaters.is_empty() or not _floaters_on:
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
	fsm.set_shader_parameter("world", FIELD)
	fmesh.material_override = fsm
	fmesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fmesh)

	# Маркеры слотов и скрытые места под ворота: пустые слоты не видны, контур-силуэт карты
	# проявляется только при выборе места (set_highlight) и ярче — под курсором (set_hover)
	for i in range(6):
		var m := Marker3D.new()
		m.name = "Slot%d" % i
		m.position = _local_slot_pos(i)
		add_child(m)
		markers.append(m)
		_highlights.append(_make_ghost(i, m.position))
	_build_decor()
	_build_sanctuary()
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


## Подсветить места slots (пустые — полупрозрачный светящийся силуэт карты, занятые — контур вокруг карты).
## pick — места выбираются мышью прямо на поле (наведение подсвечивает, щелчок → slot_clicked).
func set_highlight(slots: Array, pick: bool = false) -> void:
	_build()
	_lit = slots.duplicate()
	_pick = pick and not slots.is_empty()
	if not _lit.has(_hover):
		_hover = -1
	for i in range(_highlights.size()):
		_fade_ghost(i)


## Место под курсором (из панели выбора или мыши над полем): контур ярче. -1 — ни одного.
func set_hover(slot: int) -> void:
	_build()
	slot = slot if _lit.has(slot) else -1
	if slot == _hover:
		return
	_hover = slot
	for i in range(_highlights.size()):
		_fade_ghost(i)


## Видна ли подсветка места (для подсказок и снимков).
func is_highlighted(slot: int) -> bool:
	return _lit.has(slot)


func _fade_ghost(i: int) -> void:
	var g: MeshInstance3D = _highlights[i]
	var sm := g.material_override as ShaderMaterial
	var on: bool = _lit.has(i)
	var hv: float = 1.0 if i == _hover else 0.0
	if _ghost_tw.size() > i and _ghost_tw[i] != null and _ghost_tw[i].is_valid():
		_ghost_tw[i].kill()
	if on:
		g.visible = true
	if not is_inside_tree():
		_ghost_vis(1.0 if on else 0.0, g)
		sm.set_shader_parameter("hover", hv)
		g.visible = on
		return
	var vis0: Variant = sm.get_shader_parameter("vis")  # null, пока параметр ни разу не задан
	var hov0: Variant = sm.get_shader_parameter("hover")
	var tw := create_tween().set_parallel(true)
	tw.tween_method(_ghost_vis.bind(g), float(vis0) if vis0 != null else 0.0, 1.0 if on else 0.0, 0.25 if on else 0.35)
	tw.tween_method(func(v: float) -> void: sm.set_shader_parameter("hover", v), float(hov0) if hov0 != null else 0.0, hv, 0.15)
	if not on:
		tw.chain().tween_callback(func() -> void: g.visible = _lit.has(i))
	while _ghost_tw.size() <= i:
		_ghost_tw.append(null)
	_ghost_tw[i] = tw


func _ghost_vis(v: float, g: MeshInstance3D) -> void:
	(g.material_override as ShaderMaterial).set_shader_parameter("vis", v)
	var n := g.get_child(0) as Label3D
	n.modulate.a = 0.45 * v


## Выбор места мышью прямо на поле, пока места подсвечены для выбора.
func _unhandled_input(event: InputEvent) -> void:
	if not _pick:
		return
	if event is InputEventMouseMotion:
		set_hover(_slot_under_mouse((event as InputEventMouseMotion).position))
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var s := _slot_under_mouse(mb.position)
			if _lit.has(s):
				get_viewport().set_input_as_handled()
				slot_clicked.emit(s)


## Подсвеченный слот под точкой экрана (луч камеры до пола), -1 — мимо.
func _slot_under_mouse(mp: Vector2) -> int:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return -1
	var o := cam.project_ray_origin(mp)
	var d := cam.project_ray_normal(mp)
	if absf(d.y) < 0.0001:
		return -1
	var t := (global_position.y - o.y) / d.y
	if t <= 0.0:
		return -1
	var s := slot_at(o + d * t)
	return s if _lit.has(s) else -1


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
	// круг призыва (как раньше: кольца, руны, гексаграмма) — считается только внутри круга (r < 6.3):
	// снаружи всё это нули, а пол занимает большую часть кадра
	float g = 0.0;
	if (r < 6.3) {
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
		g = clamp(circ + runes + hexa * 0.7 + spokes * 0.6, 0.0, 1.0);
	}
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

## Место под карту ворот: светящийся контур со скруглёнными углами чуть шире карты, уголки-скобы,
## полупрозрачный силуэт карты внутри и бегущий по контуру блик. vis — проявление, hover — под курсором.
## Занятое место: силуэт закрыт самой картой, виден только контур вокруг неё.
const GHOST_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 col : source_color = vec4(0.45, 0.85, 1.0, 1.0);
uniform vec4 hover_col : source_color = vec4(1.0, 0.85, 0.4, 1.0);
uniform vec2 size = vec2(24.0, 32.0);   // размер плоскости (м)
uniform vec2 card = vec2(20.8, 29.1);   // размер карты (м)
uniform float vis = 0.0;
uniform float hover = 0.0;
uniform float seed = 0.0;

float sd_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = (UV - 0.5) * size;
	float d = sd_box(p, card * 0.5 + 0.35, 1.1);          // контур чуть шире карты
	float w = 0.16 + 0.1 * hover;
	float line = 1.0 - smoothstep(w, w + fwidth(d) * 1.5 + 0.02, abs(d));
	float glow = exp(-abs(d) * (1.4 - 0.5 * hover)) * step(0.0, d) * 0.55;
	// уголки-скобы снаружи контура
	vec2 q = card * 0.5 + 0.95 - abs(p);
	float brk = (1.0 - smoothstep(0.12, 0.2, abs(min(q.x, q.y)))) * step(max(q.x, q.y), 3.2) * step(-0.2, min(q.x, q.y));
	// силуэт карты: лёгкая заливка, внутренняя рамка и окно эмблемы
	float inside = 1.0 - smoothstep(-0.05, 0.05, d);
	float di = sd_box(p, card * 0.5 - 1.2, 0.7);
	float inner = 1.0 - smoothstep(0.06, 0.06 + fwidth(di) * 1.5 + 0.02, abs(di));
	float win = abs(length(p - vec2(0.0, card.y * 0.06)) - card.x * 0.26);
	float wline = 1.0 - smoothstep(0.08, 0.1 + fwidth(win) * 1.5, win);
	float t = TIME + seed;
	float breathe = 0.75 + 0.25 * sin(t * 2.4);
	// блик бежит по периметру
	float ang = atan(p.y * card.x / card.y, p.x) / 6.28318 + 0.5;
	float run = pow(0.5 + 0.5 * sin((ang - t * 0.22) * 6.28318 * 2.0), 16.0);
	vec3 c = mix(col.rgb, hover_col.rgb, hover);
	float a = line * (0.75 + 0.25 * hover) * breathe + line * run * 0.6 + glow * (0.5 + 0.6 * hover) + brk * (0.6 + 0.4 * hover)
		+ inside * (0.07 + 0.13 * hover + inner * (0.22 + 0.25 * hover) + wline * (0.14 + 0.2 * hover));
	ALBEDO = c * (1.2 + 1.3 * hover) + vec3(run * line * 0.6);
	ALPHA = clamp(a * vis, 0.0, 1.0);
}
"""

var _ghost_shader: Shader


func _make_ghost(i: int, pos: Vector3) -> MeshInstance3D:
	if _ghost_shader == null:
		_ghost_shader = Shader.new()
		_ghost_shader.code = GHOST_SHADER
	var pad := 3.0
	var g := MeshInstance3D.new()
	g.name = "Ghost%d" % i
	var pm := PlaneMesh.new()
	pm.size = Vector2(CARD_W + pad * 2.0, CARD_H + pad * 2.0)
	g.mesh = pm
	var sm := ShaderMaterial.new()
	sm.shader = _ghost_shader
	sm.set_shader_parameter("size", pm.size)
	sm.set_shader_parameter("card", Vector2(CARD_W, CARD_H))
	sm.set_shader_parameter("seed", float(i) * 1.7)
	sm.set_shader_parameter("vis", 0.0)
	g.material_override = sm
	g.position = pos + Vector3(0, 0.015, 0)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.visible = false
	add_child(g)
	# номер места (как на кнопках панели выбора) в центре силуэта
	var n := Label3D.new()
	n.text = str(i + 1)
	n.font_size = 160
	n.outline_size = 0
	n.pixel_size = CARD_W * 0.0016
	n.rotation_degrees = Vector3(-90, 0, 0)
	n.position = Vector3(0, 0.01, CARD_H * 0.06)
	n.modulate = Color(0.75, 0.92, 1.0, 0.5)
	n.shaded = false
	n.double_sided = false
	g.add_child(n)
	return g


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


## Неподвижный декор (руины, горы) копится по парам «меш + материал» и рисуется одним MultiMesh
## на пару: вместо ~120 отдельных MeshInstance3D — 4 вызова отрисовки.
var _static_sets: Dictionary = {}


func _static(mesh: Mesh, mat: Material, pos: Vector3, scl: Vector3, rot: Vector3) -> void:
	var key := [mesh, mat]
	if not _static_sets.has(key):
		_static_sets[key] = []
	_static_sets[key].append(Transform3D(Basis.from_euler(rot) * Basis.from_scale(scl), pos))


func _flush_static() -> void:
	for key in _static_sets.keys():
		var xs: Array = _static_sets[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = key[0]
		mm.instance_count = xs.size()
		for i in range(xs.size()):
			mm.set_instance_transform(i, xs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = key[1]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_decor.add_child(mmi)
	_static_sets.clear()


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
	_crystal_lights.append(l)


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
	_motes = p


## Дальние ориентиры (в мировых единицах): кольцо кристаллов стихий вокруг ворот, руины,
## парящие острова и осколки, столбы света, силуэты гор у горизонта. Всё без теней и коллизий.
func _build_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var stone := _stone(Color(0.30, 0.30, 0.34), 0.8, 0.12, 0.6)
	var dark := _stone(Color(0.12, 0.12, 0.15), 0.9, 0.08, 0.8)

	# Свет над зоной ворот: центр — освещённая «сцена», даль тонет в полутьме
	var spot := SpotLight3D.new()
	spot.position = Vector3(0, 95.0, 6.0)
	spot.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	spot.spot_range = 150.0
	spot.spot_angle = 32.0
	spot.spot_angle_attenuation = 1.6
	spot.light_energy = 1.4
	spot.light_color = Color(1.0, 0.9, 0.78)
	_decor.add_child(spot)

	# Кристаллы стихий — средний план вокруг ворот (дают масштаб существам и шару)
	for k in range(6):
		var a: float = TAU * (k + 0.5) / 6.0
		var r: float = 72.0 + 6.0 * (k % 2)
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
		var gr: float = rng.randf_range(125.0, 200.0)
		var gc := Vector3(cos(ga) * gr, 0.0, sin(ga) * gr)
		var s: float = rng.randf_range(2.2, 3.4)
		for c in range(rng.randi_range(3, 5)):
			var off := Vector3(rng.randf_range(-14, 14), 0, rng.randf_range(-14, 14))
			var h: float = rng.randf_range(6.0, 26.0) * (1.0 if c > 0 else 1.4)
			_static(col_mesh, stone, gc + off + Vector3(0, h * 0.5 - 0.5, 0), Vector3(s, h, s),
				Vector3(rng.randf_range(-0.12, 0.12), rng.randf() * TAU, rng.randf_range(-0.12, 0.12)))
		# перекладина-арка на двух колоннах
		if g % 2 == 0:
			var span: float = rng.randf_range(14.0, 20.0)
			var yaw: float = rng.randf() * TAU
			var axis := Vector3(cos(yaw), 0, sin(yaw))
			for side in [-1.0, 1.0]:
				_static(col_mesh, stone, gc + axis * span * 0.5 * side + Vector3(0, 11.0, 0), Vector3(s, 23.0, s), Vector3.ZERO)
			_static(block, dark, gc + Vector3(0, 23.5, 0), Vector3(span + s * 3.0, 3.0, s * 2.4), Vector3(0.0, -yaw, rng.randf_range(-0.08, 0.08)))
		# обвалившиеся блоки
		for b in range(4):
			var bp := gc + Vector3(rng.randf_range(-18, 18), 1.0, rng.randf_range(-18, 18))
			var bs := Vector3(rng.randf_range(3, 8), rng.randf_range(2, 4), rng.randf_range(3, 7))
			_static(block, dark, bp, bs, Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3)))

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
		var r: float = rng.randf_range(150.0, 340.0)
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
		var ms := Vector3(rng.randf_range(140.0, 260.0), mh, rng.randf_range(120.0, 220.0))
		_static(mount, mmat, Vector3(cos(a) * r, mh * 0.5 - 10.0, sin(a) * r), ms, Vector3(0.0, rng.randf() * TAU, 0.0))
	_flush_static()


## Шесть святилищ стихий обрамляют поле; декор за пределами траекторий броска.
func _build_sanctuary() -> void:
	var stone := _stone(Color(0.24, 0.29, 0.34), 0.9, 0.15, 0.3)
	for i in range(6):
		var a: float = TAU * (float(i) + 0.5) / 6.0
		var center := Vector3(cos(a) * 103.0, 0, sin(a) * 103.0)
		var color := VisualUtil.attr_color(i).lightened(0.15)
		var glow := _glow_mat(color, 1.15)
		var base := CylinderMesh.new()
		base.top_radius = 7.0
		base.bottom_radius = 8.2
		base.height = 0.8
		base.radial_segments = 12
		_mi(base, stone, center + Vector3(0, 0.4, 0))
		var ring := TorusMesh.new()
		ring.inner_radius = 5.5
		ring.outer_radius = 5.75
		ring.rings = 32
		ring.ring_segments = 6
		_mi(ring, glow, center + Vector3(0, 0.9, 0))
		var tangent := Vector3(-sin(a), 0, cos(a))
		for side in [-1.0, 1.0]:
			var pillar := BoxMesh.new()
			pillar.size = Vector3(2.4, 14.0, 2.4)
			var pos: Vector3 = center + tangent * side * 5.8 + Vector3(0, 7.4, 0)
			var mi := _mi(pillar, stone, pos)
			mi.rotation.y = -a
			var rune := BoxMesh.new()
			rune.size = Vector3(0.18, 10.0, 2.5)
			var line := _mi(rune, glow, pos)
			line.rotation.y = -a
		var lintel := BoxMesh.new()
		lintel.size = Vector3(14.0, 1.4, 3.0)
		var top := _mi(lintel, stone, center + Vector3(0, 14.7, 0))
		top.rotation.y = -a
		_crystal(center + Vector3(0, 2.4, 0), color, 5.5, 700 + i, false)
