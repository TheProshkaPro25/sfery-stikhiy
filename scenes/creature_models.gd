class_name CreatureModels
extends RefCounted
## 3D-модели существ: HD-модель вида в стихии или архетип вида + перекраска материалов под цвет и стихию.
## Модели генерирует tools/blender/make_creatures.py в assets/creatures/<архетип>.glb
## (высота 1.0, основание на y=0, лицом к +Z). Имена материалов: Primary, Secondary, Metal, Glow, Eye, Dark.

## Размер: длина/ширина фигуры = треть масштаба существ Arena.FIG_H (в бою два существа + треть пустоты между ними),
## высота не больше MAX_HEIGHT. Карты ворот крупнее (Arena.GATE_SCALE), существа от них не зависят.
const FOOTPRINT := Arena.FIG_H / 3.0
## Великаны над воротами: существо 0.85–1.0 FIG_H (шар рядом с ним — горошина).
const MAX_HEIGHT := Arena.FIG_H * 1.0
const MIN_HEIGHT := Arena.FIG_H * 0.85
## Предел длины вдоль карты (в третях карты) и ширины (в ширинах карты): в бою двое не пересекаются.
const MAX_LEN := 1.75
const MAX_WIDTH := 1.3
const DIR := "res://assets/creatures/%s.glb"
## Модели существ (Pixal3D, со своей текстурой): assets/creatures_hd/<вид>_<стихия>.glb (= id без creature_).
const HD_DIR := "res://assets/creatures_hd/%s.glb"
## Поворот HD-моделей вокруг Y, чтобы смотрели вдоль +Z (как архетипы).
const HD_YAW_DEG := 0.0
const LikorezModel := preload("res://scenes/likorez_model.gd")


## Загруженные модели матча (ключ "hd:<id>" или архетип). Держим только существ текущего матча:
## preload_match() в начале, clear() при перезапуске/выходе — иначе видеопамять росла с каждым матчем.
static var _scenes: Dictionary = {}

## Убирает запечённые фотографические блики из цветовой текстуры;
## широкие ступени света оставляют рисунок брони, но не имитируют полированный металл.
const ANIME_SHADER := """
shader_type spatial;
render_mode specular_disabled, cull_disabled;
uniform sampler2D color_map : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool has_texture = true;
uniform bool gold_palette = false;
void fragment() {
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
	vec3 tex = tint.rgb;
	if (has_texture) { tex *= texture(color_map, UV).rgb; }
	if (gold_palette) {
		float brightness = max(max(tex.r, tex.g), tex.b);
		float saturation = (brightness - min(min(tex.r, tex.g), tex.b)) / max(brightness, 0.001);
		tex = mix(tex, vec3(1.0, 0.62, 0.11) * brightness, smoothstep(0.12, 0.4, saturation));
	}
	float value = max(max(tex.r, tex.g), tex.b);
	vec3 chroma = tex / max(value, 0.001);
	// Сжимаем запечённые белые блики и тёмные провалы, сохраняя оттенок.
	float tone = mix(0.14, 0.68, smoothstep(0.0, 0.9, value));
	ALBEDO = chroma * tone;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
void light() {
	float facing = max(dot(NORMAL, LIGHT), 0.0);
	float shade = mix(0.32, 0.72, smoothstep(0.12, 0.2, facing));
	shade = mix(shade, 1.0, smoothstep(0.65, 0.73, facing));
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * shade / PI;
}
"""
static var _anime_shader: Shader



static func _key_path(d: CreatureDef) -> Array:
	var key := String(d.id).trim_prefix("creature_")
	# Повреждённая светлая сетка содержит вросшие плоские листы.
	# Используем чистую основу того же вида; золотая палитра задаётся материалом.
	var source_key := "kolossar_gale" if key == "kolossar_light" else key
	var hd_path := HD_DIR % source_key
	if ResourceLoader.exists(hd_path):
		return ["hd:" + key, hd_path]
	return [archetype_of(d), DIR % archetype_of(d)]


## Загрузка моделей существ матча (6 штук) при старте матча: к первому раскрытию они уже в памяти,
## без рывка кадра посреди хода. Синхронно: фоновая загрузка (load_threaded_request) текстур через
## потоки передачи RenderingDevice держала ~+600 МБ ОЗУ процесса; с VRAM-сжатыми текстурами 6 моделей
## грузятся за доли секунды.
static func preload_match(defs: Array) -> void:
	for d in defs:
		if d != null:
			if d.species == &"likorez":
				continue # Процедурная модель не требует GLB.
			var kp := _key_path(d)
			_scene(kp[0], kp[1])


## Отпустить модели (перезапуск матча, выход): ресурсы освобождаются, когда исчезнут последние экземпляры.
static func clear() -> void:
	_scenes.clear()


static func _scene(res_key: String, path: String) -> PackedScene:
	if not _scenes.has(res_key):
		_scenes[res_key] = load(path) as PackedScene
	return _scenes[res_key]


static func archetype_of(d: CreatureDef) -> String:
	return d.archetype if d.archetype != "" else "knight"


## Узел с моделью существа (основание на y=0); null, если модели нет.
static func build(d: CreatureDef) -> Node3D:
	if d == null:
		return null
	var procedural := d.species == &"likorez"
	var kp := ["likorez", ""] if procedural else _key_path(d)
	var hd: bool = String(kp[0]).begins_with("hd:")
	var ps: PackedScene = null if procedural else _scene(kp[0], kp[1])
	if ps == null and not procedural:
		return null
	var root := Node3D.new()
	var inst := LikorezModel.build() if procedural else ps.instantiate() as Node3D
	var model: Node3D = inst
	if hd:
		# обёртка с поворотом, чтобы модель смотрела вдоль +Z
		model = Node3D.new()
		inst.rotation_degrees.y = HD_YAW_DEG
		model.add_child(inst)
	var box := _bounds(model, Transform3D.IDENTITY)
	var k: float = 1.0
	if box.size.length() > 0.001:
		var sx: float = maxf(box.size.x, 0.01)
		var sy: float = maxf(box.size.y, 0.01)
		var sz: float = maxf(box.size.z, 0.01)
		# длина вдоль карты (модели смотрят вдоль Z) = треть карты; но не ниже MIN_HEIGHT,
		# не длиннее MAX_LEN трети, не шире MAX_WIDTH карты и не выше MAX_HEIGHT
		k = maxf(FOOTPRINT / sz, MIN_HEIGHT / sy)
		k = minf(k, minf(FOOTPRINT * MAX_LEN / sz, minf(Arena.FIG_W * MAX_WIDTH / sx, MAX_HEIGHT / sy)))
	model.scale = Vector3.ONE * k
	# основание на y=0, центр по XZ
	model.position = Vector3(-(box.position.x + box.size.x * 0.5) * k, -box.position.y * k, -(box.position.z + box.size.z * 0.5) * k)
	root.add_child(model)
	root.set_meta("height", box.size.y * k)
	root.set_meta("extent", maxf(box.size.x, box.size.z) * k)  # наибольший размер по полу (для камеры)
	if hd:
		_fix_hd_materials(model, d.species == &"kolossar" and d.attribute == Attr.A.LIGHT)
	elif not procedural:
		_recolor(model, d)
	return root


## Общий AABB всех мешей поддерева в координатах корня (узел может быть вне дерева сцены).
static func _bounds(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var has := false
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out = t * (n as MeshInstance3D).mesh.get_aabb()
		has = true
	for ch in n.get_children():
		var b := _bounds(ch, t)
		if b.size.length() > 0.0:
			out = b if not has else out.merge(b)
			has = true
	return out


## Мировой AABB видимых мешей поддерева (для камеры): учитывает плащи, крылья, хвосты. Отдельные эффекты
## (top_level: столбы света, следы) не входят. Пустой AABB, если мешей нет.
static func world_aabb(n: Node) -> AABB:
	var out := AABB()
	var has := false
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is Node3D and c != n and (c as Node3D).top_level:
			continue
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			if mi.mesh != null and mi.is_visible_in_tree():
				var b := mi.global_transform * mi.mesh.get_aabb()
				out = b if not has else out.merge(b)
				has = true
		stack.append_array(c.get_children())
	return out


## Матовая аниме-подача: текстура цвета сохраняется, но PBR-карты не создают
## блестящие пятна, грязные впадины и шум нормалей на сгенерированной поверхности.
## Геометрические дефекты исходного меша требуют отдельной правки модели.
static func _fix_hd_materials(node: Node, gold_palette: bool) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			return
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i in range(mi.mesh.get_surface_count()):
			var src := mi.get_active_material(i) as BaseMaterial3D
			if src == null:
				continue
			if _anime_shader == null:
				_anime_shader = Shader.new()
				_anime_shader.code = ANIME_SHADER
			var m := ShaderMaterial.new()
			m.shader = _anime_shader
			m.set_shader_parameter("tint", src.albedo_color)
			m.set_shader_parameter("gold_palette", gold_palette)
			m.set_shader_parameter("has_texture", src.albedo_texture != null)
			if src.albedo_texture != null:
				m.set_shader_parameter("color_map", src.albedo_texture)
			mi.set_surface_override_material(i, m)
	for ch in node.get_children():
		_fix_hd_materials(ch, gold_palette)


static func _recolor(node: Node, d: CreatureDef) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i in range(mi.mesh.get_surface_count()):
			var src := mi.mesh.surface_get_material(i)
			var mname := src.resource_name if src != null else ""
			mi.set_surface_override_material(i, _material(mname, d))
	for ch in node.get_children():
		_recolor(ch, d)


static func _material(mname: String, d: CreatureDef) -> StandardMaterial3D:
	var c: Color = d.color
	var m := StandardMaterial3D.new()
	m.roughness = 0.9
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	match mname:
		"Primary":
			m.albedo_color = c
			m.rim_enabled = true
			m.rim = 0.35
			m.rim_tint = 0.6
			match d.attribute:
				Attr.A.STONE:
					m.roughness = 0.9
				Attr.A.TIDE:
					m.roughness = 1.05
					m.clearcoat_enabled = true
				Attr.A.LIGHT:
					m.emission_enabled = true
					m.emission = c
					m.emission_energy_multiplier = 0.25
				Attr.A.SHADOW:
					m.albedo_color = c.darkened(0.15)
		"Secondary":
			m.albedo_color = c.darkened(0.5)
			m.roughness = 0.7
		"Metal":
			m.albedo_color = Color(0.78, 0.78, 0.82).lerp(c, 0.2)
			m.metallic = 0.0
			m.roughness = 1.08
		"Glow":
			m.albedo_color = c.lightened(0.5)
			m.emission_enabled = true
			m.emission = c.lightened(0.35)
			m.emission_energy_multiplier = 0.35
			if d.archetype == "cyclops" or d.archetype == "flying_eye":
				m.emission_enabled = false
		"Eye":
			m.albedo_color = Color(0.95, 0.93, 0.88)
			m.roughness = 1.0
		"Dark":
			m.albedo_color = Color(0.06, 0.06, 0.07)
		_:
			m.albedo_color = c
	return m
