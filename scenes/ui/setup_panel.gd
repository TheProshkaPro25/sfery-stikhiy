class_name SetupPanel
extends Control
## Подготовка: выбрать карту арены из руки, затем слот (сетка 2x3, верхний ряд - дальний).

signal placed(card_id: StringName, slot: int)
signal placed_throw(card_id: StringName, slot: int)  # «ворота + бросок»: сразу бросить существо на эту карту
signal skipped
## Наведение на кнопку места (-1 — ушли): место на поле подсвечивается ярче.
signal slot_hovered(slot: int)

var _panel: PanelContainer
var _title: Label
var _cards_box: HBoxContainer
var _grid: GridContainer
var _slot_buttons: Array[Button] = []
var _card_buttons: Dictionary = {}
var _selected: StringName = &""
var _legal: Array = []
var _built := false
var _skip_btn: Button
var _throw_btn: Button


func _ready() -> void:
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	VisualUtil.full_rect_ignore(self)
	theme = UiTheme.get_theme()
	_panel = PanelContainer.new()
	VisualUtil.place(_panel, 0.5, 1.0, 0.0, -96.0)  # над опущенной рукой способностей
	add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	_panel.add_child(vb)
	_title = VisualUtil.label("", 20)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	vb.add_child(row)
	_cards_box = HBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 8)
	row.add_child(_cards_box)
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(right)
	var sep := VisualUtil.label("Место на поле\n(ближе к сопернику, рядом с картами)", 14)
	sep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sep.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	right.add_child(sep)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	right.add_child(_grid)
	for i in range(6):
		var b := Button.new()
		b.text = str(i + 1)
		b.custom_minimum_size = Vector2(64, 52)
		b.tooltip_text = "Место %d: %s ряд поля. Карта ляжет рубашкой вверх." % [i + 1, "дальний" if i < 3 else "ближний"]
		b.pressed.connect(_on_slot_pressed.bind(i))
		b.mouse_entered.connect(func() -> void: slot_hovered.emit(i if not b.disabled else -1))
		b.mouse_exited.connect(func() -> void: slot_hovered.emit(-1))
		_grid.add_child(b)
		_slot_buttons.append(b)
	_skip_btn = Button.new()
	_skip_btn.text = "Не класть"
	_skip_btn.custom_minimum_size = Vector2(0, 40)
	_skip_btn.pressed.connect(func() -> void: skipped.emit())
	right.add_child(_skip_btn)
	_throw_btn = Button.new()
	_throw_btn.text = "Ворота + бросок"
	_throw_btn.toggle_mode = true
	_throw_btn.custom_minimum_size = Vector2(0, 40)
	_throw_btn.tooltip_text = "Положить карту и сразу бросить на неё существо: два действия за один ход. Следующий шаг — выбрать бойца."
	right.add_child(_throw_btn)
	_panel.visible = false


## cards: [{id:StringName, name:String, text:String}]; legal_slots: индексы слотов.
func begin(cards: Array, legal_slots: Array, can_skip: bool = false, can_throw: bool = false) -> void:
	_build()
	_selected = &""
	_legal = legal_slots.duplicate()
	VisualUtil.clear_children(_cards_box)
	_card_buttons.clear()
	for c in cards:
		var cid: StringName = StringName(str(c["id"]))
		var def: CardDef = CardDB.card(cid)
		var b := CardView.new()
		if def != null:
			b.for_card(def, Vector2(124, 174))
		else:
			b.setup(str(c["name"]), "Арена", str(c.get("text", "")), "", UiTheme.ARENA_NEUTRAL, UiTheme.GOLD, Vector2(124, 174))
		b.toggle_mode = true
		b.pressed.connect(_on_card_pressed.bind(cid))
		_cards_box.add_child(b)
		_card_buttons[cid] = b
	_title.text = "Карта ворот: выберите карту, затем место — кнопкой или щелчком по полю"
	if can_throw:
		_title.text += ".\nВключите «Ворота + бросок», чтобы сразу бросить существо на неё"
	_skip_btn.visible = can_skip
	_throw_btn.visible = can_throw
	_throw_btn.button_pressed = false
	_refresh_slots()
	_panel.visible = true
	_panel.call_deferred("reset_size")


func hide_panel() -> void:
	_build()
	_panel.visible = false
	_selected = &""


func _on_card_pressed(cid: StringName) -> void:
	_selected = cid
	for k in _card_buttons.keys():
		var cb: CardView = _card_buttons[k]
		cb.button_pressed = (k == cid)
	_refresh_slots()


func _refresh_slots() -> void:
	for i in range(_slot_buttons.size()):
		_slot_buttons[i].disabled = (_selected == &"") or not _legal.has(i)


## Место выбрано щелчком по полю (Arena.slot_clicked). Без выбранной карты: единственная карта берётся сама,
## иначе заголовок просит сначала выбрать карту.
func pick_slot(slot: int) -> void:
	if not _panel.visible or not _legal.has(slot):
		return
	if _selected == &"" and _card_buttons.size() == 1:
		_on_card_pressed(_card_buttons.keys()[0])
	if _selected == &"":
		_title.text = "Сначала выберите карту ворот, затем место %d" % (slot + 1)
		return
	_on_slot_pressed(slot)


func _on_slot_pressed(slot: int) -> void:
	if _selected == &"" or not _legal.has(slot):
		return
	var cid := _selected
	_selected = &""
	if _throw_btn.visible and _throw_btn.button_pressed:
		placed_throw.emit(cid, slot)
	else:
		placed.emit(cid, slot)
