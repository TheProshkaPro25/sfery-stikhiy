class_name CreaturePreview
extends PanelContainer
## Панель предпросмотра в сборке колоды: существо — живая 3D-модель на подставке со знаком стихии
## (своя SubViewport, своё 3D-окружение), карта ворот/способности — крупная карта с описанием.
## Модели тяжёлые (~28 МБ текстур): в памяти только показываемая и модели команды (keep_only),
## загрузка фоном (ResourceLoader.load_threaded_request), не больше одной одновременно.
## Модель можно крутить мышью; в покое она медленно поворачивается сама.

## Короткая характеристика вида (по GameData.SPECIES).
const SPECIES_INFO := {
	&"dragnar": "Дракон. Крылатый и мощный: высокая сила, упрямый напор.",
	&"klykar": "Волк. Быстрый охотник: силён против тех, кто сильнее его.",
	&"grifalon": "Грифон. Атакует с неба, ворота соперника ему не мешают.",
	&"kolossar": "Циклоп. Самый сильный вид, непробиваем в защите.",
	&"rogozhuk": "Жук-носорог. Броня и таран, ослабляет соперника надолго.",
	&"levian": "Морской змей. Сжигает бонусы соперника, утягивает в пучину.",
	&"ratnik": "Рыцарь. Надёжный боец, его карты нельзя отменить.",
	&"gorgul": "Крылатый глаз. Слабейший вид, но гасит ворота боя.",
}
const IconT := preload("res://scenes/ui/element_mark.gd")
const TURN_SPEED := 0.35        ## рад/с, поворот в покое
const STAGE_FOV := 30.0

var _stage: Control
var _stage_bg: ColorRect
var _bg_mat: ShaderMaterial
var _vpc: SubViewportContainer
var _vp: SubViewport
var _turn: Node3D
var _norm: Node3D
var _anim: CreatureAnim
var _sigil: MeshInstance3D
var _rim_light: OmniLight3D
var _card_box: CenterContainer
var _loading: Label
var _drag_hint: Label

var _name: Label
var _icon: IconT
var _sub: Label
var _power: Label
var _lines: VBoxContainer
var _status: Label

var _shown_id: StringName = &""      ## существо, чья модель сейчас на сцене
var _want: CreatureDef               ## существо, которое нужно показать
var _want_pose := false
var _pending := ""                   ## путь, который грузится фоном
var _cache: Dictionary = {}          ## путь -> PackedScene (показываемая + команда)
var _keep: Array[StringName] = []    ## существа, чьи модели держим в памяти
var _dragging := false
var _idle_t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UiTheme.box(Color(0.06, 0.06, 0.10, 0.92), UiTheme.GOLD_DIM, 2, 12, 10))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)

	_stage = Control.new()
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.custom_minimum_size = Vector2(0, 160)
	_stage.clip_contents = true
	_stage.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage.mouse_default_cursor_shape = Control.CURSOR_DRAG
	_stage.gui_input.connect(_on_stage_input)
	vb.add_child(_stage)
	_stage_bg = ColorRect.new()
	VisualUtil.full_rect_ignore(_stage_bg)
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nuniform vec4 tint : source_color = vec4(1.0);\nvoid fragment() {\n\tvec2 q = (UV - vec2(0.5, 0.72)) * vec2(1.0, 1.25);\n\tfloat g = smoothstep(0.75, 0.0, length(q));\n\tvec3 c = mix(vec3(0.025, 0.025, 0.045), tint.rgb * 0.42, g * g);\n\tc += tint.rgb * 0.08 * smoothstep(0.2, 0.0, abs(UV.y - 0.8)) * g;\n\tCOLOR = vec4(c, 1.0);\n}"
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = sh
	_stage_bg.material = _bg_mat
	_stage.add_child(_stage_bg)
	_vpc = SubViewportContainer.new()
	_vpc.stretch = true
	VisualUtil.full_rect_ignore(_vpc)
	_stage.add_child(_vpc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vpc.add_child(_vp)
	_build_world()
	_card_box = CenterContainer.new()
	VisualUtil.full_rect_ignore(_card_box)
	_card_box.visible = false
	_stage.add_child(_card_box)
	_loading = VisualUtil.label("Загрузка модели…", 15)
	_loading.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_loading.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_loading.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_loading.grow_vertical = Control.GROW_DIRECTION_BOTH
	_loading.visible = false
	_stage.add_child(_loading)
	_drag_hint = VisualUtil.label("⟲ потяните, чтобы повернуть", 12)
	_drag_hint.add_theme_color_override("font_color", Color(UiTheme.TEXT_DIM, 0.7))
	_drag_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_drag_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_drag_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_drag_hint.position -= Vector2(6, 4)
	_stage.add_child(_drag_hint)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vb.add_child(head)
	_icon = IconT.make(0, 30) as IconT
	head.add_child(_icon)
	var nb := VBoxContainer.new()
	nb.add_theme_constant_override("separation", -2)
	nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nb)
	_name = VisualUtil.label("", 22)
	_name.add_theme_color_override("font_color", UiTheme.GOLD)
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.clip_text = true
	nb.add_child(_name)
	_sub = VisualUtil.label("", 13)
	_sub.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nb.add_child(_sub)
	_power = VisualUtil.label("", 24)
	_power.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	head.add_child(_power)

	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 3)
	vb.add_child(_lines)
	_status = VisualUtil.label("", 14)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_status)


func _build_world() -> void:
	var w := Node3D.new()
	_vp.add_child(w)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.62)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	w.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.5
	key.rotation_degrees = Vector3(-38, 28, 0)
	w.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.45
	fill.light_color = Color(0.75, 0.8, 1.0)
	fill.rotation_degrees = Vector3(-15, -60, 0)
	w.add_child(fill)
	# контровой свет цвета стихии сзади: силуэт читается на тёмном фоне
	_rim_light = OmniLight3D.new()
	_rim_light.position = Vector3(0.0, 1.1, -1.3)
	_rim_light.omni_range = 4.0
	_rim_light.light_energy = 2.2
	w.add_child(_rim_light)
	var cam := Camera3D.new()
	cam.fov = STAGE_FOV
	cam.position = Vector3(0.0, 0.92, 3.3)
	cam.rotation_degrees = Vector3(-9.0, 0.0, 0.0)
	w.add_child(cam)
	cam.current = true
	# знак стихии на полу под существом (тот же шейдер, что вспышка знака на арене)
	_sigil = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.5, 1.5)
	_sigil.mesh = pm
	var sm := ShaderMaterial.new()
	sm.shader = load("res://scenes/shaders/fx_sigil.gdshader")
	_sigil.material_override = sm
	_sigil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sigil.position = Vector3(0, 0.005, 0)
	w.add_child(_sigil)
	_turn = Node3D.new()
	w.add_child(_turn)
	_norm = Node3D.new()
	_turn.add_child(_norm)


# ---------------------------------------------------------------- показ

## Показать существо; pose — сыграть выход в стойку (выбор в команду).
func show_creature(d: CreatureDef, pose: bool = false, in_team: bool = false, note: String = "") -> void:
	if d == null:
		return
	_card_box.visible = false
	VisualUtil.clear_children(_card_box)
	_vpc.visible = true
	_drag_hint.visible = true
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	var ac: Color = VisualUtil.attr_color(d.attribute)
	_bg_mat.set_shader_parameter("tint", ac)
	_rim_light.light_color = ac.lightened(0.2)
	_sigil.set_instance_shader_parameter("element", d.attribute)
	_sigil.set_instance_shader_parameter("col", ac.lightened(0.2))
	_sigil.set_instance_shader_parameter("fade", 0.55)
	_icon.visible = true
	_icon.set_element(d.attribute)
	_set_name(d.display_name)
	_sub.text = "%s · вид %s" % [VisualUtil.attr_name(d.attribute), CardDB.species_name(d.species)]
	_power.text = "%d G" % d.base_power
	VisualUtil.clear_children(_lines)
	_line(String(SPECIES_INFO.get(d.species, "")), UiTheme.TEXT, 14)
	var beats: int = (d.attribute + 1) % 6
	var weak: int = Attr.beaten_by(d.attribute)
	_line("Бьёт стихию %s (+60 в бою), уступает стихии %s." % [VisualUtil.attr_name(beats), VisualUtil.attr_name(weak)], UiTheme.TEXT_DIM, 13)
	var own: PackedStringArray = []
	for id in CardDB.ability_ids() + CardDB.arena_ids():
		var c: CardDef = CardDB.card(id)
		if CardEffects.species_lock(c) == d.species:
			own.append("«%s»" % c.display_name)
	if not own.is_empty():
		_line("Карты вида: " + ", ".join(own), Color(0.6, 0.9, 0.6), 13)
	_set_status(in_team, note)
	_want = d
	_want_pose = pose
	if _shown_id == d.id:
		if pose and _anim != null:
			_anim.appear()
		return
	_request(d)


## Показать карту ворот или способности крупно, с описанием класса.
func show_card(def: CardDef, picked: bool = false, note: String = "") -> void:
	if def == null:
		return
	_want = null
	_vpc.visible = false
	_drag_hint.visible = false
	_loading.visible = false
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_card_box.visible = true
	VisualUtil.clear_children(_card_box)
	var help: Array = UiTheme.card_help(def)
	var cc: Color = help[2]
	_bg_mat.set_shader_parameter("tint", cc.darkened(0.2))
	var h: float = clampf(_stage.size.y - 16.0, 150.0, 300.0)
	var cv := CardView.new().for_card(def, Vector2(round(h / 1.4), round(h)))
	cv.tooltip_text = ""
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_box.add_child(cv)
	var els: Array = UiTheme.card_elements(def)
	_icon.visible = not els.is_empty()
	if not els.is_empty():
		_icon.set_element(int(els[0]))
	_set_name(def.display_name)
	_sub.text = String(help[1])
	_power.text = UiTheme.card_badge(def)
	VisualUtil.clear_children(_lines)
	_line(def.text, UiTheme.TEXT, 14)
	if String(help[6]) != "":
		_line(String(help[6]), Color(1.0, 0.85, 0.5), 13)
	_line(String(help[3]), UiTheme.TEXT_DIM, 12)
	_set_status(picked, note)


## Пустая панель с подсказкой.
func show_hint(text: String) -> void:
	_want = null
	_vpc.visible = false
	_drag_hint.visible = false
	_loading.visible = false
	_card_box.visible = false
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_icon.visible = false
	_name.text = ""
	_sub.text = ""
	_power.text = ""
	VisualUtil.clear_children(_lines)
	_set_status(false, text)


## Имя крупно; длинное — мельче, чтобы влезло рядом со значком и силой.
func _set_name(text: String) -> void:
	_name.text = text
	var font: Font = _name.get_theme_font("font")
	var max_w: float = maxf(size.x, custom_minimum_size.x) - 20.0 - 38.0 - 12.0 - 82.0  # поля, значок, сила
	var fs := 22
	while fs > 14 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		fs -= 1
	_name.add_theme_font_size_override("font_size", fs)


func _line(text: String, c: Color, fs: int) -> void:
	if text == "":
		return
	var l := VisualUtil.label(text, fs)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", c)
	_lines.add_child(l)


func _set_status(on: bool, note: String) -> void:
	_status.text = note
	_status.add_theme_color_override("font_color", Color(0.55, 0.95, 0.6) if on else Color(1.0, 0.85, 0.5))


# ---------------------------------------------------------------- модели

## Держать в памяти только модели этих существ (команда) и показываемую; остальные отпустить.
func keep_only(ids: Array[StringName]) -> void:
	_keep = ids.duplicate()
	_prune()


## Отпустить всё (уход из меню в бой): модель, кэш, рендер.
func release() -> void:
	_want = null
	_keep.clear()
	_drop_model()
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_cache.clear()


func _path_of(d: CreatureDef) -> String:
	return String(CreatureModels._key_path(d)[1])


func _prune() -> void:
	var need: Dictionary = {}
	for id in _keep:
		var d: CreatureDef = CardDB.creature(id)
		if d != null:
			need[_path_of(d)] = true
	if _want != null:
		need[_path_of(_want)] = true
	elif _shown_id != &"":
		need[_path_of(CardDB.creature(_shown_id))] = true
	for p in _cache.keys():
		if not need.has(p):
			_cache.erase(p)


func _request(d: CreatureDef) -> void:
	var path := _path_of(d)
	if _cache.has(path):
		_spawn(d, _cache[path])
		return
	_loading.visible = true
	if _anim != null:
		_anim.visible = false
	if _pending != "":
		return   # дождёмся текущей загрузки, затем _process возьмёт актуальное _want
	if ResourceLoader.load_threaded_request(path, "PackedScene") != OK:
		return
	_pending = path


func _process(delta: float) -> void:
	if _pending != "":
		var st := ResourceLoader.load_threaded_get_status(_pending)
		if st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			var path := _pending
			_pending = ""
			var ps: PackedScene = ResourceLoader.load_threaded_get(path) as PackedScene if st == ResourceLoader.THREAD_LOAD_LOADED else null
			if ps != null:
				_cache[path] = ps
			if _want != null:
				if _path_of(_want) == path:
					_spawn(_want, ps)
				elif _shown_id != _want.id:
					_request(_want)
			_prune()
	if _turn != null and _vpc.visible and not _dragging:
		_idle_t += delta
		_turn.rotation.y += TURN_SPEED * delta * clampf(_idle_t - 1.5, 0.0, 1.0)


func _spawn(d: CreatureDef, ps: PackedScene) -> void:
	_loading.visible = false
	_drop_model()
	if ps == null:
		return
	# CreatureModels.build берёт сцену из своего кэша матча: подкладываем загруженную и убираем обратно,
	# чтобы кэш матча не держал модели меню
	var kp: Array = CreatureModels._key_path(d)
	var had: bool = CreatureModels._scenes.has(kp[0])
	if not had:
		CreatureModels._scenes[kp[0]] = ps
	var model: Node3D = CreatureModels.build(d)
	if not had:
		CreatureModels._scenes.erase(kp[0])
	if model == null:
		return
	var hgt: float = float(model.get_meta("height", 1.0))
	var ext: float = float(model.get_meta("extent", hgt))
	_norm.scale = Vector3.ONE / maxf(maxf(hgt, ext * 0.85), 0.01)
	_anim = CreatureAnim.new()
	_norm.add_child(_anim)
	_anim.set_model(model, d)
	_anim.idle_on = true
	_shown_id = d.id
	_turn.rotation.y = 0.0
	_idle_t = 0.0
	if _want_pose:
		_anim.appear()


func _drop_model() -> void:
	if _anim != null:
		_anim.queue_free()
		_anim = null
	_shown_id = &""


func _on_stage_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (e as InputEventMouseButton).pressed
		_idle_t = 0.0
	elif e is InputEventMouseMotion and _dragging:
		_turn.rotation.y += (e as InputEventMouseMotion).relative.x * 0.012
