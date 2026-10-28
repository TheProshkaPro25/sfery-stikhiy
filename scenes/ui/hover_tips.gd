class_name HoverTips
extends Control
## Подсказки для 3D-объектов (карты ворот, существа, шар): каждый кадр спрашивает у resolver, что под мышью.
## resolver(mouse: Vector2) -> {key: String, lines: Array} (lines — формат UiTheme.help_panel) или {}.
## Появляется через DELAY секунд наведения, без мерцания (короткая «прощальная» задержка), не залезает на руку карт.

const DELAY := 0.3
const GRACE := 0.12       # сколько держим подсказку, когда курсор на миг ушёл с объекта
const HAND_ZONE := 190.0  # нижняя полоса экрана под руку карт

var resolver: Callable
var _key := ""
var _wait := 0.0
var _lost := 0.0
var _panel: Control = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()


func _process(delta: float) -> void:
	var vp := get_viewport()
	var mp: Vector2 = vp.get_mouse_position()
	var blocked: bool = vp.gui_get_hovered_control() != null or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or not resolver.is_valid()
	var hit: Dictionary = {} if blocked else resolver.call(mp)
	if hit.is_empty():
		_lost += delta
		if _lost > GRACE:
			_clear()
		elif _panel != null:
			_move(mp)
		return
	_lost = 0.0
	var k: String = str(hit["key"])
	if k != _key:
		_clear()
		_key = k
		_wait = 0.0
	if _panel == null:
		_wait += delta
		if _wait >= DELAY:
			_panel = UiTheme.help_panel(hit["lines"])
			_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_panel.modulate.a = 0.0
			add_child(_panel)
			_panel.create_tween().tween_property(_panel, "modulate:a", 1.0, 0.12)
	if _panel != null:
		_move(mp)


func _clear() -> void:
	_key = ""
	_wait = 0.0
	if _panel != null:
		_panel.queue_free()
		_panel = null


## Панель рядом с курсором: правее и ниже, внутри экрана и выше полосы руки карт.
func _move(mp: Vector2) -> void:
	var vs: Vector2 = get_viewport_rect().size
	var sz: Vector2 = _panel.get_combined_minimum_size()
	var pos := mp + Vector2(20.0, 22.0)
	if pos.x + sz.x > vs.x - 8.0:
		pos.x = mp.x - sz.x - 20.0
	pos.y = minf(pos.y, vs.y - HAND_ZONE - sz.y)
	pos.y = maxf(pos.y, 8.0)
	pos.x = maxf(pos.x, 8.0)
	_panel.position = pos
