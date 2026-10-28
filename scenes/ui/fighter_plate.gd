class_name FighterPlate
extends PanelContainer
## Плашка бойца в углу экрана: имя, шарики существ (выбитые гаснут), захваченные ворота, огоньки «Натиска».
## side 0 — слева (вы), 1 — справа (соперник); плашка скошена наружу, активный боец подсвечен.

const ElementIcon := preload("res://scenes/element_icon.gd")

var _side := 0
var _name: Label
var _gates: Label
var _pips: _Pips
var _flames: _Flames
var _accent := Color(0.5, 0.7, 1.0)
var _active := false


func _init(side: int = 0, title: String = "") -> void:
	_side = side
	mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = ("Ваша плашка. " if side == 0 else "Плашка соперника. ") + "Шарики — три существа (выбывшие перечёркнуты). Ворота — захваченные карты. Огоньки — натиск."
	_accent = Color(0.5, 0.75, 1.0) if side == 0 else Color(1.0, 0.55, 0.5)
	_apply_style(false)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	add_child(vb)
	_name = VisualUtil.label(title, 20)
	_name.add_theme_color_override("font_color", _accent.lightened(0.3))
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if side == 0 else HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(_name)
	_pips = _Pips.new()
	_pips.rtl = side == 1
	_pips.mouse_filter = Control.MOUSE_FILTER_PASS
	_pips.tooltip_text = "Существа бойца: цветной шарик — в строю, перечёркнутый — выбыл. Нужно выбить всех трёх."
	vb.add_child(_pips)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN if side == 0 else BoxContainer.ALIGNMENT_END
	vb.add_child(row)
	_gates = VisualUtil.label("Ворота: 0", 14)
	_gates.add_theme_color_override("font_color", UiTheme.GOLD)
	_gates.mouse_filter = Control.MOUSE_FILTER_PASS
	_gates.tooltip_text = "Захваченные карты ворот: ворота, где сражение выиграно или карта засчитана."
	_flames = _Flames.new()
	_flames.tooltip_text = "Натиск: серия побед подряд даёт +40, затем +80 силы в следующем бою. Поражение сбрасывает серию."
	if side == 0:
		row.add_child(_gates)
		row.add_child(_flames)
	else:
		row.add_child(_flames)
		row.add_child(_gates)


func _apply_style(active: bool) -> void:
	var c: Color = _accent
	var sb := UiTheme.box(Color(0.03, 0.03, 0.06, 0.88), c if active else c.darkened(0.45), 0, 0, 10)
	sb.border_width_left = 5 if _side == 0 else 0
	sb.border_width_right = 5 if _side == 1 else 0
	sb.border_width_bottom = 2
	sb.skew = Vector2(-0.18 if _side == 0 else 0.18, 0.0)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	sb.shadow_color = Color(c.r, c.g, c.b, 0.4 if active else 0.12)
	sb.shadow_size = 10 if active else 4
	add_theme_stylebox_override("panel", sb)


## Цвета стихий существ бойца (порядок — порядок шариков); elems — стихии (значок на шарике), можно пусто.
func set_team(colors: Array, elems: Array = []) -> void:
	_pips.colors = colors
	_pips.elems = elems
	_pips.dead.clear()
	for _i in colors.size():
		_pips.dead.append(false)
	_pips.custom_minimum_size = Vector2(colors.size() * 30.0, 28.0)
	_pips.queue_redraw()


func set_title(t: String) -> void:
	_name.text = t


## Существо с индексом idx выбыло: шарик гаснет с вспышкой.
func kill(idx: int) -> void:
	if idx < 0 or idx >= _pips.dead.size():
		return
	_pips.dead[idx] = true
	_pips.flash = 1.0
	_pips.flash_idx = idx
	var tw := create_tween()
	tw.tween_property(_pips, "flash", 0.0, 0.7)
	tw.parallel().tween_method(func(_v: float) -> void: _pips.queue_redraw(), 0.0, 1.0, 0.7)


## Существо с индексом idx вернулось в игру: шарик снова горит, с вспышкой.
func revive(idx: int) -> void:
	if idx < 0 or idx >= _pips.dead.size():
		return
	_pips.dead[idx] = false
	_pips.flash = 1.0
	_pips.flash_idx = idx
	_pop(_pips)
	var tw := create_tween()
	tw.tween_property(_pips, "flash", 0.0, 0.7)
	tw.parallel().tween_method(func(_v: float) -> void: _pips.queue_redraw(), 0.0, 1.0, 0.7)


func set_gates(n: int) -> void:
	var changed: bool = _gates.text != "Ворота: %d" % n
	_gates.text = "Ворота: %d" % n
	if changed and n > 0:
		_pop(_gates)


func set_momentum(v: int) -> void:
	_flames.value = v
	_flames.queue_redraw()
	_flames.visible = v > 0
	if v > 0:
		_pop(_flames)


func set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	_apply_style(on)


## Пружинка при изменении значения.
func _pop(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2(1.35, 1.35), 0.08)
	tw.tween_property(c, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


class _Pips extends Control:
	var colors: Array = []
	var elems: Array = []
	var dead: Array = []
	var rtl := false
	var flash := 0.0
	var flash_idx := -1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size = Vector2(90, 28)

	func _draw() -> void:
		var n: int = colors.size()
		for i in range(n):
			var k: int = (n - 1 - i) if rtl else i
			var c := Vector2(14.0 + k * 30.0, 14.0)
			var col: Color = colors[i]
			if dead[i]:
				draw_circle(c, 11.0, Color(0.12, 0.12, 0.14, 0.9))
				draw_arc(c, 11.0, 0.0, TAU, 24, Color(0.35, 0.35, 0.38), 2.0, true)
				draw_line(c + Vector2(-5, -5), c + Vector2(5, 5), Color(0.5, 0.2, 0.2), 2.0)
				draw_line(c + Vector2(-5, 5), c + Vector2(5, -5), Color(0.5, 0.2, 0.2), 2.0)
				if flash > 0.0 and i == flash_idx:
					draw_circle(c, 11.0 + (1.0 - flash) * 16.0, Color(1, 0.9, 0.7, flash * 0.6))
			else:
				if flash > 0.0 and i == flash_idx:
					draw_circle(c, 12.0 + (1.0 - flash) * 14.0, Color(1, 1, 0.8, flash * 0.5))
				for j in range(5):
					var t: float = float(j) / 4.0
					draw_circle(c + Vector2(-3, -3) * t, lerpf(12.0, 3.0, t), col.darkened(0.55).lerp(col.lightened(0.5), t))
				# знак стихии поверх шарика: тёмная тень и светлый знак
				if i < elems.size() and int(elems[i]) >= 0:
					var g: Texture2D = ElementIcon.glyph(int(elems[i]))
					draw_texture_rect(g, Rect2(c - Vector2(10, 9), Vector2(20, 20)), false, Color(0, 0, 0, 0.55))
					draw_texture_rect(g, Rect2(c - Vector2(10, 10), Vector2(20, 20)), false, Color(1.0, 0.98, 0.92, 0.95))
				draw_arc(c, 12.0, 0.0, TAU, 24, UiTheme.GOLD_DIM, 1.5, true)


class _Flames extends Control:
	var value := 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size = Vector2(46, 20)
		visible = false

	func _draw() -> void:
		for i in range(2):
			var on: bool = i < value
			var c := Vector2(10.0 + i * 22.0, 10.0)
			var col: Color = Color(1.0, 0.62, 0.2) if on else Color(0.25, 0.22, 0.2)
			# язычок пламени: капля с острым верхом
			var pts := PackedVector2Array([c + Vector2(0, -10), c + Vector2(7, 2), c + Vector2(4, 8), c + Vector2(-4, 8), c + Vector2(-7, 2)])
			draw_colored_polygon(pts, col)
			if on:
				draw_circle(c + Vector2(0, 3), 3.0, Color(1.0, 0.92, 0.6))
