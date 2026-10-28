class_name TeamMenu
extends Control
## Сборка колоды по правилам Бакугана: боец одной стихии — 3 существа этой стихии,
## 3 карты ворот (стихии, вида, командные) и 3 способности (стихийная, усиление, видовая).
## Карты стихии — только своей стихии, карты вида — только видов из команды.
## Три шага: стихия и существа → ворота → способности.
## Экран: слева — колода слотами (сила команды полосой, причина «нельзя в бой», кнопка «В бой»),
## в центре — карты шага (фильтр по классу), справа — предпросмотр: 3D-модель существа или крупная карта.
## Клавиши: 1–3 — шаг, ←/→ — назад/далее, Enter — в бой (или далее), R — случайная колода.

signal team_chosen(ids: Array[StringName])
signal deck_chosen(creatures: Array[StringName], arena: Array[StringName], abilities: Array[StringName])

const MAX_TEAM := 3
## Через preload: новые классы видны и без пересборки кэша глобальных классов (godot --import).
const PreviewT := preload("res://scenes/ui/creature_preview.gd")
const IconT := preload("res://scenes/ui/element_mark.gd")
const CLASS_NAMES := {
	&"gold": "Ворота стихии", &"silver": "Ворота вида", &"bronze": "Командные ворота",
	&"red": "Стихийная", &"blue": "Усиление", &"green": "Видовая",
}
const CLASS_COLORS := {
	&"gold": Color(1.0, 0.82, 0.35), &"silver": Color(0.8, 0.84, 0.9), &"bronze": Color(0.85, 0.55, 0.3),
	&"red": Color(1.0, 0.4, 0.35), &"blue": Color(0.45, 0.65, 1.0), &"green": Color(0.45, 0.9, 0.55),
}
const STEP_NAMES := ["Команда", "Ворота", "Способности"]
const STEP_HINTS := [
	"Выберите стихию и 3 существа (клик — взять / убрать). Наведите на карту — справа модель и подробности.",
	"По одной карте ворот каждого класса. Клик — выбрать, повторный клик — снять.",
	"По одной способности каждого цвета. Клик — выбрать, повторный клик — снять.",
]

## Последняя собранная колода (переживает перезагрузку сцены).
static var last_deck: Dictionary = {}
## Сложность ИИ (AIPlayer.Difficulty): выбирается в меню, переживает перезагрузку сцены.
static var difficulty: int = AIPlayer.Difficulty.NORMAL
const DIFF_TIPS := [
	"Новичок: бросает неточно, не прикрепляет карты, плохо читает ловушки.",
	"Боец: обычная точность, отвечает на способности, иногда блефует воротами.",
	"Мастер: точный бросок, держит запас силы на ответ, ставит ловушки-приманки.",
]

## Ширины боковых колонок и отступы (логические пиксели; окно растягивается из 1280×720).
const LEFT_W := 262.0
const RIGHT_W := 322.0
const PAD := 14.0
const GAP := 12.0

var _element: int = 0
var _team: Array[StringName] = []
var _pick: Dictionary = {}   # класс карты -> id
var _step: int = 0
var _filter: StringName = &""   # класс карт, показанный на шаге 2/3 ("" — все)
var _rng := RandomNumberGenerator.new()
var _built := false

var _steps: Array[Button] = []
var _filters: HBoxContainer
var _hint: Label
var _page: ScrollContainer
var _cards: Dictionary = {}     # id -> CardView текущего шага
var _deck_box: VBoxContainer
var _power_bar: PowerBar
var _error: Label
var _back_btn: Button
var _next_btn: Button
var _go_btn: Button
var _preview: PreviewT
var _focus_id: StringName = &""    # что показывать в предпросмотре без наведения
var _hover_id: StringName = &""
var _hover_t := 0.0


func _ready() -> void:
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	_rng.randomize()
	CardDB.load_all()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.045, 0.06, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(PAD))
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)

	# шапка: название, шаги с прогрессом, настройки графики, правила
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vb.add_child(head)
	var logo := VisualUtil.label("Сферы Стихий", 24)
	logo.add_theme_color_override("font_color", UiTheme.GOLD)
	logo.custom_minimum_size = Vector2(LEFT_W - 8.0, 0)
	head.add_child(logo)
	for i in range(3):
		var sb := _button("", 150, 40, 16)
		sb.pressed.connect(func() -> void: _show_step(i))
		head.add_child(sb)
		_steps.append(sb)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	# уровень графики: Низкие → Средние → Высокие, сохраняется в user://settings.cfg и применяется сразу
	var gfx := _button("Графика: " + GraphicsSettings.level_name(), 160, 40, 15)
	gfx.tooltip_text = "Низкие — без SSAO, тени проще, меньше искр.\nСредние — почти как Высокие, легче для GTX 1060.\nВысокие — 4 каскада теней, SSAO, сглаживание MSAA 2×."
	gfx.pressed.connect(func() -> void:
		GraphicsSettings.set_level((GraphicsSettings.current() + 1) % 3)
		gfx.text = "Графика: " + GraphicsSettings.level_name()
		var m := get_tree().current_scene
		if m != null and m.has_method("apply_graphics"):
			m.apply_graphics())
	head.add_child(gfx)
	# ограничитель кадров: 60 / 90 / 120 / 144 / без лимита, применяется сразу
	var fps := _button("FPS: " + GraphicsSettings.fps_name(), 104, 40, 15)
	fps.tooltip_text = "Предел кадров в секунду. Меньше — тише вентилятор и дольше батарея."
	fps.pressed.connect(func() -> void:
		GraphicsSettings.next_fps()
		fps.text = "FPS: " + GraphicsSettings.fps_name())
	head.add_child(fps)
	var help_btn := _button("Как играть", 120, 40, 15)
	help_btn.pressed.connect(func() -> void: HelpOverlay.open_on(self))
	head.add_child(help_btn)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", int(GAP))
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(body)
	body.add_child(_build_deck_panel())

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 6)
	body.add_child(center)
	_filters = HBoxContainer.new()
	_filters.alignment = BoxContainer.ALIGNMENT_CENTER
	_filters.add_theme_constant_override("separation", 6)
	_filters.custom_minimum_size = Vector2(0, 40)
	center.add_child(_filters)
	_hint = VisualUtil.label("", 13)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hint.clip_text = true
	_hint.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	center.add_child(_hint)
	_page = ScrollContainer.new()
	_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(_page)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	center.add_child(nav)
	_back_btn = _button("← Назад", 130)
	_back_btn.pressed.connect(func() -> void: _show_step(_step - 1))
	nav.add_child(_back_btn)
	var keys := VisualUtil.label("1–3 шаги · ←/→ · Enter — в бой · R — случайная", 12)
	keys.add_theme_color_override("font_color", Color(UiTheme.TEXT_DIM, 0.7))
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keys.clip_text = true
	nav.add_child(keys)
	_next_btn = _button("Далее →", 150)
	_next_btn.pressed.connect(func() -> void: _show_step(_step + 1))
	nav.add_child(_next_btn)

	_preview = PreviewT.new()
	_preview.custom_minimum_size = Vector2(RIGHT_W, 0)
	body.add_child(_preview)

	get_viewport().size_changed.connect(func() -> void:
		if visible:
			_show_step(_step))
	visibility_changed.connect(func() -> void:
		if not visible:
			_preview.release())

	if last_deck.is_empty():
		pick_random()
	else:
		_element = int(last_deck["element"])
		_team.assign(last_deck["creatures"])
		_pick = (last_deck["pick"] as Dictionary).duplicate()
		_drop_unfit_picks()
		_show_step(0)


func _build_deck_panel() -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(LEFT_W, 0)
	p.add_theme_stylebox_override("panel", UiTheme.box(Color(0.06, 0.06, 0.10, 0.92), UiTheme.GOLD_DIM, 2, 12, 10))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	p.add_child(vb)
	var t := VisualUtil.label("Ваша колода", 18)
	t.add_theme_color_override("font_color", UiTheme.GOLD)
	vb.add_child(t)
	_deck_box = VBoxContainer.new()
	_deck_box.add_theme_constant_override("separation", 2)
	vb.add_child(_deck_box)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(sp)
	_error = VisualUtil.label("", 14)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error.custom_minimum_size = Vector2(0, 30)
	_error.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vb.add_child(_error)
	var dl := VisualUtil.label("Соперник", 13)
	dl.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	vb.add_child(dl)
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 4)
	vb.add_child(drow)
	var grp := ButtonGroup.new()
	for d in range(3):
		var db := _button(AIPlayer.difficulty_name(d), 0, 34, 14)
		db.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		db.toggle_mode = true
		db.button_group = grp
		db.button_pressed = d == difficulty
		db.tooltip_text = DIFF_TIPS[d]
		db.pressed.connect(func() -> void: difficulty = d)
		drow.add_child(db)
	_go_btn = _button("В бой!", 0, 48, 22)
	_go_btn.add_theme_stylebox_override("normal", UiTheme.box(Color(0.42, 0.28, 0.08, 0.97), UiTheme.GOLD, 2, 10, 10))
	_go_btn.add_theme_stylebox_override("hover", UiTheme.box(Color(0.55, 0.38, 0.12, 0.97), Color(1.0, 0.92, 0.6), 2, 10, 10))
	_go_btn.add_theme_color_override("font_color", Color(1.0, 0.93, 0.7))
	_go_btn.pressed.connect(_on_go)
	vb.add_child(_go_btn)
	var rnd := _button("Случайная колода", 0, 36, 15)
	rnd.tooltip_text = "Случайная стихия, команда и карты по правилам колоды (R)"
	rnd.pressed.connect(pick_random)
	vb.add_child(rnd)
	return p


func _button(text: String, w: float, h: float = 42.0, fs: int = 17) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", fs)
	return b


# ---------------------------------------------------------------- шаги

func _show_step(step: int) -> void:
	var s := clampi(step, 0, 2)
	if s != _step:
		_filter = &""
	_step = s
	VisualUtil.clear_children(_page)
	VisualUtil.clear_children(_filters)
	_cards.clear()
	_hint.text = STEP_HINTS[_step]
	match _step:
		0:
			_build_creatures_page()
		1:
			_build_cards_page(CardDef.Kind.ARENA, CardDB.GATE_CLASSES)
		2:
			_build_cards_page(CardDef.Kind.ABILITY, CardDB.ABILITY_CLASSES)
	_back_btn.disabled = _step == 0
	_next_btn.disabled = _step == 2
	_focus_id = _default_focus()
	_hover_id = &""
	_refresh()
	_show_preview(_focus_id, false)


## Свободное место под карты в центре (оценка по размеру окна; колонки фиксированной ширины).
func _center_size() -> Vector2:
	var vp := get_viewport_rect().size
	var w := vp.x - PAD * 2.0 - LEFT_W - RIGHT_W - GAP * 2.0 - 8.0
	var h := vp.y - PAD * 2.0 - 40.0 - 8.0 - 40.0 - 6.0 - 22.0 - 6.0 - 42.0 - 6.0 - 12.0
	return Vector2(w, h)


func _build_creatures_page() -> void:
	for a in range(6):
		var b := _button(VisualUtil.attr_name(a), 0, 40, 15)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.button_pressed = a == _element
		b.add_theme_color_override("font_color", VisualUtil.attr_color(a).lightened(0.35))
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
		if a == _element:
			var ac := VisualUtil.attr_color(a)
			b.add_theme_stylebox_override("pressed", UiTheme.box(ac.darkened(0.55), ac.lightened(0.3), 2, 8, 6))
			b.add_theme_stylebox_override("hover_pressed", UiTheme.box(ac.darkened(0.45), ac.lightened(0.4), 2, 8, 6))
		b.tooltip_text = "Стихия %s: бьёт %s, уступает %s" % [VisualUtil.attr_name(a), VisualUtil.attr_name((a + 1) % 6), VisualUtil.attr_name(Attr.beaten_by(a))]
		b.pressed.connect(_on_element.bind(a))
		# значок стихии и название по центру кнопки
		var name_txt := b.text
		b.text = ""
		var cc := CenterContainer.new()
		cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(cc)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 5)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cc.add_child(hb)
		hb.add_child(IconT.make(a, 20, a == _element))
		var nl := VisualUtil.label(name_txt, 15)
		nl.add_theme_color_override("font_color", Color.WHITE if a == _element else VisualUtil.attr_color(a).lightened(0.35))
		hb.add_child(nl)
		_filters.add_child(b)
	_hint.text = "Клик — взять / убрать.  Цикл стихий: Пламя > Буря > Свет > Камень > Тень > Прилив > Пламя"
	# 8 видов стихии: сетка 4×2, карты по размеру свободного места
	var avail := _center_size()
	var w: float = minf(minf((avail.x - 3 * 14.0) / 4.0, (avail.y - 14.0) / 2.0 / 1.4), 160.0)
	var sz := Vector2(round(w), round(w * 1.4))
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size = Vector2(0, avail.y - 8.0)
	_page.add_child(center)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	center.add_child(grid)
	for id in CardDB.creatures_of(_element):
		var cv := CardView.new().for_creature(CardDB.creature(id), -1, "", sz)
		cv.tooltip_text = ""   # подробности — в предпросмотре справа
		cv.toggle_mode = true
		cv.pressed.connect(_on_creature.bind(id))
		cv.mouse_entered.connect(_on_hover.bind(id, true))
		cv.mouse_exited.connect(_on_hover.bind(id, false))
		cv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(cv)
		_cards[id] = cv
	_sync_cards()


func _build_cards_page(kind: int, classes: Array[StringName]) -> void:
	var species: Array = CardDB.team_species(_team)
	# фильтр: все классы или один
	var fgrp := ButtonGroup.new()
	var fl: Array = [&""]
	fl.append_array(classes)
	for cls in fl:
		var b := _button("Все" if cls == &"" else String(CLASS_NAMES[cls]), 0, 40, 15)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL if cls != &"" else Control.SIZE_FILL
		if cls == &"":
			b.custom_minimum_size.x = 70
		b.toggle_mode = true
		b.button_group = fgrp
		b.button_pressed = cls == _filter
		if cls != &"":
			var c: Color = CLASS_COLORS[cls]
			b.add_theme_color_override("font_color", c)
			b.add_theme_color_override("font_hover_color", c.lightened(0.3))
			b.add_theme_color_override("font_pressed_color", Color.WHITE)
			b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
			b.add_theme_stylebox_override("pressed", UiTheme.box(c.darkened(0.65), c, 2, 8, 6))
			b.add_theme_stylebox_override("hover_pressed", UiTheme.box(c.darkened(0.55), c.lightened(0.2), 2, 8, 6))
			if _pick.has(cls):
				b.text += " ✓"
			b.tooltip_text = String(UiTheme.CLASS_HELP[cls][1])
		b.pressed.connect(func() -> void:
			_filter = cls
			_show_step(_step))
		_filters.add_child(b)
	var sections: Array = []
	for cls in classes:
		if _filter != &"" and cls != _filter:
			continue
		sections.append([cls, CardDB.cards_of(kind, cls, _element, species)])
	var lay: Dictionary = _fit_sections(sections, _center_size())
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 22)
	flow.add_theme_constant_override("v_separation", 8)
	_page.add_child(flow)
	var sz: Vector2 = lay["size"]
	for i in range(sections.size()):
		var cls: StringName = sections[i][0]
		var ids: Array = sections[i][1]
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 10)  # выбранная карта приподнята — не наезжает на заголовок
		flow.add_child(col)
		var head := VisualUtil.label(String(CLASS_NAMES[cls]), 16)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_theme_color_override("font_color", CLASS_COLORS[cls])
		col.add_child(head)
		var grid := GridContainer.new()
		grid.columns = int(lay["cols"][i])
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		col.add_child(grid)
		if ids.is_empty():
			col.add_child(VisualUtil.label("нет подходящих карт", 13))
		for id in ids:
			var cv := CardView.new().for_card(CardDB.card(id), sz)
			cv.tooltip_text = ""
			cv.toggle_mode = true
			cv.pressed.connect(_on_card.bind(cls, id))
			cv.mouse_entered.connect(_on_hover.bind(id, true))
			cv.mouse_exited.connect(_on_hover.bind(id, false))
			grid.add_child(cv)
			_cards[id] = cv
	_sync_cards()


## Наибольший размер карт, при котором секции (заголовок + сетка) влезают в avail потоком слева направо.
## -> {size: Vector2, cols: [число колонок каждой секции]}
func _fit_sections(sections: Array, avail: Vector2) -> Dictionary:
	const G := 8.0      # между картами
	const SG := 22.0    # между секциями
	const HEAD := 32.0  # заголовок секции
	var w := 170.0
	var cols: Array = []
	while true:
		var h := roundf(w * 1.4)
		var per_row: int = maxi(1, int((avail.x + G) / (w + G)))
		cols.clear()
		var total := 0.0
		var row_w := 0.0
		var row_h := 0.0
		for s in sections:
			var n: int = maxi(1, (s[1] as Array).size())
			var c: int = mini(n, per_row)
			# в широкой секции — поровну по рядам (10 карт в 5+5, а не 6+4)
			var rows: int = ceili(float(n) / c)
			c = ceili(float(n) / rows)
			cols.append(c)
			var sw := c * (w + G) - G
			var sh := HEAD + rows * (h + G) - G
			if row_w > 0.0 and row_w + SG + sw > avail.x:
				total += row_h + 8.0
				row_w = 0.0
				row_h = 0.0
			row_w += (SG if row_w > 0.0 else 0.0) + sw
			row_h = maxf(row_h, sh)
		total += row_h
		if total <= avail.y or w <= 84.0:
			break
		w -= 4.0
	return {"size": Vector2(round(w), round(w * 1.4)), "cols": cols.duplicate()}


## Что показать в предпросмотре по умолчанию: последнее существо команды / выбранная карта шага.
func _default_focus() -> StringName:
	if _step == 0:
		if not _team.is_empty():
			return _team[_team.size() - 1]
		var all: Array[StringName] = CardDB.creatures_of(_element)
		return all[0] if not all.is_empty() else &""
	var classes: Array[StringName] = CardDB.GATE_CLASSES if _step == 1 else CardDB.ABILITY_CLASSES
	for cls in classes:
		if (_filter == &"" or cls == _filter) and _pick.has(cls):
			return _pick[cls]
	return &""


## Состояние карт шага без перестройки: выбранные горят, остальные в занятом классе приглушены.
func _sync_cards() -> void:
	for id in _cards:
		var cv: CardView = _cards[id]
		if _step == 0:
			cv.set_pressed_no_signal(_team.has(id))
			cv.modulate = Color(1, 1, 1, 0.5) if _team.size() >= MAX_TEAM and not _team.has(id) else Color.WHITE
		else:
			var cls: StringName = CardDB.card_class(CardDB.card(id))
			cv.set_pressed_no_signal(_pick.get(cls, &"") == id)
			cv.modulate = Color(1, 1, 1, 0.55) if _pick.has(cls) and _pick[cls] != id else Color.WHITE
		cv._sync_selected()


# ---------------------------------------------------------------- предпросмотр

func _on_hover(id: StringName, on: bool) -> void:
	if on:
		_hover_id = id
		# существо — с задержкой (модель грузится; не дёргать при проводке мышью), карта — сразу
		_hover_t = 0.12 if _step == 0 else 0.0
		if _step != 0:
			_show_preview(id, false)
	elif _hover_id == id:
		_hover_id = &""
		_hover_t = 0.35


func _process(delta: float) -> void:
	if _hover_t <= 0.0:
		return
	_hover_t -= delta
	if _hover_t <= 0.0:
		_show_preview(_hover_id if _hover_id != &"" else _focus_id, false)


func _show_preview(id: StringName, pose: bool) -> void:
	if _preview == null:
		return
	if _step == 0:
		var d: CreatureDef = CardDB.creature(id)
		if d == null:
			_preview.show_hint("Наведите на существо, чтобы увидеть его")
			return
		var in_team := _team.has(id)
		var note := ""
		if in_team:
			note = "В команде · клик — убрать"
		elif _team.size() >= MAX_TEAM:
			note = "Команда полна: сначала уберите кого-то"
		else:
			var after := CardDB.team_power(_team) + d.base_power
			note = "Клик — взять в команду"
			if after > CardDB.team_power_limit():
				note = "Сила команды станет %d — больше лимита %d" % [after, CardDB.team_power_limit()]
		_preview.show_creature(d, pose, in_team, note)
		_power_bar.set_extra(0 if in_team or _team.size() >= MAX_TEAM else d.base_power)
		return
	var c: CardDef = CardDB.card(id)
	if c == null:
		_preview.show_hint("Наведите на карту, чтобы прочитать её целиком.\nВыбрано: %d из 3." % _picked_count(_step))
		return
	var cls: StringName = CardDB.card_class(c)
	var picked: bool = _pick.get(cls, &"") == id
	_preview.show_card(c, picked, "Выбрана · клик — снять" if picked else ("Клик — заменить «%s»" % CardDB.card(_pick[cls]).display_name if _pick.has(cls) else "Клик — взять в колоду"))


## Для снимков: показать существо номер i текущей стихии как при наведении (-1 — снять).
func debug_preview(i: int) -> void:
	var all: Array[StringName] = CardDB.creatures_of(_element)
	if i >= 0 and i < all.size():
		_show_preview(all[i], true)
	else:
		_show_preview(_focus_id, false)


# ---------------------------------------------------------------- выбор

func _on_element(a: int) -> void:
	if a == _element:
		_show_step(0)
		return
	_element = a
	_team.clear()
	_drop_unfit_picks()
	var all: Array[StringName] = CardDB.creatures_of(a)
	for id in all:
		if _team.size() < MAX_TEAM:
			_team.append(id)
	_show_step(0)


func _on_creature(id: StringName) -> void:
	if _team.has(id):
		_team.erase(id)
	elif _team.size() < MAX_TEAM:
		_team.append(id)
	_drop_unfit_picks()
	_focus_id = id
	_sync_cards()
	_refresh()
	_show_preview(id, _team.has(id))


## Убрать выбранные карты, которые больше не подходят команде (чужая стихия, вид не из команды, удалённая карта).
func _drop_unfit_picks() -> void:
	var species: Array = CardDB.team_species(_team)
	for cls in _pick.keys():
		var c: CardDef = CardDB.card(StringName(_pick[cls]))
		if c == null or CardDB.card_class(c) != cls or not CardDB.card_fits(c, _element, species if _team.size() == MAX_TEAM else []):
			_pick.erase(cls)


func _on_card(cls: StringName, id: StringName) -> void:
	if _pick.get(cls, &"") == id:
		_pick.erase(cls)
	else:
		_pick[cls] = id
	_focus_id = id
	_sync_cards()
	_refresh()
	_refresh_filter_marks()
	_show_preview(id, false)


func _refresh_filter_marks() -> void:
	for b in _filters.get_children():
		var btn := b as Button
		for cls in CLASS_NAMES:
			if btn.text.begins_with(String(CLASS_NAMES[cls])):
				btn.text = String(CLASS_NAMES[cls]) + (" ✓" if _pick.has(cls) else "")


func _deck_lists() -> Array:
	var arena: Array[StringName] = []
	for cls in CardDB.GATE_CLASSES:
		if _pick.has(cls):
			arena.append(_pick[cls])
	var abil: Array[StringName] = []
	for cls in CardDB.ABILITY_CLASSES:
		if _pick.has(cls):
			abil.append(_pick[cls])
	return [_team.duplicate(), arena, abil]


func _picked_count(step: int) -> int:
	if step == 0:
		return _team.size()
	var n := 0
	for cls in (CardDB.GATE_CLASSES if step == 1 else CardDB.ABILITY_CLASSES):
		if _pick.has(cls):
			n += 1
	return n


func _refresh() -> void:
	# шаги: номер, название, сколько выбрано; готовый шаг — зелёный, текущий — нажат
	for i in range(3):
		var b := _steps[i]
		var n := _picked_count(i)
		b.text = "%d  %s  %d/3" % [i + 1, STEP_NAMES[i], n]
		var done := n == 3
		var c := Color(0.55, 0.95, 0.6) if done else UiTheme.TEXT
		var cur := i == _step
		b.add_theme_stylebox_override("normal", UiTheme.box(Color(0.36, 0.27, 0.14, 0.97) if cur else Color(0.12, 0.11, 0.16, 0.95), UiTheme.GOLD if cur else (Color(0.4, 0.7, 0.45) if done else UiTheme.GOLD_DIM), 2, 8, 8))
		b.add_theme_color_override("font_color", Color.WHITE if cur else c)
	_refresh_deck()
	var lists: Array = _deck_lists()
	var err: String = CardDB.deck_error(lists[0], lists[1], lists[2])
	if err == "":
		_error.text = "Колода готова!"
		_error.add_theme_color_override("font_color", Color(0.55, 0.95, 0.6))
	else:
		# что именно не выбрано — подсказка к тексту правила
		var miss: PackedStringArray = []
		for cls in CardDB.GATE_CLASSES + CardDB.ABILITY_CLASSES:
			if not _pick.has(cls):
				miss.append(String(CLASS_NAMES[cls]).to_lower())
		_error.text = err
		if _team.size() == MAX_TEAM and not miss.is_empty() and err.begins_with("Нужно"):
			_error.text = "Не выбраны: " + ", ".join(miss)
		_error.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	_go_btn.disabled = err != ""
	_go_btn.tooltip_text = "Начать матч (Enter)" if err == "" else "Пока нельзя: " + err
	_preview.keep_only(_team)


## Колода слотами: 3 существа, полоса силы, 3 ворот, 3 способности.
func _refresh_deck() -> void:
	VisualUtil.clear_children(_deck_box)
	_deck_box.add_child(_section("Существа", _team.size()))
	for i in range(MAX_TEAM):
		if i < _team.size():
			var d: CreatureDef = CardDB.creature(_team[i])
			_deck_box.add_child(_slot(d.display_name, VisualUtil.attr_color(d.attribute), "%d" % d.base_power, d.attribute, 0, _team[i], &""))
		else:
			_deck_box.add_child(_slot("", VisualUtil.attr_color(_element), "", -1, 0, &"", &""))
	_power_bar = PowerBar.new()
	_power_bar.set_power(CardDB.team_power(_team), CardDB.team_power_limit())
	_deck_box.add_child(_power_bar)
	for st in [1, 2]:
		var classes: Array[StringName] = CardDB.GATE_CLASSES if st == 1 else CardDB.ABILITY_CLASSES
		_deck_box.add_child(_section(STEP_NAMES[st], _picked_count(st)))
		for cls in classes:
			var c: CardDef = CardDB.card(_pick.get(cls, &""))
			_deck_box.add_child(_slot(c.display_name if c != null else "", CLASS_COLORS[cls], UiTheme.card_badge(c) if c != null else "", -1, st, c.id if c != null else &"", cls))


func _section(title: String, n: int) -> Control:
	var hb := HBoxContainer.new()
	var l := VisualUtil.label(title, 14)
	l.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(l)
	var k := VisualUtil.label("%d/3" % n, 14)
	k.add_theme_color_override("font_color", Color(0.55, 0.95, 0.6) if n == 3 else Color(1.0, 0.75, 0.45))
	hb.add_child(k)
	return hb


## Слот колоды: клик — перейти к шагу (и классу) и показать карту; × — убрать из колоды.
func _slot(text: String, c: Color, right: String, element: int, step: int, id: StringName, cls: StringName) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 26)
	var filled := id != &""
	b.add_theme_stylebox_override("normal", UiTheme.box(c.darkened(0.78) if filled else Color(0.08, 0.08, 0.11, 0.6), c.darkened(0.1) if filled else c.darkened(0.55), 1, 6, 4))
	b.add_theme_stylebox_override("hover", UiTheme.box(c.darkened(0.62), c.lightened(0.2), 1, 6, 4))
	b.add_theme_stylebox_override("pressed", UiTheme.box(c.darkened(0.55), c.lightened(0.3), 1, 6, 4))
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 6
	hb.offset_right = -3
	hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	if element >= 0:
		hb.add_child(IconT.make(element, 18))
	else:
		var dot := ColorRect.new()
		dot.color = c if filled else c.darkened(0.5)
		dot.custom_minimum_size = Vector2(4, 16)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(dot)
	var l := VisualUtil.label(text, 14)
	if not filled:
		l.text = "+ " + (String(CLASS_NAMES[cls]) if cls != &"" else "существо")
		l.add_theme_color_override("font_color", c.darkened(0.15) * Color(1, 1, 1, 0.75))
	else:
		l.add_theme_color_override("font_color", c.lightened(0.55))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hb.add_child(l)
	if right != "":
		var r := VisualUtil.label(right, 13)
		r.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		r.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
		hb.add_child(r)
	if filled:
		var x := Button.new()
		x.text = "×"
		x.flat = true
		x.focus_mode = Control.FOCUS_NONE
		x.custom_minimum_size = Vector2(22, 22)
		x.add_theme_font_size_override("font_size", 16)
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			x.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		x.add_theme_color_override("font_hover_color", Color(1.0, 0.85, 0.8))
		x.add_theme_color_override("font_color", Color(1.0, 0.6, 0.55))
		x.tooltip_text = "Убрать из колоды"
		x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		x.pressed.connect(func() -> void:
			if step == 0:
				_team.erase(id)
				_drop_unfit_picks()
			else:
				_pick.erase(cls)
			_show_step(_step))
		hb.add_child(x)
	b.tooltip_text = ("Показать «%s»" % text) if filled else ("Выбрать: " + (String(CLASS_NAMES[cls]) if cls != &"" else "существо"))
	b.pressed.connect(func() -> void:
		if step != _step or (cls != &"" and _filter != &"" and _filter != cls):
			_filter = &""
			_show_step(step)
		if filled:
			_focus_id = id
			_show_preview(id, false))
	if filled:
		b.mouse_entered.connect(func() -> void:
			if step == _step:
				_on_hover(id, true))
		b.mouse_exited.connect(func() -> void:
			if step == _step:
				_on_hover(id, false))
	return b


# ---------------------------------------------------------------- клавиатура

func _unhandled_key_input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey) or not e.pressed or e.echo:
		return
	match (e as InputEventKey).keycode:
		KEY_1, KEY_KP_1:
			_show_step(0)
		KEY_2, KEY_KP_2:
			_show_step(1)
		KEY_3, KEY_KP_3:
			_show_step(2)
		KEY_LEFT, KEY_BACKSPACE:
			_show_step(_step - 1)
		KEY_RIGHT:
			_show_step(_step + 1)
		KEY_ENTER, KEY_KP_ENTER:
			if not _go_btn.disabled:
				_on_go()
			else:
				_show_step(_step + 1)
		KEY_R:
			pick_random()
		_:
			return
	get_viewport().set_input_as_handled()


## Случайная колода по правилам (стихия, существа, ворота, способности).
func pick_random() -> void:
	_build()
	var deck: DeckDef = CardDB.random_deck(_rng)
	_element = deck.creatures[0].attribute
	_team.clear()
	for d in deck.creatures:
		_team.append(d.id)
	_pick.clear()
	for c in deck.arena + deck.abilities:
		_pick[CardDB.card_class(c)] = c.id
	_show_step(_step)


## Для автоигры/тестов: случайная колода и старт.
func pick_random_and_start() -> void:
	pick_random()
	_on_go()


func _on_go() -> void:
	var lists: Array = _deck_lists()
	if CardDB.deck_error(lists[0], lists[1], lists[2]) != "":
		return
	last_deck = {"element": _element, "creatures": _team.duplicate(), "pick": _pick.duplicate()}
	visible = false
	_preview.release()
	var team: Array[StringName] = []
	team.assign(lists[0])
	team_chosen.emit(team)
	deck_chosen.emit(team, lists[1], lists[2])


## Полоса силы команды: заполнение до лимита, пунктир — сколько добавит существо под мышью.
class PowerBar:
	extends Control
	var power := 0
	var limit := 1
	var extra := 0

	func _init() -> void:
		custom_minimum_size = Vector2(0, 34)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		tooltip_text = ""

	func set_power(p: int, l: int) -> void:
		power = p
		limit = maxi(l, 1)
		queue_redraw()

	func set_extra(e: int) -> void:
		extra = e
		queue_redraw()

	func _draw() -> void:
		var font := get_theme_font("font", "Label")
		var over := power > limit
		var after := power + extra
		var col := Color(1.0, 0.4, 0.35) if over else (Color(0.55, 0.9, 0.55) if power >= limit * 0.85 else UiTheme.GOLD)
		draw_string(font, Vector2(0, 13), "Сила команды", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.TEXT_DIM)
		var txt := "%d / %d" % [power, limit]
		if extra > 0:
			txt = "%d → %d / %d" % [power, after, limit]
		draw_string(font, Vector2(0, 13), txt, HORIZONTAL_ALIGNMENT_RIGHT, size.x, 13, Color(1.0, 0.45, 0.4) if after > limit else Color(1.0, 0.93, 0.75))
		var r := Rect2(0, 19, size.x, 10)
		draw_rect(r, Color(0.1, 0.1, 0.14), true)
		var full := maxf(float(limit), float(maxi(power, after)))
		var k := r.size.x / full
		draw_rect(Rect2(r.position, Vector2(minf(power, limit) * k, r.size.y)), col, true)
		if over:
			draw_rect(Rect2(r.position + Vector2(limit * k, 0), Vector2((power - limit) * k, r.size.y)), Color(0.9, 0.2, 0.2), true)
		if extra > 0:
			var ec := Color(1.0, 0.35, 0.3, 0.75) if after > limit else Color(1.0, 1.0, 1.0, 0.35)
			draw_rect(Rect2(r.position + Vector2(power * k, 0), Vector2(extra * k, r.size.y)), ec, true)
		# отметка лимита
		draw_line(Vector2(limit * k, r.position.y - 3), Vector2(limit * k, r.end.y + 3), Color(1, 1, 1, 0.8), 2.0)
		draw_rect(r, Color(1, 1, 1, 0.25), false, 1.0)
