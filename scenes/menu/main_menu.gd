class_name MainMenu
extends Node
## Главное меню (стартовая сцена): живой пейзаж города (MenuCity) и кнопки «Играть», «Как играть», «Настройки»,
## «Выход». «Играть» — затемнение и переход в res://scenes/main.tscn (там, как раньше, меню команды); сцена меню
## при этом освобождается целиком. Клавиатура/геймпад: фокус по кнопкам, Esc/«назад» закрывает окна.

const GAME_SCENE := "res://scenes/main.tscn"
const LOGO_SIZE := 68

var city: MenuCity
var ui: Control
var _column: VBoxContainer
var _buttons: Array[Button] = []
var _fade: ColorRect
var _clock: Label
var _settings: MenuSettings
var _help: HelpOverlay
var _leaving := false
var _mouse_hover := false


func _ready() -> void:
	SoundFx.i()
	AudioSettings.load_and_apply()
	city = MenuCity.new()
	city.name = "City"
	add_child(city)
	_build_ui()
	_appear()


func _process(_d: float) -> void:
	if _clock != null and city != null:
		_clock.text = DayCycle.clock_text(city.phase)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		if _help != null and is_instance_valid(_help):
			_help.queue_free()
			get_viewport().set_input_as_handled()
		elif _settings != null and _settings.visible:
			_settings.close()
			get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion:
		_mouse_hover = true
	elif e is InputEventKey or e is InputEventJoypadButton or e is InputEventJoypadMotion:
		_mouse_hover = false
		# первый нажатый «вниз/вверх» без фокуса — встать на «Играть»
		if get_viewport().gui_get_focus_owner() == null and not _buttons.is_empty() and not _leaving:
			if e.is_action_pressed("ui_down") or e.is_action_pressed("ui_up") or e.is_action_pressed("ui_accept"):
				_buttons[0].grab_focus()
				get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- интерфейс

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.theme = UiTheme.get_theme()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)

	# подложка слева: затемнение к краю, чтобы логотип и кнопки читались и днём, и ночью
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ssh := Shader.new()
	ssh.code = """shader_type canvas_item;
void fragment() {
	float l = 1.0 - smoothstep(0.0, 0.5, UV.x);
	float v = smoothstep(0.45, 0.9, length((UV - 0.5) * vec2(1.1, 1.0)));
	COLOR = vec4(0.01, 0.012, 0.03, clamp(l * l * 0.78 + v * 0.45, 0.0, 0.9));
}"""
	var smat := ShaderMaterial.new()
	smat.shader = ssh
	shade.material = smat
	ui.add_child(shade)

	_column = VBoxContainer.new()
	_column.anchor_top = 0.5
	_column.anchor_bottom = 0.5
	_column.anchor_left = 0.0
	_column.offset_left = 80
	_column.offset_top = -270
	_column.offset_bottom = 270
	_column.offset_right = 80 + 520
	_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_column.add_theme_constant_override("separation", 6)
	ui.add_child(_column)

	var logo := VisualUtil.label("Сферы Стихий", LOGO_SIZE)
	logo.add_theme_color_override("font_color", UiTheme.GOLD)
	logo.add_theme_color_override("font_outline_color", Color(0.10, 0.05, 0.0, 0.95))
	logo.add_theme_constant_override("outline_size", 12)
	logo.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	logo.add_theme_constant_override("shadow_offset_x", 0)
	logo.add_theme_constant_override("shadow_offset_y", 5)
	logo.add_theme_constant_override("shadow_outline_size", 18)
	_column.add_child(logo)

	# шесть стихий — цветные точки под логотипом и подзаголовок
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_column.add_child(row)
	for a in range(6):
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var c: Color = VisualUtil.attr_color(a)
		dot.add_theme_stylebox_override("panel", UiTheme.box(c, c.lightened(0.5), 1, 7, 0))
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(dot)
	var sub := VisualUtil.label("  битва шести стихий", 20)
	sub.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	row.add_child(sub)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 26)
	_column.add_child(gap)

	var panel := PanelContainer.new()
	var pst := UiTheme.box(Color(0.05, 0.05, 0.09, 0.72), UiTheme.GOLD_DIM, 2, 14, 18)
	pst.shadow_color = Color(0, 0, 0, 0.45)
	pst.shadow_size = 10
	panel.add_theme_stylebox_override("panel", pst)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_column.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	for spec in [["Играть", _on_play], ["Как играть", _on_help], ["Настройки", _on_settings], ["Выход", _on_quit]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(330, 56)
		b.add_theme_font_size_override("font_size", 24)
		b.pressed.connect(spec[1])
		b.mouse_entered.connect(b.grab_focus)
		b.focus_entered.connect(_on_focus.bind(b))
		vb.add_child(b)
		_buttons.append(b)
	_buttons[0].add_theme_color_override("font_color", UiTheme.GOLD)
	# по кругу: с «Выхода» вниз — на «Играть»
	_buttons[0].focus_neighbor_top = _buttons[-1].get_path()
	_buttons[-1].focus_neighbor_bottom = _buttons[0].get_path()

	var hint := VisualUtil.label("↑ ↓ — выбор   Enter — подтвердить   Esc — назад", 14)
	hint.add_theme_color_override("font_color", Color(UiTheme.TEXT_DIM, 0.8))
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.offset_left = 24
	hint.offset_top = -38
	hint.offset_bottom = -14
	ui.add_child(hint)

	_clock = VisualUtil.label("", 22)
	_clock.add_theme_color_override("font_color", Color(UiTheme.GOLD, 0.85))
	_clock.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_clock.offset_left = -110
	_clock.offset_right = -24
	_clock.offset_top = -44
	_clock.offset_bottom = -14
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui.add_child(_clock)

	_settings = MenuSettings.new()
	_settings.city = city
	_settings.visible = false
	_settings.closed.connect(func() -> void: _buttons[2].grab_focus())
	ui.add_child(_settings)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_fade)


## Появление: из чёрного, логотип и кнопки по очереди.
func _appear() -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 1.4).set_ease(Tween.EASE_OUT)
	_column.modulate.a = 0.0
	var x0 := _column.offset_left
	_column.offset_left = x0 - 40
	_column.offset_right -= 40
	var tc := create_tween().set_parallel()
	tc.tween_property(_column, "modulate:a", 1.0, 0.9).set_delay(0.35)
	tc.tween_property(_column, "offset_left", x0, 1.0).set_delay(0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tc.tween_property(_column, "offset_right", x0 + 520, 1.0).set_delay(0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i in range(_buttons.size()):
		var b := _buttons[i]
		b.modulate.a = 0.0
		tc.tween_property(b, "modulate:a", 1.0, 0.45).set_delay(0.7 + 0.1 * i)
	tc.chain().tween_callback(func() -> void:
		if get_viewport().gui_get_focus_owner() == null:
			_mouse_hover = true   # первый фокус — без звука
			_buttons[0].grab_focus())


func _on_focus(b: Button) -> void:
	# звук наведения с клавиатуры/геймпада (мышью его играет SoundFx по mouse_entered)
	if not _mouse_hover and b.modulate.a > 0.9:
		SoundFx.i().play("ui_hover", -10.0, 0.06)


# ---------------------------------------------------------------- кнопки

func _on_play() -> void:
	if _leaving:
		return
	_leaving = true
	for b in _buttons:
		b.disabled = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.45)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(GAME_SCENE))


func _on_help() -> void:
	_help = HelpOverlay.open_on(ui)
	for n in _help.find_children("*", "Button", true, false):
		(n as Button).grab_focus()
		break
	_help.tree_exited.connect(func() -> void:
		if is_inside_tree() and not _leaving:
			_buttons[1].grab_focus())


func _on_settings() -> void:
	_settings.open()


func _on_quit() -> void:
	_leaving = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.3)
	tw.tween_callback(get_tree().quit)
