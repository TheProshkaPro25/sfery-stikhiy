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
var _counts: Array[Label] = []        # «СПОСОБНОСТИ ●●○ 2/3» под силой (лимит карт на бой)
var _shown: Array[float] = [0.0, 0.0]
var _vs: Label
var _target: Array[int] = [0, 0]     # последние заданные силы (для всплывающих +/−)
var _chain: HBoxContainer            # лента карт боя: «Пожирающий жар → Волчья хватка → ПАС»
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
		var cn := VisualUtil.label("", 15)
		cn.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		cn.custom_minimum_size = Vector2(300, 0)  # ширина не скачет от «ПАС»/«▶»
		for l in [n, a, pw, cn]:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if side == 0 else HORIZONTAL_ALIGNMENT_RIGHT
			vb.add_child(l)
		_counts.append(cn)
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
	_chain = HBoxContainer.new()
	_chain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chain.add_theme_constant_override("separation", 6)
	_chain.alignment = BoxContainer.ALIGNMENT_CENTER
	_chain.anchor_left = 0.0
	_chain.anchor_right = 1.0
	_chain.offset_top = BAR_H + 108.0
	_chain.offset_bottom = BAR_H + 146.0
	add_child(_chain)


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
func open(names: Array, attrs: Array, powers: Array, momentum: Array = [0, 0]) -> void:
	_build()
	_open = true
	_target = [0, 0]
	set_chain([], [false, false])
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
		if momentum.size() == 2 and int(momentum[side]) > 0:
			_attrs[side].text += "  ·  НАТИСК +%d" % int(momentum[side])
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


## Сила бойцов: числа «бегут» к новым значениям, разница всплывает над плашкой (+120 / −80) с пружиной.
func set_powers(powers: Array) -> void:
	if not _open:
		return
	for side in range(2):
		var to: float = float(powers[side])
		var tw := create_tween()
		tw.tween_method(_set_shown.bind(side), _shown[side], to, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		var delta: int = int(to) - _target[side]
		if _target[side] > 0 and delta != 0:
			_pulse(_powers[side], Color(0.6, 1.0, 0.6) if delta > 0 else Color(1.0, 0.45, 0.4))
			_float_number(side, delta)
		_target[side] = int(to)


## Всплывающее число изменения силы: выскакивает с пружиной, плывёт вверх и гаснет.
func _float_number(side: int, delta: int) -> void:
	var p: PanelContainer = _plates[side]
	var l := VisualUtil.label(("+%d" if delta > 0 else "−%d") % absi(delta), 54)
	l.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55) if delta > 0 else Color(1.0, 0.4, 0.35))
	l.add_theme_constant_override("outline_size", 14)
	add_child(l)
	l.size = l.get_minimum_size()
	l.pivot_offset = l.size * 0.5
	var x: float = p.position.x + (p.size.x * 0.5 if side == 0 else p.size.x * 0.5) - l.size.x * 0.5
	var y: float = p.position.y + p.size.y + 4.0
	l.position = Vector2(x, y)
	l.scale = Vector2(0.2, 0.2)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "position:y", y + 40.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.35)
	tw.tween_callback(l.queue_free)


## Лента карт боя по порядку (прикреплённые — первыми): plays — [[сторона, card_id], ...], passed — кто спасовал.
## Лента карт боя и счётчики «Способности N/3» на плашках. turn — чья очередь обмена (сторона, -1 — ничья).
func set_chain(plays: Array, passed: Array, turn: int = -1) -> void:
	_build()
	VisualUtil.clear_children(_chain)
	var used: Array[int] = [0, 0]
	for pl in plays:
		var side: int = int(pl[0])
		used[side] += 1
		var c: CardDef = CardDB.card(StringName(pl[1]))
		_chain.add_child(_chip(c.display_name if c != null else str(pl[1]), side))
	for side in range(2):
		if side < passed.size() and bool(passed[side]):
			_chain.add_child(_chip("ПАС", side, true))
	_chain.visible = _open and _chain.get_child_count() > 0
	for side in range(2):
		_set_count(side, used[side], side < passed.size() and bool(passed[side]), side == turn)


## Счётчик карт стороны: закрашенные кружки — сыгранные (с прикреплёнными), «ПАС» — сторона вышла из обмена.
func _set_count(side: int, used: int, passed: bool, turn: bool) -> void:
	var cap: int = MatchController.MAX_BATTLE_ABILITIES
	var dots := ""
	for i in range(cap):
		dots += "●" if i < used else "○"
	var t := "СПОСОБНОСТИ %s %d/%d" % [dots, mini(used, cap), cap]
	if passed:
		t += "  ·  ПАС"
	elif turn:
		t = ("▶ " + t) if side == 0 else (t + " ◀")
	var l: Label = _counts[side]
	var was: String = l.text
	l.text = t
	var c: Color = UiTheme.TEXT_DIM
	if turn and not passed:
		c = UiTheme.GOLD
	elif used >= cap:
		c = Color(1.0, 0.75, 0.45)
	l.add_theme_color_override("font_color", c)
	if was != "" and was != t and _open:
		_pulse(l, Color(1.4, 1.3, 1.0))


func _chip(text: String, side: int, dim: bool = false) -> Control:
	var c: Color = Color(0.5, 0.75, 1.0) if side == 0 else Color(1.0, 0.55, 0.5)
	if dim:
		c = c.darkened(0.35)
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_theme_stylebox_override("panel", UiTheme.box(Color(c.r * 0.15, c.g * 0.15, c.b * 0.15, 0.9), c, 2, 6, 5))
	var l := VisualUtil.label(text, 16)
	l.add_theme_color_override("font_color", c.lightened(0.4))
	pc.add_child(l)
	pc.pivot_offset = Vector2(40, 14)
	pc.scale = Vector2(0.4, 0.4)
	pc.create_tween().tween_property(pc, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return pc


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
## winner_side -1 — победителя нет (бой прерван или выбыли оба): обе плашки гаснут.
func resolve(winner_side: int) -> void:
	if not _open:
		return
	if winner_side < 0:
		var tw0 := create_tween().set_parallel(true)
		for pl in _plates:
			tw0.tween_property(pl, "modulate", Color(0.55, 0.55, 0.6, 0.7), 0.3)
		_vs.visible = false
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
	_chain.visible = false


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
	_chain.visible = false
