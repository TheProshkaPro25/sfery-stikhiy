class_name GameOverUI
extends Control
## Экран конца игры: заголовок, причина, таблица итогов «вы / соперник», список боёв и кнопка новой партии.

signal restart_requested

var _dim: ColorRect
var _panel: PanelContainer
var _title: Label
var _sub: Label
var _table: GridContainer
var _battles: VBoxContainer
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
	_dim.color = Color(0, 0, 0, 0.6)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	add_child(_dim)
	_panel = PanelContainer.new()
	VisualUtil.place(_panel, 0.5, 0.5, 0.0, 0.0)
	_panel.visible = false
	add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.custom_minimum_size = Vector2(520, 0)
	_panel.add_child(vb)
	_title = VisualUtil.label("", 52)
	_title.add_theme_color_override("font_color", UiTheme.GOLD)
	_title.add_theme_constant_override("outline_size", 12)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title)
	_sub = VisualUtil.label("", 18)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.custom_minimum_size = Vector2(520, 0)
	vb.add_child(_sub)
	vb.add_child(HSeparator.new())
	_table = GridContainer.new()
	_table.columns = 3
	_table.add_theme_constant_override("h_separation", 30)
	_table.add_theme_constant_override("v_separation", 2)
	_table.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(_table)
	var bh := VisualUtil.label("Бои матча", 15)
	bh.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	vb.add_child(bh)
	_battles = VBoxContainer.new()
	_battles.add_theme_constant_override("separation", 0)
	vb.add_child(_battles)
	var b := Button.new()
	b.text = "Новая игра"
	b.custom_minimum_size = Vector2(200, 50)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func() -> void: restart_requested.emit())
	vb.add_child(b)


## stats: {turns:int, alive:[a,b], captures:[a,b], wins:[a,b], abilities:[a,b], traps:int,
## battles:[{turn:int, winner:String, loser:String, wp:int, lp:int, mine:bool}]}.
func show_result(winner: int, reason: String, stats: Dictionary = {}) -> void:
	_build()
	if winner == 0:
		_title.text = "ПОБЕДА!"
	elif winner == 1:
		_title.text = "ПОРАЖЕНИЕ"
	else:
		_title.text = "НИЧЬЯ"
	_title.add_theme_color_override("font_color", UiTheme.GOLD if winner == 0 else (Color(1.0, 0.5, 0.45) if winner == 1 else UiTheme.TEXT))
	_sub.text = reason
	VisualUtil.clear_children(_table)
	VisualUtil.clear_children(_battles)
	if not stats.is_empty():
		_row("", "Вы", "Соперник", true)
		var a: Array = stats.get("alive", [0, 0])
		var c: Array = stats.get("captures", [0, 0])
		var w: Array = stats.get("wins", [0, 0])
		var ab: Array = stats.get("abilities", [0, 0])
		_row("Существ осталось", str(a[0]), str(a[1]))
		_row("Боёв выиграно", str(w[0]), str(w[1]))
		_row("Ворот захвачено", str(c[0]), str(c[1]))
		_row("Карт способностей", str(ab[0]), str(ab[1]))
		_row("Ходов в матче", str(int(stats.get("turns", 0))), "")
		var traps: int = int(stats.get("traps", 0))
		if traps > 0:
			_row("Сработало ловушек", str(traps), "")
		var hist: Array = stats.get("battles", [])
		var from: int = maxi(0, hist.size() - 6)
		for i in range(from, hist.size()):
			var e: Dictionary = hist[i]
			var l := VisualUtil.label("Ход %d: %s побеждает %s (%d : %d)" % [int(e["turn"]), e["winner"], e["loser"], int(e["wp"]), int(e["lp"])], 14)
			l.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0) if bool(e["mine"]) else Color(1.0, 0.7, 0.6))
			_battles.add_child(l)
	_dim.visible = true
	_panel.visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.call_deferred("reset_size")
	await get_tree().process_frame
	await get_tree().process_frame
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.8, 0.8)
	_panel.create_tween().tween_property(_panel, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _row(name: String, a: String, b: String, head: bool = false) -> void:
	var sz: int = 16 if head else 18
	var l0 := VisualUtil.label(name, sz)
	l0.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	l0.custom_minimum_size = Vector2(200, 0)
	var l1 := VisualUtil.label(a, sz)
	l1.add_theme_color_override("font_color", UiTheme.GOLD)
	l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l1.custom_minimum_size = Vector2(90, 0)
	var l2 := VisualUtil.label(b, sz)
	l2.add_theme_color_override("font_color", Color(1.0, 0.65, 0.6))
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l2.custom_minimum_size = Vector2(90, 0)
	_table.add_child(l0)
	_table.add_child(l1)
	_table.add_child(l2)
