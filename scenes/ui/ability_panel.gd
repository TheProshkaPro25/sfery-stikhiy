class_name AbilityPanel
extends Control
## Рука карт способностей внизу экрана, веером, как настоящие карты в руке.
## Вне боя рука опущена (видны верхушки карт); наведение поднимает карту. В окне способностей рука
## поднимается, доступные карты светятся, остальные гаснут; сыгранная карта вылетает к центру экрана.

signal ability_chosen(card_id: StringName)
signal passed

const CARD := Vector2(138, 193)
const FAN_H := 300.0
const PEEK := 84.0          # сколько карты видно в опущенной руке
const SPREAD_DEG := 7.0     # поворот соседних карт
const STEP_X := 112.0       # шаг карт по горизонтали

var _fan: Control
var _caption: Label
var _panel: PanelContainer   # заголовок окна способностей и «Пас»; виден только в окне
var _title: Label
var _cards: Array[CardView] = []
var _hand: Array[StringName] = []
var _legal: Array[StringName] = []
var _window := false
var _hovered: CardView = null
var _built := false


func _ready() -> void:
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	VisualUtil.full_rect_ignore(self)
	theme = UiTheme.get_theme()

	_fan = Control.new()
	_fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fan.anchor_left = 0.5
	_fan.anchor_right = 0.5
	_fan.anchor_top = 1.0
	_fan.anchor_bottom = 1.0
	_fan.offset_left = -450.0
	_fan.offset_right = 450.0
	_fan.offset_top = -FAN_H
	_fan.offset_bottom = 0.0
	_fan.visible = false
	add_child(_fan)

	_caption = VisualUtil.label("Ваши способности", 13)
	_caption.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.position = Vector2(0, FAN_H - PEEK - 26.0)
	_caption.size = Vector2(900, 20)
	_fan.add_child(_caption)

	_panel = PanelContainer.new()
	VisualUtil.place(_panel, 0.5, 1.0, 0.0, -FAN_H + 8.0)
	add_child(_panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	_panel.add_child(hb)
	_title = VisualUtil.label("", 18)
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(440, 0)
	hb.add_child(_title)
	var pb := Button.new()
	pb.text = "Пас"
	pb.custom_minimum_size = Vector2(110, 44)
	pb.pressed.connect(_on_pass)
	hb.add_child(pb)
	_panel.visible = false


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


## entries: [{id:StringName, name:String, text:String}] - доступные сейчас карты.
func show_options(entries: Array, header: String = "Окно способностей") -> void:
	_build()
	_legal.clear()
	for e in entries:
		var cid := StringName(str(e["id"]))
		_legal.append(cid)
		if not _hand.has(cid):
			_hand.append(cid)
	_title.text = header
	_window = true
	_panel.visible = true
	_fan.visible = true
	_rebuild()


func hide_panel() -> void:
	_build()
	_window = false
	_legal.clear()
	_panel.visible = false
	_layout(true)
	for cv in _cards:
		cv.set_dimmed(false)


## Показать или скрыть руку целиком (меню, конец игры).
func set_dock_visible(on: bool) -> void:
	_build()
	_fan.visible = on


## Карта, сыгранная соперником: появляется сверху по центру и гаснет.
func show_played(card_id: StringName, by_opponent: bool) -> void:
	var def: CardDef = CardDB.card(card_id)
	if def == null or not by_opponent:
		return
	var cv := CardView.new().for_card(def, CARD)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cv)
	var vp := get_viewport_rect().size
	cv.pivot_offset = CARD * 0.5
	cv.position = Vector2(vp.x * 0.5 - CARD.x * 0.5, -CARD.y)
	cv.scale = Vector2(0.8, 0.8)
	var tw := cv.create_tween()
	tw.tween_property(cv, "position:y", vp.y * 0.16, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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
		var cv := CardView.new().for_card(def, CARD)
		cv.pivot_offset = Vector2(CARD.x * 0.5, CARD.y)
		cv.mouse_entered.connect(_on_hover.bind(cv, true))
		cv.mouse_exited.connect(_on_hover.bind(cv, false))
		cv.pressed.connect(_on_card_pressed.bind(cv))
		if _window:
			cv.set_dimmed(not _legal.has(cid))
		_fan.add_child(cv)
		_cards.append(cv)
	_caption.text = "Ваши способности" if not _hand.is_empty() else "Способностей не осталось"
	_layout(false)


## Раскладка веером. Опущенная рука (вне окна) показывает только верх карт.
func _layout(animate: bool) -> void:
	var n: int = _cards.size()
	var mid: float = (n - 1) * 0.5
	_caption.visible = false  # карты говорят сами за себя; подпись мешала панелям над рукой
	for i in range(n):
		var cv: CardView = _cards[i]
		var k: float = i - mid
		var raised: bool = _window or cv == _hovered
		var top: float = FAN_H - CARD.y - 18.0 if raised else FAN_H - PEEK
		if cv == _hovered:
			top -= 22.0
		var pos := Vector2(450.0 + k * STEP_X - CARD.x * 0.5, top + k * k * 5.0)
		var rot: float = 0.0 if cv == _hovered else deg_to_rad(k * SPREAD_DEG)
		var sc: Vector2 = Vector2(1.15, 1.15) if cv == _hovered else Vector2.ONE
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
	if not (_window and _legal.has(cid)):
		return
	_window = false
	_panel.visible = false
	# сыгранная карта вылетает к центру экрана и гаснет, остальные опускаются
	_cards.erase(cv)
	_hand.erase(cid)
	var gp := cv.global_position
	_fan.remove_child(cv)
	add_child(cv)
	cv.global_position = gp
	cv.z_index = 20
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := get_viewport_rect().size
	var tw := cv.create_tween()
	tw.tween_property(cv, "position", Vector2(vp.x * 0.5 - CARD.x * 0.5, vp.y * 0.28), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(cv, "rotation", 0.0, 0.3)
	tw.parallel().tween_property(cv, "scale", Vector2(1.5, 1.5), 0.3)
	tw.tween_interval(0.5)
	tw.tween_property(cv, "modulate:a", 0.0, 0.3)
	tw.tween_callback(cv.queue_free)
	for c in _cards:
		c.set_dimmed(false)
	_layout(true)
	ability_chosen.emit(cid)


func _on_pass() -> void:
	passed.emit()
