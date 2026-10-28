class_name GameOverUI
extends Control
## Экран конца игры с кнопкой новой партии.

signal restart_requested

var _dim: ColorRect
var _panel: PanelContainer
var _title: Label
var _sub: Label
var _built := false


func _ready() -> void:
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	VisualUtil.full_rect_ignore(self)
	theme = UiTheme.get_theme()
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	add_child(_dim)
	_panel = PanelContainer.new()
	VisualUtil.place(_panel, 0.5, 0.5, 0.0, 0.0)
	_panel.visible = false
	add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.custom_minimum_size = Vector2(380, 0)
	_panel.add_child(vb)
	_title = VisualUtil.label("", 44)
	_title.add_theme_color_override("font_color", UiTheme.GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title)
	_sub = VisualUtil.label("", 20)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_sub)
	var b := Button.new()
	b.text = "Новая игра"
	b.custom_minimum_size = Vector2(200, 50)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func() -> void: restart_requested.emit())
	vb.add_child(b)


func show_result(winner: int, reason: String) -> void:
	_build()
	if winner == 0:
		_title.text = "Победа!"
	elif winner == 1:
		_title.text = "Поражение"
	else:
		_title.text = "Ничья"
	_sub.text = reason
	_dim.visible = true
	_panel.visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.call_deferred("reset_size")
