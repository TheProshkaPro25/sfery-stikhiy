class_name MenuCity
extends Node3D
## Живой пейзаж главного меню: город у реки с видом с холма. Всё процедурно: небоскрёбы и дома — один MultiMesh
## единичных кубов (окна, неон, огни — в building.gdshader), крыши частных домов и деревья — ещё по MultiMesh,
## дороги и мосты — MultiMesh плоскостей (разметка и фонари — road.gdshader), вода, земля, горы-силуэты, небо
## с облаками. Транспорт (машины, метро, лодки, самолёт, вертолёт) — MenuTraffic, шары стихий в полночь — MenuOrbs. Цикл суток DayCycle.CYCLE_SEC: солнце/луна по дуге, свет, туман, окна и машины по времени.
## Точечных источников света нет — все огни эмиссией; тени — только от одного DirectionalLight3D.

const RIVER_FAR := 20.0      # z дальней набережной (город)
const RIVER_NEAR := 125.0    # z ближней набережной (холм с камерой)
const CITY_Y := 1.5
const CITY := Vector4(60.0, -420.0, 840.0, 520.0)   # центр xz и полуоси эллипса города
const DOWNTOWN := Vector2(150.0, -260.0)
const UPTOWN := Vector2(-330.0, -560.0)
const BRIDGES := [-190.0, 290.0]
const STREET_X := 70.0       # шаг улиц вдоль x
const STREET_Z := 62.0       # шаг улиц вдоль z
const SEA_X := -780.0        # левее — залив
const CAM_POS := Vector3(-60.0, 46.0, 265.0)
const CAM_LOOK := Vector3(110.0, 52.0, -320.0)

## Фаза суток 0..1 (см. DayCycle); paused — фаза стоит (снимки tools/menu_shots.gd).
var phase := DayCycle.START_PHASE
var paused := false
var anim_t := 0.0
var quality := GraphicsSettings.Level.HIGH

var env: Environment
var sun: DirectionalLight3D
var cam: Camera3D
var _sky_mat: ShaderMaterial
var _bld_mat: ShaderMaterial
var _road_mat: ShaderMaterial
var _water_mat: ShaderMaterial
var _terrain_mat: ShaderMaterial
var _mount_mat: ShaderMaterial
var traffic: MenuTraffic
var orbs: MenuOrbs
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _parallax := Vector2.ZERO
var _tree_mat: ShaderMaterial
var _tower_mat: ShaderMaterial
var _tree_mis: Array[MultiMeshInstance3D] = []
var _tree_far_mi: MultiMeshInstance3D

# накопители инстансов: [Transform3D, Color(custom)]
var _bld: Array = []
var _roads: Array = []
var _roofs: Array = []
var _trees: Array = []        # [Transform3D, Color, вид кроны 0..2]
var _towers: Array = []       # водобашни на крышах
var _road_specs: Array = []   # для MenuTraffic: [a, b, ширина, полос, y, скорость]


func _ready() -> void:
	_rng.seed = 20261028
	_noise.seed = 7
	_noise.frequency = 0.0022
	_noise.fractal_octaves = 4
	_build_env()
	_build_terrain()
	_build_water()
	_build_city()
	_build_river_and_bridges()
	_build_near_bank()
	_flush_multimeshes()
	_build_mountains()
	traffic = MenuTraffic.new()
	traffic.name = "Traffic"
	add_child(traffic)
	traffic.build(_road_specs, CAM_POS)
	_road_specs.clear()
	orbs = MenuOrbs.new()
	orbs.name = "Orbs"
	add_child(orbs)
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.near = 1.0
	cam.far = 9000.0
	add_child(cam)
	cam.current = true
	apply_quality(GraphicsSettings.current())
	_update(0.0)


func _process(delta: float) -> void:
	_update(delta)


## Уровень графики: тени, glow, детализация неба, MSAA (через GraphicsSettings.apply_world без SSAO).
func apply_quality(level: int) -> void:
	quality = level
	GraphicsSettings.apply_world(get_viewport(), null, null)
	var low := level == GraphicsSettings.Level.LOW
	sun.shadow_enabled = not low
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 1400.0 if level == GraphicsSettings.Level.HIGH else 1000.0
	env.glow_enabled = not low
	_sky_mat.set_shader_parameter("detail", 0.0 if low else 1.0)
	traffic.apply_quality(level)
	orbs.apply_quality(level)
	if _tree_far_mi != null:
		_tree_far_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for mi in _tree_mis:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if low else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


# ---------------------------------------------------------------- цикл суток

func _update(delta: float) -> void:
	anim_t += delta
	if not paused:
		phase = fposmod(phase + delta / DayCycle.CYCLE_SEC, 1.0)
	var s := DayCycle.state(phase)
	var night: float = s.night
	var zen: Color = s.zenith
	var hor: Color = s.horizon
	_sky_mat.set_shader_parameter("zenith_col", zen)
	_sky_mat.set_shader_parameter("horizon_col", hor)
	_sky_mat.set_shader_parameter("glow_col", s.glow)
	_sky_mat.set_shader_parameter("sun_col", s.sun_color)
	_sky_mat.set_shader_parameter("sun_dir", s.sun_dir)
	_sky_mat.set_shader_parameter("moon_dir", s.moon_dir)
	_sky_mat.set_shader_parameter("night", night)
	_sky_mat.set_shader_parameter("day", s.day)
	_sky_mat.set_shader_parameter("anim_t", anim_t)
	_sky_mat.set_shader_parameter("cover", s.cover)

	var ld: Vector3 = s.light_dir
	sun.look_at_from_position(Vector3.ZERO, -ld, Vector3.UP if absf(ld.y) < 0.99 else Vector3.FORWARD)
	sun.light_color = s.light_color
	sun.light_energy = s.light_energy
	sun.visible = s.light_energy > 0.002

	env.tonemap_exposure = s.exposure
	env.ambient_light_energy = lerpf(0.35, 1.5, night)
	env.fog_light_color = hor.lerp(zen, 0.3)
	env.fog_density = lerpf(0.00022, 0.00034, night)
	env.glow_intensity = lerpf(0.35, 0.85, night)

	for m: ShaderMaterial in [_bld_mat, _road_mat, _water_mat]:
		m.set_shader_parameter("night", night)
		m.set_shader_parameter("anim_t", anim_t)
	_bld_mat.set_shader_parameter("win_on", s.windows)
	_bld_mat.set_shader_parameter("sky_tint", hor.lerp(zen, 0.5))
	_water_mat.set_shader_parameter("win_on", s.windows)
	_water_mat.set_shader_parameter("deep_col", Color(0.02, 0.05, 0.07).lerp(zen * 0.25, 0.5))
	_terrain_mat.set_shader_parameter("night", night)
	_mount_mat.set_shader_parameter("horizon_col", hor.lerp(s.glow, 0.15))
	_mount_mat.set_shader_parameter("zenith_col", zen)
	_mount_mat.set_shader_parameter("light_col", s.sun_color)
	_mount_mat.set_shader_parameter("day", s.day)
	_mount_mat.set_shader_parameter("night", night)
	_tree_mat.set_shader_parameter("anim_t", anim_t)
	_tower_mat.set_shader_parameter("night", night)
	traffic.update(anim_t, night, s.traffic, _water_mat)
	orbs.update(phase, anim_t, _water_mat)
	_update_camera(delta)


## Камера медленно дрейфует по дуге, мышь слегка сдвигает взгляд (параллакс).
func _update_camera(delta: float) -> void:
	var vp := get_viewport()
	if vp != null and vp.get_visible_rect().size.x > 0.0:
		var mp := vp.get_mouse_position() / vp.get_visible_rect().size - Vector2(0.5, 0.5)
		_parallax = _parallax.lerp(mp.clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5)), clampf(delta * 1.5, 0.0, 1.0))
	var t := anim_t
	var off := Vector3(sin(t * 0.043) * 16.0, sin(t * 0.031) * 4.0, sin(t * 0.027 + 1.0) * 10.0)
	var look := CAM_LOOK + Vector3(sin(t * 0.037) * 24.0 + _parallax.x * 40.0, -_parallax.y * 18.0, 0.0)
	cam.look_at_from_position(CAM_POS + off + Vector3(_parallax.x * 6.0, 0.0, 0.0), look)


# ---------------------------------------------------------------- окружение

func _build_env() -> void:
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load("res://scenes/menu/city_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_256   # realtime-небо принимает только 256
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_intensity = 0.6
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for lv in range(7):
		env.set_glow_level(lv, 1.0 if lv in [1, 2, 3, 4] else 0.0)
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.0003
	env.fog_aerial_perspective = 0.8
	env.fog_sky_affect = 0.0
	env.fog_height = 4.0          # низкая дымка над водой
	env.fog_height_density = 0.004
	env.ssao_enabled = false
	env.ssr_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.shadow_blur = 1.0
	sun.light_angular_distance = 0.5
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 1.5
	sun.directional_shadow_blend_splits = true
	add_child(sun)


# ---------------------------------------------------------------- рельеф

## Высота земли: ровный город, русло реки, холм у камеры, холмы за городом, залив слева.
func height_at(x: float, z: float) -> float:
	var h := CITY_Y
	var n := _noise.get_noise_2d(x, z)
	# холм у камеры
	if z > RIVER_NEAR + 15.0:
		var k := (z - RIVER_NEAR - 15.0) / 190.0
		h += pow(k, 1.5) * 42.0 + n * 14.0 * clampf(k, 0.0, 1.0)
	# холмы за городом
	var ce := Vector2((x - CITY.x) / (CITY.z + 160.0), (z - CITY.y) / (CITY.w + 160.0)).length()
	if z < RIVER_FAR:
		h += smoothstep(1.0, 1.9, ce) * (90.0 + n * 70.0) + maxf(ce - 1.9, 0.0) * 60.0
	# река
	var river := smoothstep(RIVER_FAR - 6.0, RIVER_FAR + 4.0, z) * (1.0 - smoothstep(RIVER_NEAR - 4.0, RIVER_NEAR + 6.0, z))
	h = lerpf(h, -5.0, river)
	# залив
	var coast := SEA_X + n * 90.0 - maxf(z - RIVER_NEAR, 0.0) * 0.6
	h = lerpf(h, -8.0, smoothstep(coast + 60.0, coast - 60.0, x))
	return h


func _build_terrain() -> void:
	var nx := 240
	var nz := 170
	var x0 := -3200.0
	var x1 := 3200.0
	var z0 := -3000.0
	var z1 := 700.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hs := PackedFloat32Array()
	hs.resize((nx + 1) * (nz + 1))
	for j in range(nz + 1):
		for i in range(nx + 1):
			var x := lerpf(x0, x1, float(i) / nx)
			var z := lerpf(z0, z1, _zgrid(float(j) / nz))
			hs[j * (nx + 1) + i] = height_at(x, z)
	for j in range(nz + 1):
		for i in range(nx + 1):
			var x := lerpf(x0, x1, float(i) / nx)
			var z := lerpf(z0, z1, _zgrid(float(j) / nz))
			st.add_vertex(Vector3(x, hs[j * (nx + 1) + i], z))
	for j in range(nz):
		for i in range(nx):
			var a := j * (nx + 1) + i
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + nx + 1)
			st.add_index(a + 1)
			st.add_index(a + nx + 2)
			st.add_index(a + nx + 1)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	_terrain_mat = ShaderMaterial.new()
	_terrain_mat.shader = load("res://scenes/menu/terrain.gdshader")
	_terrain_mat.set_shader_parameter("city", CITY)
	mi.material_override = _terrain_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Сетка по z гуще у реки и холма (там, где рельеф виден вблизи).
func _zgrid(t: float) -> float:
	return pow(t, 0.75)


func _build_water() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(9000, 9000)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = load("res://scenes/menu/water.gdshader")
	_water_mat.set_shader_parameter("cam_ground", Vector3(CAM_POS.x, 0.0, CAM_POS.z))
	_water_mat.set_shader_parameter("shore_z", RIVER_FAR)
	_water_mat.set_shader_parameter("bridges", Vector2(BRIDGES[0], BRIDGES[1]))
	mi.material_override = _water_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ---------------------------------------------------------------- город

func _in_city(x: float, z: float, margin: float = 0.0) -> bool:
	var q := Vector2((x - CITY.x) / (CITY.z - margin), (z - CITY.y) / (CITY.w - margin))
	return q.length() < 1.0 and z < RIVER_FAR - 12.0 and x > SEA_X + 70.0


func _add_box(pos: Vector3, size: Vector3, kind: int, seed_v: float, flags: int = 0, hue: float = 0.0, basis: Basis = Basis.IDENTITY) -> void:
	var b := basis * Basis.from_scale(size)
	_bld.append([Transform3D(b, pos + basis.y * size.y * 0.5), Color(seed_v, kind, flags, hue)])


func _add_road(a: Vector2, b: Vector2, width: float, lanes: int, y: float, speed: float = 1.0) -> void:
	var d := b - a
	var len := d.length()
	if len < 5.0:
		return
	var ang := -atan2(d.y, d.x)
	var basis := Basis(Vector3.UP, ang) * Basis.from_scale(Vector3(len, 1.0, width))
	var mid := (a + b) * 0.5
	_roads.append([Transform3D(basis, Vector3(mid.x, y, mid.y)), Color(len, _rng.randf(), lanes, speed)])
	_road_specs.append([a, b, width, lanes, y, speed])


## Отрезок прямой внутри эллипса города: по x (horizontal=true, z фиксирован) или по z.
func _city_span(coord: float, horizontal: bool) -> Vector2:
	var q := (coord - (CITY.y if horizontal else CITY.x)) / (CITY.w if horizontal else CITY.z)
	if absf(q) >= 1.0:
		return Vector2.ZERO
	var half := sqrt(1.0 - q * q) * (CITY.z if horizontal else CITY.w)
	var c: float = CITY.x if horizontal else CITY.y
	var lo := c - half
	var hi := c + half
	if horizontal:
		lo = maxf(lo, SEA_X + 70.0)
	else:
		hi = minf(hi, RIVER_FAR - 8.0)
	return Vector2(lo, hi)


func _tower_height(x: float, z: float) -> float:
	var d1 := Vector2(x, z).distance_to(DOWNTOWN)
	var d2 := Vector2(x, z).distance_to(UPTOWN)
	var core := exp(-pow(d1 / 230.0, 2.0)) * 1.0 + exp(-pow(d2 / 170.0, 2.0)) * 0.55
	var r := _rng.randf()
	var h := lerpf(12.0, 40.0, r * r) + core * lerpf(40.0, 250.0, pow(_rng.randf(), 1.4))
	# у набережной ниже, но пара высоток всё-таки есть
	if z > -60.0:
		h *= 0.75
	if _rng.randf() < 0.025:
		h += _rng.randf_range(60.0, 140.0)
	return h


func _build_city() -> void:
	var xs: Array[float] = []
	var x := SEA_X + 70.0
	while x < CITY.x + CITY.z:
		xs.append(x)
		x += STREET_X
	var zs: Array[float] = []
	var z := RIVER_FAR - 12.0
	while z > CITY.y - CITY.w:
		zs.append(z)
		z -= STREET_Z
	# улицы: каждая 4-я — проспект в две полосы
	for i in range(xs.size()):
		var span := _city_span(xs[i], false)
		if span != Vector2.ZERO:
			var avenue := i % 4 == 1 or BRIDGES.has(xs[i])
			_add_road(Vector2(xs[i], span.x), Vector2(xs[i], span.y), 16.0 if avenue else 10.0, 2 if avenue else 1, CITY_Y + 0.12, 1.2 if avenue else 0.9)
	for j in range(zs.size()):
		var span := _city_span(zs[j], true)
		if span != Vector2.ZERO:
			var avenue := j % 3 == 0
			_add_road(Vector2(span.x, zs[j]), Vector2(span.y, zs[j]), 16.0 if avenue else 10.0, 2 if avenue else 1, CITY_Y + 0.14, 1.2 if avenue else 0.9)
	# кварталы
	for i in range(xs.size() - 1):
		for j in range(zs.size() - 1):
			var bx0 := xs[i] + 8.0
			var bx1 := xs[i + 1] - 8.0
			var bz0 := zs[j] - 8.0
			var bz1 := zs[j + 1] + 8.0
			var cx := (bx0 + bx1) * 0.5
			var cz := (bz0 + bz1) * 0.5
			if not _in_city(cx, cz, 30.0):
				continue
			_fill_block(bx0, bx1, bz1, bz0)


## Квартал [x0..x1] × [z0..z1] → 1–4 участка, на каждом дом (у высоток — уступы, надстройки, антенны).
func _fill_block(x0: float, x1: float, z0: float, z1: float) -> void:
	var nx := _rng.randi_range(1, 2)
	var nz := _rng.randi_range(1, 2)
	var w := (x1 - x0) / nx
	var d := (z1 - z0) / nz
	for i in range(nx):
		for j in range(nz):
			if _rng.randf() < 0.06:
				continue   # пустырь/площадь
			var lx := x0 + i * w
			var lz := z0 + j * d
			var mx := _rng.randf_range(1.5, 5.0)
			var mz := _rng.randf_range(1.5, 5.0)
			var bw := w - mx * 2.0
			var bd := d - mz * 2.0
			var cx := lx + w * 0.5
			var cz := lz + d * 0.5
			var h := _tower_height(cx, cz)
			if h > 70.0:
				bw = minf(bw, _rng.randf_range(22.0, 34.0))
				bd = minf(bd, _rng.randf_range(22.0, 34.0))
			_add_building(Vector3(cx, CITY_Y, cz), bw, bd, h)


func _add_building(base: Vector3, w: float, d: float, h: float) -> void:
	var seed_v := _rng.randf()
	var kind := 2
	var r := _rng.randf()
	if h > 110.0:
		kind = 0 if r < 0.5 else (3 if r < 0.8 else 1)
	elif h > 40.0:
		kind = 1 if r < 0.4 else (0 if r < 0.65 else 2)
	else:
		kind = 2 if r < 0.7 else 1
	var flags := 0
	var dist_dt := Vector2(base.x, base.z).distance_to(DOWNTOWN)
	if h > 18.0 and h < 100.0 and _rng.randf() < (0.22 if dist_dt < 450.0 else 0.08):
		flags |= 1
	if h > 95.0 and _rng.randf() < 0.45:
		flags |= 2
	if h > 140.0 and _rng.randf() < 0.3:
		flags |= 4
	if h > 75.0:
		flags |= 8
	var hue := _rng.randf()
	# уступы у высоток
	if h > 90.0 and _rng.randf() < 0.6:
		var h1 := h * _rng.randf_range(0.5, 0.7)
		_add_box(base, Vector3(w, h1, d), kind, seed_v, flags & 1, hue)
		var w2 := w * _rng.randf_range(0.6, 0.8)
		var d2 := d * _rng.randf_range(0.6, 0.8)
		_add_box(base + Vector3(0, h1, 0), Vector3(w2, h - h1, d2), kind, seed_v + 0.37, flags & ~1, hue)
		w = w2
		d = d2
	else:
		_add_box(base, Vector3(w, h, d), kind, seed_v, flags, hue)
	var top := base + Vector3(0, h, 0)
	# водобашня на крыше старого жилого дома
	if kind == 2 and h > 16.0 and h < 90.0 and minf(w, d) > 12.0 and _rng.randf() < 0.28:
		var ts := _rng.randf_range(0.8, 1.2)
		var tp := top + Vector3(_rng.randf_range(-0.25, 0.25) * w, 0.0, _rng.randf_range(-0.25, 0.25) * d)
		_towers.append([Transform3D(Basis(Vector3.UP, _rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * ts), tp), Color(0, 0, 0, 0)])
	# надстройки на крыше
	for k in range(_rng.randi_range(0, 3 if h > 30.0 else 1)):
		var sw := _rng.randf_range(2.0, minf(w, d) * 0.4)
		var sh := _rng.randf_range(1.5, 5.0)
		_add_box(top + Vector3(_rng.randf_range(-w, w) * 0.3, 0, _rng.randf_range(-d, d) * 0.3), Vector3(sw, sh, sw * _rng.randf_range(0.6, 1.4)), 4, _rng.randf())
	# антенна-шпиль у высоких
	if h > 120.0 and _rng.randf() < 0.6:
		var ah := _rng.randf_range(15.0, 45.0)
		_add_box(top, Vector3(1.2, ah, 1.2), 5, _rng.randf())
	elif h > 50.0 and _rng.randf() < 0.3:
		_add_box(top + Vector3(w * 0.25, 0, -d * 0.2), Vector3(0.5, _rng.randf_range(6.0, 12.0), 0.5), 5, _rng.randf())


# ---------------------------------------------------------------- река, набережные, мосты

func _build_river_and_bridges() -> void:
	var xl := SEA_X - 40.0
	var xr := 2400.0
	# стенки набережных
	_add_box(Vector3((xl + xr) * 0.5, -3.0, RIVER_FAR - 1.0), Vector3(xr - xl, CITY_Y + 3.3, 3.0), 7, 0.1)
	_add_box(Vector3((xl + xr) * 0.5, -3.0, RIVER_NEAR + 1.0), Vector3(xr - xl, CITY_Y + 3.3, 3.0), 7, 0.2)
	# дороги вдоль реки: набережная города и шоссе на нашем берегу
	_add_road(Vector2(SEA_X + 40.0, RIVER_FAR - 6.0), Vector2(xr, RIVER_FAR - 6.0), 13.0, 2, CITY_Y + 0.15, 1.1)
	_add_road(Vector2(SEA_X - 20.0, RIVER_NEAR + 11.0), Vector2(xr, RIVER_NEAR + 11.0), 18.0, 3, CITY_Y + 0.15, 1.5)
	_build_metro()
	for bi in range(BRIDGES.size()):
		var bx: float = BRIDGES[bi]
		var deck_y := 13.0
		var z0 := RIVER_FAR - 30.0
		var z1 := RIVER_NEAR + 32.0
		_add_road(Vector2(bx, z1 + 40.0), Vector2(bx, z0 - 25.0), 18.0, 2, deck_y + 0.6, 1.3)
		_add_box(Vector3(bx, deck_y - 1.6, (z0 + z1) * 0.5 - 10.0), Vector3(20.0, 2.2, z1 - z0 + 90.0), 7, 0.3)
		# перила-бортики
		for sx in [-1.0, 1.0]:
			_add_box(Vector3(bx + sx * 9.6, deck_y + 0.6, (z0 + z1) * 0.5 - 10.0), Vector3(0.6, 1.0, z1 - z0 + 90.0), 7, 0.4)
		# опоры
		for zp in [RIVER_FAR + 25.0, RIVER_NEAR - 25.0, RIVER_FAR - 25.0, RIVER_NEAR + 30.0]:
			_add_box(Vector3(bx, -4.0, zp), Vector3(8.0, deck_y + 2.4, 5.0), 7, 0.5)
		if bi == 1:
			# вантовый мост: пилон и ванты
			var zc := (RIVER_FAR + RIVER_NEAR) * 0.5
			var ph := 75.0
			for sx in [-1.0, 1.0]:
				_add_box(Vector3(bx + sx * 11.0, deck_y - 1.0, zc), Vector3(2.6, ph, 3.4), 8, 0.6)
			_add_box(Vector3(bx, deck_y + ph * 0.72, zc), Vector3(24.0, 2.5, 3.0), 8, 0.7)
			for sx in [-1.0, 1.0]:
				for k in range(7):
					for dir in [-1.0, 1.0]:
						var top := Vector3(bx + sx * 11.0, deck_y + ph * (0.62 + k * 0.045), zc)
						var foot := Vector3(bx + sx * 9.5, deck_y + 0.5, zc + dir * (18.0 + k * 11.0))
						var v := top - foot
						_add_box(foot, Vector3(0.25, v.length(), 0.25), 8, 0.8, 0, 0.0, _basis_along(v.normalized()))


## Эстакада метро над водой у городской набережной: настил, бортики, опоры в воде (поезда — MenuTraffic).
## Настил ниже пролётов мостов — поезд проходит под ними.
func _build_metro() -> void:
	var z := MenuTraffic.RAIL_Z
	var y := MenuTraffic.RAIL_Y
	var x0: float = MenuTraffic.RAIL_X.x
	var x1: float = MenuTraffic.RAIL_X.y
	_add_box(Vector3((x0 + x1) * 0.5, y - 1.3, z), Vector3(x1 - x0, 1.3, 9.4), 7, 0.15)
	for sz in [-1.0, 1.0]:
		_add_box(Vector3((x0 + x1) * 0.5, y, z + sz * 4.5), Vector3(x1 - x0, 0.9, 0.4), 7, 0.25)
	var x := x0 + 20.0
	while x < x1 - 10.0:
		var near_bridge := false
		for bx: float in BRIDGES:
			near_bridge = near_bridge or absf(x - bx) < 14.0
		if not near_bridge:
			_add_box(Vector3(x, -4.0, z), Vector3(2.4, y + 2.7 - 1.3, 3.2), 7, 0.5)
			_add_box(Vector3(x, y - 2.6, z), Vector3(3.0, 1.3, 8.0), 7, 0.55)   # ригель под настилом
		x += 42.0


## Базис, у которого ось Y смотрит вдоль dir (для тонких балок-вант).
func _basis_along(dir: Vector3) -> Basis:
	var side := dir.cross(Vector3.RIGHT)
	if side.length() < 0.01:
		side = dir.cross(Vector3.FORWARD)
	side = side.normalized()
	var fwd := side.cross(dir).normalized()
	return Basis(fwd, dir, side).orthonormalized()


# ---------------------------------------------------------------- наш берег: холм, домики, деревья

func _build_near_bank() -> void:
	for k in range(260):
		var x := _rng.randf_range(-900.0, 900.0)
		var z := _rng.randf_range(RIVER_NEAR + 30.0, 330.0)
		# коридор обзора перед камерой без домов
		if absf(x - CAM_POS.x) < 140.0 and z > 200.0 or Vector2(x, z).distance_to(Vector2(CAM_POS.x, CAM_POS.z)) < 220.0:
			continue
		var y := height_at(x, z)
		if y < 1.0:
			continue
		if _rng.randf() < 0.45:
			var w := _rng.randf_range(8.0, 13.0)
			var d := _rng.randf_range(7.0, 11.0)
			var hh := _rng.randf_range(3.5, 7.0)
			var basis := Basis(Vector3.UP, _rng.randf_range(-0.2, 0.2))
			_add_box(Vector3(x, y - 1.0, z), Vector3(w, hh + 1.0, d), 6, _rng.randf(), 0, 0.0, basis)
			var roof_c: Color = [Color(0.45, 0.18, 0.12), Color(0.25, 0.26, 0.30), Color(0.35, 0.22, 0.16)][_rng.randi() % 3]
			_roofs.append([Transform3D(basis * Basis.from_scale(Vector3(w + 1.0, _rng.randf_range(2.5, 4.0), d + 1.0)), Vector3(x, y + hh, z) + basis.y * 1.6), roof_c])
	# деревья по склону и вдоль шоссе
	for k in range(5200):
		var x := _rng.randf_range(-1200.0, 1200.0)
		var z := _rng.randf_range(RIVER_NEAR + 24.0, 420.0)
		var y := height_at(x, z)
		if y < 1.0 or (absf(x - CAM_POS.x) < 30.0 and absf(z - CAM_POS.z) < 30.0):
			continue
		# у шоссе реже, выше по склону — сплошной лес
		if _rng.randf() > smoothstep(RIVER_NEAR + 20.0, RIVER_NEAR + 70.0, z):
			continue
		var s := _rng.randf_range(6.0, 13.0)
		_trees.append(_tree_item(x, y - 0.4, z, s, 0 if _rng.randf() < 0.62 else 1))
	# деревья на холмах за городом (дальний лес)
	for k in range(1600):
		var x := _rng.randf_range(-1600.0, 1800.0)
		var z := _rng.randf_range(-1700.0, -200.0)
		if _in_city(x, z, -60.0):
			continue
		var y := height_at(x, z)
		if y < 3.0:
			continue
		var s := _rng.randf_range(8.0, 16.0)
		_trees.append(_tree_item(x, y - 1.0, z, s, 2))


## Дерево: вид 0 — лиственное (крона из шаров), 1 — ель (шары сужаются кверху), 2 — дальнее (2 шара).
## Цвет: тёмная хвоя / разная листва, изредка желтеющие и красноватые кроны; a — вид.
func _tree_item(x: float, y: float, z: float, s: float, kind: int) -> Array:
	var c: Color
	if kind == 1:
		c = Color(0.04, 0.09, 0.06).lerp(Color(0.07, 0.14, 0.08), _rng.randf())
	else:
		c = Color(0.07, 0.13, 0.05).lerp(Color(0.16, 0.22, 0.07), _rng.randf())
		var r := _rng.randf()
		if r < 0.07:
			c = c.lerp(Color(0.42, 0.34, 0.08), 0.6)
		elif r < 0.11:
			c = c.lerp(Color(0.40, 0.14, 0.06), 0.5)
	var w := s * (0.42 if kind == 1 else _rng.randf_range(0.55, 0.75))
	var basis := Basis(Vector3.UP, _rng.randf() * TAU) * Basis.from_scale(Vector3(w, s, w))
	return [Transform3D(basis, Vector3(x, y, z)), Color(c.r, c.g, c.b, kind)]


# ---------------------------------------------------------------- сборка MultiMesh

func _flush_multimeshes() -> void:
	var box := BoxMesh.new()
	_bld_mat = ShaderMaterial.new()
	_bld_mat.shader = load("res://scenes/menu/building.gdshader")
	_make_mm(box, _bld, _bld_mat, true, true)

	var plane := PlaneMesh.new()
	plane.size = Vector2(1, 1)
	_road_mat = ShaderMaterial.new()
	_road_mat.shader = load("res://scenes/menu/road.gdshader")
	_make_mm(plane, _roads, _road_mat, true, false)

	var prism := PrismMesh.new()
	prism.size = Vector3(1, 1, 1)
	var roof_mat := StandardMaterial3D.new()
	roof_mat.vertex_color_use_as_albedo = true
	roof_mat.roughness = 0.85
	_make_mm(prism, _roofs, roof_mat, false, true)

	_tree_mat = ShaderMaterial.new()
	_tree_mat.shader = load("res://scenes/menu/tree.gdshader")
	var meshes := _tree_meshes()
	for kind in range(3):
		var part: Array = []
		for it: Array in _trees:
			if int(it[1].a) == kind:
				part.append(it)
		var mi := _make_mm(meshes[kind], part, _tree_mat, true, kind != 2)
		if kind == 2:
			_tree_far_mi = mi
		else:
			_tree_mis.append(mi)

	_tower_mat = ShaderMaterial.new()
	_tower_mat.shader = load("res://scenes/menu/vehicle.gdshader")
	_make_mm(_tower_mesh(), _towers, _tower_mat, true, true)
	_towers.clear()
	_bld.clear()
	_roads.clear()
	_trees.clear()
	_roofs.clear()


## Кроны в единицах: высота дерева 1, ширина 1 (масштаб инстанса — (ширина, высота, ширина)).
func _tree_meshes() -> Array[ArrayMesh]:
	var out: Array[ArrayMesh] = []
	var k := MenuTraffic.MeshKit.new()
	k.box(Vector3(-0.035, 0.0, -0.035), Vector3(0.035, 0.42, 0.035), 1)
	k.shade = 0.5
	k.ico(Vector3(0.0, 0.62, 0.0), Vector3(0.36, 0.27, 0.36), 0)
	k.shade = 0.15
	k.ico(Vector3(0.2, 0.5, 0.12), Vector3(0.27, 0.21, 0.27), 0)
	k.shade = 0.85
	k.ico(Vector3(-0.14, 0.78, -0.1), Vector3(0.25, 0.2, 0.25), 0)
	k.shade = 0.3
	k.ico(Vector3(-0.18, 0.5, 0.2), Vector3(0.22, 0.18, 0.22), 0)
	out.append(k.commit())
	k = MenuTraffic.MeshKit.new()
	k.box(Vector3(-0.04, 0.0, -0.04), Vector3(0.04, 0.25, 0.04), 1)
	var lv := [[0.3, 0.5, 0.2], [0.52, 0.38, 0.6], [0.72, 0.25, 0.4], [0.88, 0.13, 0.9]]
	for l: Array in lv:
		k.shade = l[2]
		k.ico(Vector3(0.0, l[0], 0.0), Vector3(l[1], 0.16, l[1]), 0)
	out.append(k.commit())
	k = MenuTraffic.MeshKit.new()
	k.shade = 0.35
	k.ico(Vector3(0.0, 0.45, 0.0), Vector3(0.45, 0.4, 0.45), 0)
	k.shade = 0.8
	k.ico(Vector3(0.1, 0.75, 0.05), Vector3(0.3, 0.24, 0.3), 0)
	out.append(k.commit())
	return out


## Водобашня на крыше: опоры, деревянный бак-восьмигранник, конус крыши. Части — как у vehicle.gdshader.
func _tower_mesh() -> ArrayMesh:
	var k := MenuTraffic.MeshKit.new()
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			k.box(Vector3(sx * 1.4 - 0.12, 0.0, sz * 1.4 - 0.12), Vector3(sx * 1.4 + 0.12, 3.0, sz * 1.4 + 0.12), 6)
	k.box(Vector3(-1.7, 2.8, -1.7), Vector3(1.7, 3.05, 1.7), 6)
	var ring: Array = []
	var top: Array = []
	for i in range(8):
		var a := TAU * i / 8.0
		ring.append(Vector3(cos(a) * 1.9, 3.05, sin(a) * 1.9))
	k.prism(ring, Vector3(0, 4.2, 0), 7)
	for i in range(8):
		var a := TAU * i / 8.0
		top.append(Vector3(cos(a) * 2.05, 7.25, sin(a) * 2.05))
	var apex := Vector3(0, 9.0, 0)
	for i in range(8):
		k.tri(top[i], top[(i + 1) % 8], apex, 6, Vector3(0, 7.6, 0))
	return k.commit()


## items: [Transform3D, Color]; custom=true — цвет идёт в INSTANCE_CUSTOM, иначе в цвет инстанса (COLOR).
func _make_mm(mesh: Mesh, items: Array, mat: Material, custom: bool, shadows: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = custom
	mm.use_colors = not custom
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in range(items.size()):
		mm.set_instance_transform(i, items[i][0])
		if custom:
			mm.set_instance_custom_data(i, items[i][1])
		else:
			mm.set_instance_color(i, items[i][1])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


# ---------------------------------------------------------------- горы

func _build_mountains() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ridge := FastNoiseLite.new()
	ridge.seed = 31
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 5
	ridge.frequency = 1.6
	var layers := [[2600.0, 260.0, 0.0], [3400.0, 420.0, 0.5], [4400.0, 650.0, 1.0]]
	var center := Vector3(CAM_POS.x, 0.0, CAM_POS.z)
	for li in range(layers.size()):
		var R: float = layers[li][0]
		var amp: float = layers[li][1]
		var lay: float = layers[li][2]
		var n := 260
		var a0 := deg_to_rad(-75.0)
		var a1 := deg_to_rad(95.0)
		for i in range(n):
			for e in range(2):
				var ta := lerpf(a0, a1, float(i + e) / n)
				var hn := ridge.get_noise_1d(ta * 3.0 + li * 10.0) * 0.5 + 0.5
				var env_h := 0.35 + 0.65 * smoothstep(-0.9, 0.2, ta)   # над морем слева ниже
				var top_h := amp * (0.25 + 0.75 * hn) * env_h
				var dir := Vector3(sin(ta), 0.0, -cos(ta))
				var p := center + dir * R
				var pt := p + Vector3(0, top_h, 0)
				var pb := p + Vector3(0, -120.0, 0)
				# квад сегмента: (низ i, верх i, низ i+1, верх i+1)
				_mvert(st, pb, lay, 0.0)
				_mvert(st, pt, lay, top_h / amp)
	# индексы квадов: по 4 вершины на сегмент
	var total := layers.size() * 260
	for q in range(total):
		var b := q * 4
		st.add_index(b)
		st.add_index(b + 1)
		st.add_index(b + 2)
		st.add_index(b + 1)
		st.add_index(b + 3)
		st.add_index(b + 2)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	_mount_mat = ShaderMaterial.new()
	_mount_mat.shader = load("res://scenes/menu/mountains.gdshader")
	_mount_mat.render_priority = 0
	mi.material_override = _mount_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _mvert(st: SurfaceTool, p: Vector3, layer: float, h01: float) -> void:
	st.set_color(Color(layer, 0.0, h01))
	st.add_vertex(p)
