class_name HudUI
extends Control
## HUD: строка статуса, подсказка, вспышка сообщений и панель выбора существа.

signal creature_chosen(uid: int)

var _status: Label
var _hint: Label
var _hint_plate: PanelContainer
var _status_plate: PanelContainer
var _flash: Label
var _creature_panel: PanelContainer
var _creature_title: Label
var _creature_box: HBoxContainer
var _built := false


func _ready() -> void:
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	VisualUtil.full_rect_ignore(self)
	theme = UiTheme.get_theme()

	_status_plate = PanelContainer.new()
	_status_plate.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.INK, UiTheme.GOLD_DIM, 1, 8, 8))
	VisualUtil.place(_status_plate, 0.0, 0.0, 12.0, 10.0)
	_status_plate.visible = false
	add_child(_status_plate)
	_status = VisualUtil.label("", 17)
	_status_plate.add_child(_status)

	_hint_plate = PanelContainer.new()
	_hint_plate.add_theme_stylebox_override("panel", UiTheme.box(Color(0.05, 0.05, 0.09, 0.78), UiTheme.GOLD, 1, 18, 10))
	VisualUtil.place(_hint_plate, 0.5, 0.0, 0.0, 54.0)
	add_child(_hint_plate)
	_hint = VisualUtil.label("", 20)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_plate.add_child(_hint)
	_hint_plate.visible = false

	_flash = VisualUtil.label("", 34)
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash.add_theme_color_override("font_color", UiTheme.GOLD)
	_flash.add_theme_color_override("font_outline_color", Color.BLACK)
	_flash.add_theme_constant_override("outline_size", 10)
	_flash.visible = false
	VisualUtil.place(_flash, 0.5, 0.0, 0.0, 104.0)
	add_child(_flash)

	var help_btn := Button.new()
	help_btn.text = "?"
	help_btn.tooltip_text = "Как играть"
	help_btn.custom_minimum_size = Vector2(44, 44)
	VisualUtil.place(help_btn, 1.0, 0.0, -12.0, 10.0)
	help_btn.pressed.connect(func() -> void: HelpOverlay.open_on(get_parent()))
	add_child(help_btn)

	_creature_panel = PanelContainer.new()
	_creature_panel.visible = false
	VisualUtil.place(_creature_panel, 0.5, 1.0, 0.0, -96.0)  # над опущенной рукой способностей
	add_child(_creature_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	_creature_panel.add_child(vb)
	_creature_title = VisualUtil.label("Выберите существо", 20)
	_creature_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_creature_title)
	_creature_box = HBoxContainer.new()
	_creature_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_creature_box.add_theme_constant_override("separation", 10)
	vb.add_child(_creature_box)


func set_status(turn: int, active: int, captures0: int, captures1: int) -> void:
	_build()
	var who := "Ваш ход" if active == 0 else "Ход соперника"
	_status.text = "Ход %d   ·   %s   ·   Существа: вы %d / соперник %d" % [turn, who, captures0, captures1]
	_status.add_theme_color_override("font_color", UiTheme.GOLD if active == 0 else Color(1.0, 0.6, 0.55))
	_status_plate.visible = true


func set_hint(text: String) -> void:
	_build()
	_hint.text = text
	_hint_plate.visible = text != ""


func flash(text: String) -> void:
	_build()
	_flash.text = text
	_flash.visible = true


func clear_flash() -> void:
	_build()
	_flash.visible = false


## entries: [{uid:int, def:CreatureDef, note:String}] (без def - запасной вариант {uid, text}).
func show_creatures(entries: Array, title: String = "Выберите существо для броска") -> void:
	_build()
	VisualUtil.clear_children(_creature_box)
	_creature_title.text = title
	for e in entries:
		var uid: int = int(e["uid"])
		var cv := CardView.new()
		var d: CreatureDef = e.get("def")
		if d != null:
			cv.for_creature(d, uid, str(e.get("note", "")), Vector2(132, 185))
		else:
			cv.setup(str(e.get("text", "?")), "Существо", "", "", UiTheme.ARENA_NEUTRAL, UiTheme.GOLD, Vector2(132, 185))
		cv.pressed.connect(_on_creature_pressed.bind(uid))
		_creature_box.add_child(cv)
	_creature_panel.visible = true
	_creature_panel.call_deferred("reset_size")


func hide_creatures() -> void:
	_build()
	_creature_panel.visible = false
	VisualUtil.clear_children(_creature_box)


func _on_creature_pressed(uid: int) -> void:
	creature_chosen.emit(uid)


## Режим боя: статус и подсказка прячутся (их место занимают плашки бойцов), сообщения — ниже центра.
func set_battle_mode(on: bool) -> void:
	_build()
	_status_plate.modulate.a = 0.0 if on else 1.0
	_hint_plate.modulate.a = 0.0 if on else 1.0
	VisualUtil.place(_flash, 0.5, 0.42 if on else 0.0, 0.0, 0.0 if on else 104.0)


## Короткая вспышка всего экрана (удар).
func screen_flash(c: Color) -> void:
	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(r)
	var tw := r.create_tween()
	tw.tween_property(r, "color:a", 0.0, 0.35)
	tw.tween_callback(r.queue_free)


static var _coached: Dictionary = {}
var _coach: PanelContainer


## Подсказка-наставник: показывается один раз за запуск для каждого ключа.
func coach(key: String, text: String) -> void:
	_build()
	if _coached.has(key):
		return
	_coached[key] = true
	if _coach != null and is_instance_valid(_coach):
		_coach.queue_free()
	_coach = PanelContainer.new()
	_coach.add_theme_stylebox_override("panel", UiTheme.box(Color(0.03, 0.06, 0.1, 0.94), Color(0.45, 0.8, 1.0), 2, 10, 14))
	VisualUtil.place(_coach, 0.0, 0.62, 16.0, 0.0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_coach.add_child(vb)
	var head := VisualUtil.label("Подсказка", 14)
	head.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	vb.add_child(head)
	var l := VisualUtil.label(text, 15)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 0)
	vb.add_child(l)
	var b := Button.new()
	b.text = "Ясно"
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	var wr: WeakRef = weakref(_coach)
	b.pressed.connect(func() -> void:
		var pn: Object = wr.get_ref()
		if pn != null:
			pn.queue_free())
	vb.add_child(b)
	add_child(_coach)
	get_tree().create_timer(14.0).timeout.connect(func() -> void:
		var pn: Object = wr.get_ref()
		if pn != null:
			pn.queue_free())
