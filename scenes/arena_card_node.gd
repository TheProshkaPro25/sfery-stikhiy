class_name ArenaCardNode
extends Node3D
## Карта ворот на слоте — в одном облике с 2D-картами (scenes/shaders/card_face.gdshaderinc).
## Рубашкой вверх: тёмная туманность и эмблема-сфера в цвете владельца; своя закрытая карта подписана на плашке.
## Открытая: рамка по типу ворот, символ в окне, крупное название и медальон силы (читаются с камеры сверху-под углом).

const SIZE := Vector3(Arena.CARD_W, 0.05, Arena.CARD_H)
const OWNER_COLORS = [Color(0.18, 0.30, 0.55), Color(0.55, 0.20, 0.20)]
const TRAY_X := 8.4 * Arena.UNIT
const SHADER: Shader = preload("res://scenes/shaders/card_arena.gdshader")
## Виртуальная ширина карты в пикселях для подбора кегля (как у 2D-карты шириной VIRT px).
const VIRT := 300.0
## Металл ребра карты по типу рамки (CardView.Frame).
const EDGE_COLORS := {0: Color(0.85, 0.66, 0.32), 1: Color(0.72, 0.75, 0.82), 2: Color(0.72, 0.45, 0.26), 3: Color(0.6, 0.26, 0.2),
	6: Color(0.42, 0.62, 0.5), 7: Color(0.42, 0.62, 0.5)}

var slot: int = -1
var owner_player: int = 0
var tray_offset: float = 0.0

var _box: MeshInstance3D
var _face: MeshInstance3D
var _mat: ShaderMaterial
var _edge: StandardMaterial3D
var _flash_tw: Tween
var _title: Label3D
var _power: Label3D
var _lay: Dictionary
var _built := false


func _init() -> void:
	_ensure_built()


func _ready() -> void:
	_ensure_built()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	# раскладка как у мелкой 2D-карты, но плашки крупнее: с наклонной камеры надписи сжимаются по высоте
	_lay = CardView.layout(SIZE.z / SIZE.x, false)
	_lay["title"] = Rect2(0.06, 0.045, 0.88, 0.2)
	_lay["win"] = Vector3(0.5, SIZE.z / SIZE.x * 0.5 + 0.045, 0.27)
	_lay["plaque"] = Vector4(0.5, SIZE.z / SIZE.x - 0.16, 0.26, 0.085)
	_box = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = SIZE
	_box.mesh = bm
	_box.position = Vector3(0, SIZE.y * 0.5, 0)
	_edge = VisualUtil.make_material(Color(0.6, 0.62, 0.7), 0.35, 0.9) as StandardMaterial3D
	_box.material_override = _edge
	add_child(_box)

	# Лицевая поверхность с шейдером облика карты (рубашка / открытая карта) + вспышка раскрытия.
	_face = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(SIZE.x, SIZE.z)
	_face.mesh = pm
	_face.position = Vector3(0, SIZE.y + 0.002, 0)
	_face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("aspect", SIZE.z / SIZE.x)
	_mat.set_shader_parameter("detail", CardView.detail_level())
	_face.material_override = _mat
	add_child(_face)

	_title = _mk_label(CardView.title_font(), Color(1.0, 0.94, 0.8))
	_power = _mk_label(CardView.power_font(), Color(1.0, 0.98, 0.92))


func _mk_label(font: Font, col: Color) -> Label3D:
	var l := Label3D.new()
	l.font = font
	l.modulate = col
	l.outline_modulate = Color(0.0, 0.0, 0.02, 0.95)
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.pixel_size = SIZE.x / VIRT / 2.0
	l.render_priority = 1
	l.outline_render_priority = 0
	l.visible = false
	add_child(l)
	return l


## Точка карты в долях ширины (как в 2D-раскладке) → локальная позиция над лицом.
func _at(px: float, py: float) -> Vector3:
	return Vector3((px - 0.5) * SIZE.x, SIZE.y + 0.012, (py - SIZE.z / SIZE.x * 0.5) * SIZE.x)


## Надпись по центру прямоугольника r (доли ширины) с подбором кегля/строк/ужатия (CardView.fit_title).
func _place(l: Label3D, text: String, center: Vector2, w: float, h: float, max_fs: float) -> void:
	var f: Dictionary = CardView.fit_title(l.font, text, int(max_fs * VIRT), w * VIRT, h * VIRT)
	l.text = f["text"]
	l.font_size = int(f["fs"]) * 2
	l.outline_size = maxi(6, int(int(f["fs"]) * 2 * 0.16))
	l.line_spacing = -float(f["fs"]) * 0.35
	l.scale = Vector3(float(f["sx"]), 1.0, 1.0)
	l.position = _at(center.x, center.y)
	l.visible = text != ""


func show_facedown(owner_pl: int, visible_to_owner_def: CardDef) -> void:
	_ensure_built()
	owner_player = owner_pl
	var oc: Color = OWNER_COLORS[clampi(owner_pl, 0, 1)]
	# рубашка: глубокая туманность и эмблема-сфера в цвете владельца, серебристая рамка
	_mat.set_shader_parameter("frame", CardView.Frame.BACK)
	_mat.set_shader_parameter("base", oc.darkened(0.2))
	_mat.set_shader_parameter("glow", oc.lightened(0.45))
	_mat.set_shader_parameter("gem", Color(oc.lightened(0.5), 1.0))
	_mat.set_shader_parameter("sigil", 0)
	_mat.set_shader_parameter("tier", 0.0)
	_mat.set_shader_parameter("title_box", Vector4.ZERO)
	_mat.set_shader_parameter("text_box", Vector4.ZERO)
	var aspect: float = SIZE.z / SIZE.x
	_mat.set_shader_parameter("win", Vector3(0.5, aspect * 0.5 - 0.04, 0.3))
	_edge.albedo_color = Color(0.55, 0.57, 0.64)
	_power.visible = false
	if visible_to_owner_def != null:
		# своя закрытая карта: имя на плашке внизу (сопернику не видно)
		var pq := Vector4(0.5, aspect - 0.15, 0.36, 0.068)
		_mat.set_shader_parameter("plaque", pq)
		_title.modulate = Color(0.92, 0.95, 1.0)
		_place(_title, visible_to_owner_def.display_name, Vector2(pq.x, pq.y), pq.z * 2.0 - pq.w * 1.6, pq.w * 1.9, 0.085)
	else:
		_mat.set_shader_parameter("plaque", Vector4.ZERO)
		_title.visible = false


## Открытая карта без анимации (переворот в reveal; используется и витриной).
func show_face(def: CardDef) -> void:
	_ensure_built()
	var cols: Array = UiTheme.card_colors(def)
	var fr: int = UiTheme.card_frame(def)
	_mat.set_shader_parameter("frame", fr)
	_mat.set_shader_parameter("tier", float(UiTheme.card_tier(def)))
	_mat.set_shader_parameter("base", cols[0])
	_mat.set_shader_parameter("glow", cols[1])
	var el: Array = UiTheme.card_elements(def)
	if not el.is_empty():
		_mat.set_shader_parameter("gem", Color(VisualUtil.attr_color(int(el[0])).lightened(0.25), 1.0))
	else:
		_mat.set_shader_parameter("gem", Color(cols[1], 0.0))
	_mat.set_shader_parameter("sigil", UiTheme.card_sigil(def))
	_mat.set_shader_parameter("win", _lay["win"])
	_mat.set_shader_parameter("text_box", Vector4.ZERO)
	var tr: Rect2 = _lay["title"]
	_mat.set_shader_parameter("title_box", Vector4(tr.position.x, tr.position.y, tr.end.x, tr.end.y))
	_edge.albedo_color = EDGE_COLORS.get(fr, Color(0.6, 0.62, 0.7))
	_title.modulate = Color(1.0, 0.94, 0.8)
	_place(_title, def.display_name, tr.get_center(), tr.size.x - tr.size.y * 0.84, tr.size.y * 0.96, 0.15)
	var txt: String = CardView.power_text(UiTheme.card_badge(def))
	var pq: Vector4 = _lay["plaque"]
	_mat.set_shader_parameter("plaque", pq if txt != "" else Vector4.ZERO)
	_place(_power, txt, Vector2(pq.x, pq.y - pq.w * 0.04), pq.z * 2.0 - pq.w * 1.4, pq.w * 2.0, pq.w * 2.0)


func reveal(def: CardDef) -> void:
	_ensure_built()
	if def == null:
		return
	var flash_col: Color = (UiTheme.card_colors(def)[1] as Color).lightened(0.2)
	_title.visible = false
	_power.visible = false
	# Переворот: поворот ребром, смена лица, поворот обратно, затем вспышка.
	var tw := create_tween()
	tw.tween_property(self, "rotation:z", PI * 0.5, 0.22).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(self, "position:y", position.y + 0.6 * Arena.WORLD, 0.22)
	tw.tween_callback(func():
		show_face(def)
		VisualUtil.light_pillar(self, Vector3(0, 0.1, 0), flash_col, Arena.CARD_H * 0.9, Arena.CARD_W * 0.35, 0.7)
		VisualUtil.ring_wave(self, global_position + Vector3(0, 0.1, 0), flash_col, Arena.CARD_H * 0.75, 0.7)
		rotation.z = -PI * 0.5)
	tw.tween_property(self, "rotation:z", 0.0, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.parallel().tween_property(self, "position:y", position.y, 0.25)
	tw.tween_callback(func():
		_mat.set_shader_parameter("flash_col", flash_col)
		if _flash_tw != null:
			_flash_tw.kill()
		_flash_tw = create_tween()
		_flash_tw.tween_method(func(v: float): _mat.set_shader_parameter("flash", v), 1.0, 0.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT))


## Движение в "лоток" захваченных карт игрока; возвращает сигнал завершения твина.
func play_capture(to_player: int) -> Signal:
	var z := 2.6 * Arena.UNIT if to_player == 0 else -2.6 * Arena.UNIT
	z += (-tray_offset if to_player == 0 else tray_offset)
	var target := Vector3(TRAY_X, 0.15, z)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "position", target, 0.8)
	tw.tween_property(self, "scale", Vector3(0.5, 0.5, 0.5), 0.8)
	return tw.finished
