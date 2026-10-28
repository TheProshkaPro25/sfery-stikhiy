class_name CreatureModels
extends RefCounted
## 3D-модели существ: HD-модель вида в стихии или архетип вида + перекраска материалов под цвет и стихию.
## Модели генерирует tools/blender/make_creatures.py в assets/creatures/<архетип>.glb
## (высота 1.0, основание на y=0, лицом к +Z). Имена материалов: Primary, Secondary, Metal, Glow, Eye, Dark.

## Размер: длина/ширина фигуры = треть длины карты (в бою два существа + треть пустоты между ними), высота не больше MAX_HEIGHT.
const FOOTPRINT := Arena.CARD_H / 3.0
## Великаны над воротами: существо 0.85–1.0 длины карты (шар рядом с ним — горошина).
const MAX_HEIGHT := Arena.CARD_H * 1.0
const MIN_HEIGHT := Arena.CARD_H * 0.85
## Предел длины вдоль карты (в третях карты) и ширины (в ширинах карты): в бою двое не пересекаются.
const MAX_LEN := 1.75
const MAX_WIDTH := 1.3
const DIR := "res://assets/creatures/%s.glb"
## Модели существ (Pixal3D, со своей текстурой): assets/creatures_hd/<вид>_<стихия>.glb (= id без creature_).
const HD_DIR := "res://assets/creatures_hd/%s.glb"
## Поворот HD-моделей вокруг Y, чтобы смотрели вдоль +Z (как архетипы).
const HD_YAW_DEG := 0.0


## Загруженные модели матча (ключ "hd:<id>" или архетип). Держим только существ текущего матча:
## preload_match() в начале, clear() при перезапуске/выходе — иначе видеопамять росла с каждым матчем.
static var _scenes: Dictionary = {}


static func _key_path(d: CreatureDef) -> Array:
	var key := String(d.id).trim_prefix("creature_")
	var hd_path := HD_DIR % key
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
	var kp := _key_path(d)
	var hd: bool = String(kp[0]).begins_with("hd:")
	var ps: PackedScene = _scene(kp[0], kp[1])
	if ps == null:
		return null
	var root := Node3D.new()
	var inst := ps.instantiate() as Node3D
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
		k = minf(k, minf(FOOTPRINT * MAX_LEN / sz, minf(Arena.CARD_W * MAX_WIDTH / sx, MAX_HEIGHT / sy)))
	model.scale = Vector3.ONE * k
	# основание на y=0, центр по XZ
	model.position = Vector3(-(box.position.x + box.size.x * 0.5) * k, -box.position.y * k, -(box.position.z + box.size.z * 0.5) * k)
	root.add_child(model)
	root.set_meta("height", box.size.y * k)
	root.set_meta("extent", maxf(box.size.x, box.size.z) * k)  # наибольший размер по полу (для камеры)
	if hd:
		_fix_hd_materials(model, VisualUtil.attr_color(d.attribute))
	else:
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


## Материалы моделей Hunyuan3D: в glTF не указан metallicFactor, а по стандарту это 1.0 — полностью металл,
## который под рассеянным светом и тёмным небом выглядит почти чёрным. Делаем диэлектрик (кожа, чешуя)
## и добавляем контурный свет цвета стихии, чтобы тёмные существа читались на тёмном полу.
static func _fix_hd_materials(node: Node, rim_col: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i in range(mi.mesh.get_surface_count()):
			var src := mi.get_active_material(i) as BaseMaterial3D
			if src == null:
				continue
			var m := src.duplicate() as BaseMaterial3D
			if m.metallic_texture != null:
				# TRELLIS.2: полный PBR (metallic/roughness/AO/normal) — карты сохраняем, металл приглушаем,
				# иначе без отражений окружения модели темнеют.
				m.metallic = 0.1
				m.metallic_specular = 0.4
				m.roughness = 1.0
			else:
				# Hunyuan: в glTF нет metallic (по стандарту 1.0) — обнуляем.
				m.metallic = 0.0
				m.metallic_specular = 0.35
				m.roughness = 0.72
			m.rim_enabled = true
			m.rim = 0.35
			m.rim_tint = 0.6
			m.emission_enabled = true
			m.emission = rim_col.darkened(0.6)
			m.emission_energy_multiplier = 0.25
			mi.set_surface_override_material(i, m)
	for ch in node.get_children():
		_fix_hd_materials(ch, rim_col)


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
	m.roughness = 0.55
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
					m.roughness = 0.25
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
			m.metallic = 1.0
			m.roughness = 0.28
		"Glow":
			m.albedo_color = c.lightened(0.5)
			m.emission_enabled = true
			m.emission = c.lightened(0.35)
			m.emission_energy_multiplier = 3.0
		"Eye":
			m.albedo_color = Color(0.95, 0.93, 0.88)
			m.roughness = 0.2
		"Dark":
			m.albedo_color = Color(0.06, 0.06, 0.07)
		_:
			m.albedo_color = c
	return m
