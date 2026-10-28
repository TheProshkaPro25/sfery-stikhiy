class_name TeamMenu
extends Control
## Сборка колоды по правилам Бакугана: боец одной стихии — 3 существа этой стихии,
## 3 карты ворот (золотая, серебряная, бронзовая) и 3 способности (красная, синяя, зелёная).
## Три шага: стихия и существа → ворота → способности.

signal team_chosen(ids: Array[StringName])
signal deck_chosen(creatures: Array[StringName], arena: Array[StringName], abilities: Array[StringName])

const MAX_TEAM := 3
const CLASS_NAMES := {
	&"gold": "Золотые ворота", &"silver": "Серебряные ворота", &"bronze": "Бронзовые ворота",
	&"red": "Красная (стихия)", &"blue": "Синяя (сила G)", &"green": "Зелёная (ситуация)",
}
const CLASS_COLORS := {
	&"gold": Color(1.0, 0.82, 0.35), &"silver": Color(0.8, 0.84, 0.9), &"bronze": Color(0.85, 0.55, 0.3),
	&"red": Color(1.0, 0.4, 0.35), &"blue": Color(0.45, 0.65, 1.0), &"green": Color(0.45, 0.9, 0.55),
}

## Последняя собранная колода (переживает перезагрузку сцены).
static var last_deck: Dictionary = {}
## Сложность ИИ (AIPlayer.Difficulty): выбирается в меню, переживает перезагрузку сцены.
static var difficulty: int = AIPlayer.Difficulty.NORMAL
const DIFF_TIPS := [
	"Новичок: бросает неточно, не прикрепляет карты, плохо читает ловушки.",
	"Боец: обычная точность, отвечает на способности, иногда блефует воротами.",
	"Мастер: точный бросок, держит запас силы на ответ, ставит ловушки-приманки.",
]

var _element: int = 0
var _team: Array[StringName] = []
var _pick: Dictionary = {}   # класс карты -> id
var _step: int = 0
var _rng := RandomNumberGenerator.new()
var _built := false

var _title: Label
var _page: Control
var _summary: HBoxContainer
var _error: Label
var _back_btn: Button
var _next_btn: Button
var _go_btn: Button


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
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)

	var head := HBoxContainer.new()
	vb.add_child(head)
	var logo := VisualUtil.label("Сферы Стихий", 30)
	logo.add_theme_color_override("font_color", UiTheme.GOLD)
	head.add_child(logo)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_title = VisualUtil.label("", 20)
	head.add_child(_title)
	var help_btn := Button.new()
	help_btn.text = "Как играть"
	help_btn.custom_minimum_size = Vector2(140, 40)
	help_btn.pressed.connect(func() -> void: HelpOverlay.open_on(self))
	head.add_child(help_btn)

	_page = VBoxContainer.new()
	_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(_page as VBoxContainer).add_theme_constant_override("separation", 10)
	vb.add_child(_page)

	var deck_row := PanelContainer.new()
	vb.add_child(deck_row)
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 10)
	deck_row.add_child(drow)
	var dl := VisualUtil.label("Колода:", 16)
	drow.add_child(dl)
	_summary = HBoxContainer.new()
	_summary.add_theme_constant_override("separation", 6)
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drow.add_child(_summary)

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 14)
	vb.add_child(bottom)
	_error = VisualUtil.label("", 15)
	_error.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
	_error.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_error)
	var dl2 := VisualUtil.label("Соперник:", 16)
	bottom.add_child(dl2)
	var grp := ButtonGroup.new()
	for d in range(3):
		var db := _button(AIPlayer.difficulty_name(d), 110)
		db.toggle_mode = true
		db.button_group = grp
		db.button_pressed = d == difficulty
		db.tooltip_text = DIFF_TIPS[d]
		db.pressed.connect(func() -> void: difficulty = d)
		bottom.add_child(db)
	# уровень графики: Низкие → Средние → Высокие, сохраняется в user://settings.cfg и применяется сразу
	var gfx := _button("Графика: " + GraphicsSettings.level_name(), 170)
	gfx.tooltip_text = "Низкие — без SSAO, тени проще, меньше искр.\nСредние — почти как Высокие, легче для GTX 1060.\nВысокие — 4 каскада теней, SSAO, сглаживание MSAA 2×."
	gfx.pressed.connect(func() -> void:
		GraphicsSettings.set_level((GraphicsSettings.current() + 1) % 3)
		gfx.text = "Графика: " + GraphicsSettings.level_name()
		var m := get_tree().current_scene
		if m != null and m.has_method("apply_graphics"):
			m.apply_graphics())
	bottom.add_child(gfx)
	# ограничитель кадров: 60 / 90 / 120 / 144 / без лимита, применяется сразу
	var fps := _button("FPS: " + GraphicsSettings.fps_name(), 150)
	fps.tooltip_text = "Предел кадров в секунду. Меньше — тише вентилятор и дольше батарея."
	fps.pressed.connect(func() -> void:
		GraphicsSettings.next_fps()
		fps.text = "FPS: " + GraphicsSettings.fps_name())
	bottom.add_child(fps)
	var rnd := _button("Случайная колода", 190)
	rnd.pressed.connect(pick_random)
	bottom.add_child(rnd)
	_back_btn = _button("Назад", 120)
	_back_btn.pressed.connect(func() -> void: _show_step(_step - 1))
	bottom.add_child(_back_btn)
	_next_btn = _button("Далее", 140)
	_next_btn.pressed.connect(func() -> void: _show_step(_step + 1))
	bottom.add_child(_next_btn)
	_go_btn = _button("В бой", 160)
	_go_btn.pressed.connect(_on_go)
	bottom.add_child(_go_btn)

	if last_deck.is_empty():
		pick_random()
	else:
		_element = int(last_deck["element"])
		_team.assign(last_deck["creatures"])
		_pick = (last_deck["pick"] as Dictionary).duplicate()
		_show_step(0)


func _button(text: String, w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 44)
	return b


# ---------------------------------------------------------------- шаги

func _show_step(step: int) -> void:
	_step = clampi(step, 0, 2)
	VisualUtil.clear_children(_page)
	match _step:
		0:
			_title.text = "Шаг 1 из 3 · Стихия бойца и 3 существа"
			_build_creatures_page()
		1:
			_title.text = "Шаг 2 из 3 · Карты ворот: по одной каждого класса"
			_build_cards_page(CardDef.Kind.ARENA, CardDB.GATE_CLASSES)
		2:
			_title.text = "Шаг 3 из 3 · Способности: по одной каждого цвета"
			_build_cards_page(CardDef.Kind.ABILITY, CardDB.ABILITY_CLASSES)
	_back_btn.disabled = _step == 0
	_next_btn.disabled = _step == 2
	_refresh()


func _build_creatures_page() -> void:
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 8)
	_page.add_child(tabs)
	for a in range(6):
		var b := Button.new()
		b.text = VisualUtil.attr_name(a)
		b.toggle_mode = true
		b.button_pressed = a == _element
		b.custom_minimum_size = Vector2(150, 46)
		b.add_theme_color_override("font_color", VisualUtil.attr_color(a).lightened(0.3))
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.pressed.connect(_on_element.bind(a))
		tabs.add_child(b)
	var hint := VisualUtil.label("Боец играет одной стихией: все три существа — %s. Цикл: Пламя > Буря > Свет > Камень > Тень > Прилив > Пламя" % VisualUtil.attr_name(_element), 15)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_page.add_child(hint)
	# 8 видов стихии: сетка 4×2 по центру
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page.add_child(center)
	var row := GridContainer.new()
	row.columns = 4
	row.add_theme_constant_override("h_separation", 16)
	row.add_theme_constant_override("v_separation", 12)
	center.add_child(row)
	for id in CardDB.creatures_of(_element):
		var cv := CardView.new().for_creature(CardDB.creature(id), -1, "", Vector2(150, 210))
		cv.toggle_mode = true
		cv.button_pressed = _team.has(id)
		if _team.size() >= MAX_TEAM and not _team.has(id):
			cv.modulate = Color(1, 1, 1, 0.45)
		cv.pressed.connect(_on_creature.bind(id))
		cv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(cv)


func _build_cards_page(kind: int, classes: Array[StringName]) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page.add_child(row)
	for cls in classes:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 8)
		row.add_child(col)
		var head := VisualUtil.label(String(CLASS_NAMES[cls]), 18)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_theme_color_override("font_color", CLASS_COLORS[cls])
		col.add_child(head)
		var ids: Array[StringName] = CardDB.cards_of(kind, cls, _element)
		var grid := GridContainer.new()
		grid.columns = clampi(ceili(ids.size() / 2.0), 1, 4)
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 10)
		col.add_child(grid)
		for id in ids:
			var cv := CardView.new().for_card(CardDB.card(id), Vector2(116, 162))
			cv.toggle_mode = true
			cv.button_pressed = _pick.get(cls, &"") == id
			if _pick.has(cls) and _pick[cls] != id:
				cv.modulate = Color(1, 1, 1, 0.45)
			cv.pressed.connect(_on_card.bind(cls, id))
			grid.add_child(cv)


# ---------------------------------------------------------------- выбор

func _on_element(a: int) -> void:
	if a == _element:
		_show_step(0)
		return
	_element = a
	_team.clear()
	_pick.erase(&"red")  # красная способность привязана к стихии
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
	_show_step(0)


func _on_card(cls: StringName, id: StringName) -> void:
	_pick[cls] = id
	_show_step(_step)


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


func _refresh() -> void:
	VisualUtil.clear_children(_summary)
	for id in _team:
		_summary.add_child(_chip(CardDB.creature(id).display_name, VisualUtil.attr_color(_element)))
	for cls in CardDB.GATE_CLASSES + CardDB.ABILITY_CLASSES:
		var c: CardDef = CardDB.card(_pick.get(cls, &""))
		_summary.add_child(_chip(c.display_name if c != null else "—", CLASS_COLORS[cls]))
	var power := VisualUtil.label("Сила: %d / %d" % [CardDB.team_power(_team), CardDB.team_power_limit()], 15)
	_summary.add_child(power)
	var lists: Array = _deck_lists()
	var err: String = CardDB.deck_error(lists[0], lists[1], lists[2])
	_error.text = err
	_go_btn.disabled = err != ""


func _chip(text: String, c: Color) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.box(c.darkened(0.7), c, 1, 6, 5))
	var l := VisualUtil.label(text, 13)
	l.add_theme_color_override("font_color", c.lightened(0.4))
	p.add_child(l)
	return p


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
	var team: Array[StringName] = []
	team.assign(lists[0])
	team_chosen.emit(team)
	deck_chosen.emit(team, lists[1], lists[2])
