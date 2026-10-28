class_name BattleHud
extends Control
## Подача боя как в аниме: чёрные полосы сверху и снизу, две скошенные плашки бойцов
## (имя, стихия, сила с бегущим счётчиком) и «VS» по центру. Итог: победитель вспыхивает, проигравший гаснет.

const BAR_H := 64.0

var _top: ColorRect
var _bot: ColorRect
var _plates: Array[PanelContainer] = []
var _names: Array[Label] = []
var _attrs: Array[Label] = []
var _powers: Array[Label] = []
var _shown: Array[float] = [0.0, 0.0]
var _vs: Label
var _open := false
var _built := false


func _ready() -> void:
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	VisualUtil.full_rect_ignore(self)
	theme = UiTheme.get_theme()
	_top = _bar(true)
	_bot = _bar(false)
	for side in range(2):
		var p := PanelContainer.new()
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", -4)
		p.add_child(vb)
		var n := VisualUtil.label("", 24)
		var a := VisualUtil.label("", 14)
		var pw := VisualUtil.label("0", 46)
		pw.add_theme_color_override("font_color", UiTheme.GOLD)
		pw.add_theme_constant_override("outline_size", 10)
		for l in [n, a, pw]:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if side == 0 else HORIZONTAL_ALIGNMENT_RIGHT
			vb.add_child(l)
		add_child(p)
		_plates.append(p)
		_names.append(n)
		_attrs.append(a)
		_powers.append(pw)
		p.visible = false
	_vs = VisualUtil.label("VS", 64)
	_vs.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	_vs.add_theme_constant_override("outline_size", 14)
	_vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vs.visible = false
	add_child(_vs)


func _bar(top: bool) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0, 0, 0, 0.92)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_left = 0.0
	r.anchor_right = 1.0
	r.anchor_top = 0.0 if top else 1.0
	r.anchor_bottom = 0.0 if top else 1.0
	r.offset_top = -BAR_H if top else 0.0
	r.offset_bottom = 0.0 if top else BAR_H
	add_child(r)
	return r


func _plate_style(c: Color, side: int) -> StyleBoxFlat:
	var sb := UiTheme.box(Color(0.03, 0.03, 0.05, 0.88), c, 0, 0, 14)
	sb.border_width_left = 6 if side == 0 else 0
	sb.border_width_right = 6 if side == 1 else 0
	sb.border_width_bottom = 2
	sb.skew = Vector2(-0.25 if side == 0 else 0.25, 0.0)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.shadow_color = Color(c.r, c.g, c.b, 0.35)
	sb.shadow_size = 12
	return sb


## Открыть подачу боя. Сторона 0 — атакующий (слева), 1 — защитник.
func open(names: Array, attrs: Array, powers: Array) -> void:
	_build()
	_open = true
	var vp := get_viewport_rect().size
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_top, "offset_top", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_top, "offset_bottom", BAR_H, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_bot, "offset_top", -BAR_H, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_bot, "offset_bottom", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for side in range(2):
		var c: Color = VisualUtil.attr_color(int(attrs[side]))
		var p: PanelContainer = _plates[side]
		p.add_theme_stylebox_override("panel", _plate_style(c, side))
		p.modulate = Color.WHITE
		_names[side].text = str(names[side])
		_attrs[side].text = ("АТАКА · " if side == 0 else "ЗАЩИТА · ") + VisualUtil.attr_name(int(attrs[side])).to_upper()
		_attrs[side].add_theme_color_override("font_color", c.lightened(0.35))
		_shown[side] = 0.0
		_powers[side].text = "0"
		p.visible = true
		p.reset_size()
		var y: float = BAR_H + 18.0
		var x_in: float = 30.0 if side == 0 else vp.x - p.size.x - 30.0
		var x_out: float = -p.size.x - 40.0 if side == 0 else vp.x + 40.0
		p.position = Vector2(x_out, y)
		tw.tween_property(p, "position:x", x_in, 0.35).set_delay(0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_vs.visible = true
	_vs.size = Vector2(200, 80)
	_vs.pivot_offset = _vs.size * 0.5
	_vs.position = Vector2(vp.x * 0.5 - 100.0, BAR_H + 22.0)
	_vs.scale = Vector2(3, 3)
	_vs.modulate.a = 0.0
	tw.tween_property(_vs, "scale", Vector2.ONE, 0.3).set_delay(0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_vs, "modulate:a", 1.0, 0.2).set_delay(0.3)
	set_powers(powers)


## Сила бойцов: числа «бегут» к новым значениям.
func set_powers(powers: Array) -> void:
	if not _open:
		return
	for side in range(2):
		var to: float = float(powers[side])
		var tw := create_tween()
		tw.tween_method(_set_shown.bind(side), _shown[side], to, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if to > _shown[side] + 0.5 and _shown[side] > 0.0:
			_pulse(_powers[side], Color(0.6, 1.0, 0.6))
		elif to < _shown[side] - 0.5:
			_pulse(_powers[side], Color(1.0, 0.45, 0.4))


func _set_shown(v: float, side: int) -> void:
	_shown[side] = v
	_powers[side].text = str(int(round(v)))


func _pulse(l: Label, c: Color) -> void:
	l.pivot_offset = l.size * 0.5
	var tw := l.create_tween()
	tw.tween_property(l, "modulate", c, 0.1)
	tw.parallel().tween_property(l, "scale", Vector2(1.25, 1.25), 0.1)
	tw.tween_property(l, "modulate", Color.WHITE, 0.35)
	tw.parallel().tween_property(l, "scale", Vector2.ONE, 0.35)


## Итог: плашка победителя вспыхивает, проигравшего гаснет.
func resolve(winner_side: int) -> void:
	if not _open:
		return
	var w: PanelContainer = _plates[winner_side]
	var l: PanelContainer = _plates[1 - winner_side]
	w.pivot_offset = w.size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(w, "scale", Vector2(1.12, 1.12), 0.15)
	tw.tween_property(w, "modulate", Color(1.6, 1.5, 1.2), 0.15)
	tw.tween_property(l, "modulate", Color(0.45, 0.45, 0.5, 0.6), 0.3)
	tw.chain().tween_property(w, "scale", Vector2.ONE, 0.25)
	tw.parallel().tween_property(w, "modulate", Color.WHITE, 0.25)
	_vs.visible = false


func close() -> void:
	if not _open:
		return
	_open = false
	var vp := get_viewport_rect().size
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_top, "offset_top", -BAR_H, 0.25)
	tw.tween_property(_top, "offset_bottom", 0.0, 0.25)
	tw.tween_property(_bot, "offset_top", 0.0, 0.25)
	tw.tween_property(_bot, "offset_bottom", BAR_H, 0.25)
	tw.tween_property(_plates[0], "position:x", -_plates[0].size.x - 40.0, 0.25)
	tw.tween_property(_plates[1], "position:x", vp.x + 40.0, 0.25)
	_vs.visible = false
