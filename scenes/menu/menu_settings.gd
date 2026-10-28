class_name MenuSettings
extends Control
## Окно «Настройки» главного меню: уровень графики и лимит кадров (GraphicsSettings, применяются сразу и к пейзажу),
## громкость эффектов и музыки (AudioSettings). Всё сохраняется в user://settings.cfg.

signal closed

var city: MenuCity
var _built := false
var _first: Control
var _last_preview := 0


func _ready() -> void:
	_build()


func open() -> void:
	_build()
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)
	_first.grab_focus()


func close() -> void:
	visible = false
	closed.emit()


func _build() -> void:
	if _built:
		return
	_built = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0.02, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			close())
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(540, 0)
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	var t := VisualUtil.label("Настройки", 28)
	t.add_theme_color_override("font_color", UiTheme.GOLD)
	vb.add_child(t)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 12)
	vb.add_child(grid)

	var gfx := OptionButton.new()
	for n in GraphicsSettings.NAMES:
		gfx.add_item(n)
	gfx.select(GraphicsSettings.current())
	gfx.item_selected.connect(func(i: int) -> void:
		GraphicsSettings.set_level(i)
		if city != null:
			city.apply_quality(i))
	_row(grid, "Графика", gfx)
	_first = gfx

	var fps := OptionButton.new()
	for v in GraphicsSettings.FPS_OPTIONS:
		fps.add_item(GraphicsSettings.fps_name(v))
	fps.select(maxi(GraphicsSettings.FPS_OPTIONS.find(GraphicsSettings.fps_limit()), 0))
	fps.item_selected.connect(func(i: int) -> void: GraphicsSettings.set_fps(GraphicsSettings.FPS_OPTIONS[i]))
	_row(grid, "Лимит кадров", fps)

	_row(grid, "Звуки", _slider(AudioSettings.sfx, "SFX"))
	_row(grid, "Музыка", _slider(AudioSettings.music, "Music"))

	var note := VisualUtil.label("Уровень графики действует и в бою. «Низкие» — без теней и свечения.", 14)
	note.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(500, 0)
	vb.add_child(note)

	var done := Button.new()
	done.text = "Готово"
	done.custom_minimum_size = Vector2(160, 46)
	done.size_flags_horizontal = Control.SIZE_SHRINK_END
	done.pressed.connect(close)
	vb.add_child(done)


func _row(grid: GridContainer, title: String, ctrl: Control) -> void:
	var l := VisualUtil.label(title, 19)
	grid.add_child(l)
	ctrl.custom_minimum_size = Vector2(280, 40)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(ctrl)


func _slider(v: float, bus_name: String) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 5
	s.value = roundf(maxf(v, 0.0) * 100.0) if v >= 0.0 else 100.0
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(x: float) -> void:
		AudioSettings.set_volume(bus_name, x / 100.0)
		# короткий щелчок для пробы громкости эффектов (не чаще 4 раз в секунду)
		if bus_name == "SFX" and Time.get_ticks_msec() - _last_preview > 250:
			_last_preview = Time.get_ticks_msec()
			SoundFx.i().play("ui_click", -4.0))
	return s
