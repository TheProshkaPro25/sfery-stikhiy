class_name AbilityPanel
extends Control
## Рука карт способностей внизу экрана, веером, как настоящие карты в руке.
## Вне окон рука опущена (видны верхушки карт); наведение поднимает карту.
## Три момента: «в бою» (обмен по очереди, рука поднята), «до броска» (рука приподнята, ход не ждёт),
## «после приземления» (рука поднята, можно прикрепить карту или завершить ход).
## Играбельные карты светятся и пульсируют, остальные гаснут; сыгранная карта вылетает к центру экрана.

signal ability_chosen(card_id: StringName)
signal passed

enum Mode { IDLE, WINDOW, PRETHROW }

const PEEK := 84.0          # сколько карты видно в опущенной руке
const PEEK_PRETHROW := 150.0
const SPREAD_DEG := 7.0     # поворот соседних карт
const MAX_CARDS := 3        # лимит карт на бой (MatchController.MAX_BATTLE_ABILITIES)

var _card := Vector2(150, 210)
var _fan_h := 320.0
var _step := 122.0
var _fan: Control
var _caption: Label
var _panel: PanelContainer   # заголовок окна, счётчик карт и «Пас»; виден только в окне
var _title: Label
var _note: Label
var _pips: HBoxContainer
var _pass_btn: Button
var _cards: Array[CardView] = []
var _hand: Array[StringName] = []
var _legal: Array[StringName] = []
var _mode := Mode.IDLE
var _info: Dictionary = {}
var _hovered: CardView = null
var _built := false


func _ready() -> void:
	_build()


## Размер карт зависит от высоты окна: в 1080p крупнее, в 768p компактнее.
func _calc_sizes() -> void:
	var vh: float = get_viewport_rect().size.y
	var h: float = clampf(vh * 0.255, 190.0, 262.0)
	_card = Vector2(roundf(h * 0.715), roundf(h))
	_fan_h = _card.y + 110.0
	_step = _card.x * 0.82


func _build() -> void:
	if _built:
		return
	_built = true
	VisualUtil.full_rect_ignore(self)
	theme = UiTheme.get_theme()
	_calc_sizes()

	_fan = Control.new()
	_fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fan.anchor_left = 0.5
	_fan.anchor_right = 0.5
	_fan.anchor_top = 1.0
	_fan.anchor_bottom = 1.0
	_fan.offset_left = -520.0
	_fan.offset_right = 520.0
	_fan.offset_top = -_fan_h
	_fan.offset_bottom = 0.0
	_fan.visible = false
	add_child(_fan)

	_caption = VisualUtil.label("Ваши способности", 13)
	_caption.visible = false
	_fan.add_child(_caption)

	_panel = PanelContainer.new()
	VisualUtil.place(_panel, 0.5, 1.0, 0.0, -_fan_h)
	add_child(_panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	_panel.add_child(hb)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	hb.add_child(left)
	_title = VisualUtil.label("", 18)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(430, 0)
	left.add_child(_title)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 8)
	left.add_child(prow)
	_pips = HBoxContainer.new()
	_pips.add_theme_constant_override("separation", 4)
	prow.add_child(_pips)
	_note = VisualUtil.label("", 13)
	_note.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(430, 0)
	left.add_child(_note)
	_pass_btn = Button.new()
	_pass_btn.text = "Пас"
	_pass_btn.custom_minimum_size = Vector2(130, 52)
	_pass_btn.pressed.connect(_on_pass)
	hb.add_child(_pass_btn)
	_panel.visible = false
	get_viewport().size_changed.connect(_on_resized)


## Панель над рукой: над поднятыми картами (в бою) или над приподнятой рукой (до броска).
func _place_panel() -> void:
	var y: float = -(_card.y + 52.0) if _mode == Mode.WINDOW else -(PEEK_PRETHROW + 22.0)
	_panel.offset_top = y
	_panel.offset_bottom = y


func _on_resized() -> void:
	_calc_sizes()
	_fan.offset_top = -_fan_h
	_place_panel()
	_rebuild()


## Карты способностей в руке игрока (ещё не сыгранные).
func set_hand(ids: Array) -> void:
	_build()
	var fresh: Array[StringName] = []
	for id in ids:
		if StringName(str(id)) != &"":
			fresh.append(StringName(str(id)))
	if fresh == _hand and _cards.size() == _hand.size():
		return
	_hand = fresh
	_rebuild()


## entries: [{id:StringName, name:String, text:String}] — доступные сейчас карты.
## info: {moment: &"battle"/&"pre_throw"/&"after_landing", used: сколько карт уже сыграно (из лимита 3),
## pass_text: подпись кнопки, note: пояснение под заголовком}.
func show_options(entries: Array, header: String = "Окно способностей", info: Dictionary = {}) -> void:
	_build()
	_legal.clear()
	for e in entries:
		var cid := StringName(str(e["id"]))
		_legal.append(cid)
		if not _hand.has(cid):
			_hand.append(cid)
	_info = info
	var moment: StringName = StringName(str(info.get("moment", &"battle")))
	_mode = Mode.PRETHROW if moment == &"pre_throw" else Mode.WINDOW
	_title.text = header
	_note.text = str(info.get("note", ""))
	_note.visible = _note.text != ""
	_pass_btn.visible = _mode == Mode.WINDOW
	_pass_btn.text = str(info.get("pass_text", "Пас"))
	_pass_btn.tooltip_text = str(info.get("pass_tip", ""))
	_fill_pips(int(info.get("used", 0)))
	_panel.visible = true
	_place_panel()
	_fan.visible = true
	_rebuild()


## Счётчик карт: сыгранные закрашены, оставшиеся — пустые кружки (лимит 3 на бой).
func _fill_pips(used: int) -> void:
	VisualUtil.clear_children(_pips)
	var cap := VisualUtil.label("Способности в бою:", 14)
	cap.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_pips.add_child(cap)
	for i in range(MAX_CARDS):
		var l := VisualUtil.label("●" if i < used else "○", 20)
		l.add_theme_color_override("font_color", UiTheme.GOLD if i < used else UiTheme.TEXT_DIM)
		_pips.add_child(l)
	var cnt := VisualUtil.label("%d/%d" % [mini(used, MAX_CARDS), MAX_CARDS], 14)
	cnt.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_pips.add_child(cnt)


func hide_panel() -> void:
	_build()
	_mode = Mode.IDLE
	_legal.clear()
	_panel.visible = false
	_layout(true)
	for cv in _cards:
		cv.set_dimmed(false)
		cv.set_playable(false)


## Показать или скрыть руку целиком (меню, конец игры).
func set_dock_visible(on: bool) -> void:
	_build()
	_fan.visible = on


## Карта, сыгранная соперником: появляется сверху по центру и гаснет.
func show_played(card_id: StringName, by_opponent: bool) -> void:
	var def: CardDef = CardDB.card(card_id)
	if def == null or not by_opponent:
		return
	_build()
	var cv := CardView.new().for_card(def, _card)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cv)
	var vp := get_viewport_rect().size
	cv.pivot_offset = _card * 0.5
	cv.position = Vector2(vp.x * 0.5 - _card.x * 0.5, -_card.y)
	cv.scale = Vector2(0.8, 0.8)
	var tw := cv.create_tween()
	tw.tween_property(cv, "position:y", vp.y * 0.32, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(cv, "scale", Vector2(1.25, 1.25), 0.35)
	tw.tween_interval(0.9)
	tw.tween_property(cv, "modulate:a", 0.0, 0.35)
	tw.tween_callback(cv.queue_free)


func _rebuild() -> void:
	for cv in _cards:
		cv.queue_free()
	_cards.clear()
	_hovered = null
	for cid in _hand:
		var def: CardDef = CardDB.card(cid)
		if def == null:
			continue
		var cv := CardView.new().for_card(def, _card)
		cv.pivot_offset = Vector2(_card.x * 0.5, _card.y)
		cv.mouse_entered.connect(_on_hover.bind(cv, true))
		cv.mouse_exited.connect(_on_hover.bind(cv, false))
		cv.pressed.connect(_on_card_pressed.bind(cv))
		if _mode != Mode.IDLE:
			var ok: bool = _legal.has(cid)
			cv.set_dimmed(not ok)
		_fan.add_child(cv)
		_cards.append(cv)
		if _mode != Mode.IDLE and _legal.has(cid):
			cv.set_playable(true)
	_layout(false)


## Раскладка веером. Опущенная рука показывает только верх карт; в окне играбельные карты приподняты выше.
func _layout(animate: bool) -> void:
	var n: int = _cards.size()
	var mid: float = (n - 1) * 0.5
	var peek: float = PEEK_PRETHROW if _mode == Mode.PRETHROW else PEEK
	for i in range(n):
		var cv: CardView = _cards[i]
		var k: float = i - mid
		var playable: bool = _mode != Mode.IDLE and _legal.has(cv.card_id)
		var top: float = _fan_h - peek
		if _mode == Mode.WINDOW:
			top = _fan_h - _card.y - 18.0 + (0.0 if playable else 26.0)
		elif cv == _hovered:
			top = _fan_h - _card.y - 18.0
		if cv == _hovered:
			top -= 22.0
		var pos := Vector2(520.0 + k * _step - _card.x * 0.5, top + k * k * 5.0)
		var rot: float = 0.0 if cv == _hovered else deg_to_rad(k * SPREAD_DEG)
		var sc: Vector2 = Vector2(1.12, 1.12) if cv == _hovered else Vector2.ONE
		cv.z_index = 10 if cv == _hovered else i
		if animate:
			var tw := cv.create_tween().set_parallel(true)
			tw.tween_property(cv, "position", pos, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(cv, "rotation", rot, 0.16)
			tw.tween_property(cv, "scale", sc, 0.16)
		else:
			cv.position = pos
			cv.rotation = rot
			cv.scale = sc


func _on_hover(cv: CardView, on: bool) -> void:
	if on:
		_hovered = cv
	elif _hovered == cv:
		_hovered = null
	_layout(true)


func _on_card_pressed(cv: CardView) -> void:
	var cid: StringName = cv.card_id
	if _mode == Mode.IDLE or not _legal.has(cid):
		return
	_mode = Mode.IDLE
	_panel.visible = false
	# сыгранная карта вылетает к центру экрана и гаснет, остальные опускаются
	_cards.erase(cv)
	_hand.erase(cid)
	var gp := cv.global_position
	_fan.remove_child(cv)
	add_child(cv)
	cv.global_position = gp
	cv.z_index = 20
	cv.set_playable(false)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := get_viewport_rect().size
	var tw := cv.create_tween()
	tw.tween_property(cv, "position", Vector2(vp.x * 0.5 - _card.x * 0.5, vp.y * 0.28), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(cv, "rotation", 0.0, 0.3)
	tw.parallel().tween_property(cv, "scale", Vector2(1.5, 1.5), 0.3)
	tw.tween_interval(0.5)
	tw.tween_property(cv, "modulate:a", 0.0, 0.3)
	tw.tween_callback(cv.queue_free)
	for c in _cards:
		c.set_dimmed(false)
		c.set_playable(false)
	_layout(true)
	ability_chosen.emit(cid)


func _on_pass() -> void:
	passed.emit()
