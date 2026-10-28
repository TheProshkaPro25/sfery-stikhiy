class_name BattleOverlay
extends Control
## Итог боя: силы, разбивка модификаторов, победитель. Закрывается кнопкой или по таймеру.

signal closed

const AUTO_CLOSE_SEC := 5.0  # минимум; для длинных разборов добавляется время на строку

var _dim: ColorRect
var _panel: PanelContainer
var _vbox: VBoxContainer
var _open := false
var _seq := 0
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
	_dim.color = Color(0, 0, 0, 0.45)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	add_child(_dim)
	_panel = PanelContainer.new()
	VisualUtil.place(_panel, 0.5, 0.5, 0.0, 0.0)
	_panel.visible = false
	add_child(_panel)
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 6)
	_vbox.custom_minimum_size = Vector2(460, 0)
	_panel.add_child(_vbox)


## names: словарь uid -> строка (имя существа). Возвращает сигнал closed.
func show_result(r: BattleResult, names: Dictionary = {}) -> Signal:
	_build()
	VisualUtil.clear_children(_vbox)
	var an: String = str(names.get(r.attacker_uid, "Атакующий"))
	var dn: String = str(names.get(r.defender_uid, "Защитник"))
	var wn: String = an if r.winner_uid == r.attacker_uid else dn

	var head := VisualUtil.label("Бой: %s против %s" % [an, dn], 26)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(head)
	var pa: int = 0
	var pd: int = 0
	if r.powers.size() >= 2:
		pa = int(r.powers[0])
		pd = int(r.powers[1])
	var powers := VisualUtil.label("Сила: %s %d  -  %d %s" % [an, pa, pd, dn], 22)
	powers.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(powers)

	var traps_shown: Dictionary = {}
	for line in r.breakdown:
		var side: int = int(line.get("side", 0))
		var src0: String = str(line.get("source", ""))
		# ловушка ворот без изменения силы пишется ядром по строке на сторону — показываем одной строкой
		if src0.begins_with("trap:") and int(line.get("delta", 0)) == 0:
			if not traps_shown.has(src0):
				traps_shown[src0] = true
				var tl := VisualUtil.label(_trap_text(StringName(src0.substr(5))), 16)
				tl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
				_vbox.add_child(tl)
			continue
		var who := "Атака" if side == 0 else "Защита"
		var delta: int = int(line.get("delta", 0))
		var sign_s := "+" if delta >= 0 else ""
		var src: String = str(line.get("source", ""))
		var txt: String = "%s: %s" % [who, _pretty_source(src)]
		if delta != 0 or src == "base":
			txt += " %s%d" % [sign_s, delta]
		var ll := VisualUtil.label(txt, 16)
		ll.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0) if side == 0 else Color(1.0, 0.7, 0.6))
		_vbox.add_child(ll)
	if r.final_round:
		var fr := VisualUtil.label("Финальный бой: преимущество стихии ×2", 16)
		fr.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
		_vbox.add_child(fr)
	for line in _outcome_lines(r):
		var ol := VisualUtil.label(line, 16)
		ol.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		_vbox.add_child(ol)
	if r.interrupted:
		wn = "никто — бой прерван"
	elif r.both_lose:
		wn = "никто — выбывают оба"
	var win := VisualUtil.label("Побеждает: %s" % wn, 26)
	win.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win.add_theme_color_override("font_color", UiTheme.GOLD)
	_vbox.add_child(win)

	var btn := Button.new()
	btn.text = "Дальше (Enter)"
	btn.custom_minimum_size = Vector2(190, 42)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(_close)
	_vbox.add_child(btn)

	_dim.visible = true
	_panel.visible = true
	_panel.call_deferred("reset_size")
	mouse_filter = Control.MOUSE_FILTER_STOP
	_open = true
	_seq += 1
	var my_seq := _seq
	get_tree().create_timer(AUTO_CLOSE_SEC + 0.6 * float(_vbox.get_child_count())).timeout.connect(func() -> void:
		if _open and _seq == my_seq:
			_close())
	return closed


func _card_name(id: StringName) -> String:
	var c: CardDef = CardDB.card(id)
	if c == null:
		return String(id)
	return c.display_name


## Особые исходы боя: ловушки, перенос, двойное выбывание, удержание ворот, возрождение, метки.
func _outcome_lines(r: BattleResult) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if r.mirrored:
		out.append("Зеркало: силы бойцов поменялись местами")
	if r.auto_win:
		out.append("Трон сумрака: существо Тени побеждает")
	if r.interrupted:
		out.append("Отлив: бой прерван, соперника унесло на другие ворота")
	if r.both_lose:
		out.append("Выбывают оба бойца, ворота сгорают")
	if r.winner_stays:
		out.append("Удержание: победитель остаётся на воротах")
	for side in range(2):
		if r.revive[side]:
			out.append("Возрождение: выбывшее существо вернётся")
		if r.recall[side] != &"":
			out.append("«%s»: сыгранные карты вернутся в руку" % _card_name(r.recall[side]))
	for c in r.copies:
		out.append("«%s» повторяет «%s»" % [_card_name(c[1]), _card_name(c[2])])
	if not r.marks.is_empty():
		out.append("Метки на следующий бой: %d" % r.marks.size())
	return out


## Строка ловушки ворот: название и что она сделала.
func _trap_text(id: StringName) -> String:
	var c: CardDef = CardDB.card(id)
	var act: String = ""
	if c != null:
		match String(c.effect_id):
			"mute":
				act = "сопернику владельца способности запрещены"
			"mirror":
				act = "силы бойцов поменялись местами"
			"limit":
				act = "кто сильнее %d — проигрывает" % int(c.params.get("amount", 400))
			"clash":
				act = "выбывают оба бойца"
	return "Ловушка «%s»: %s" % [_card_name(id), act] if act != "" else "Ловушка «%s»" % _card_name(id)


## Источники из BattleResult.breakdown: base, advantage, floor, arena:<id>, ability:<id>, cancelled:<id>.
func _pretty_source(src: String) -> String:
	if src == "base":
		return "базовая сила"
	if src == "advantage":
		return "преимущество атрибута"
	if src == "floor":
		return "нижняя граница"
	if src == "momentum":
		return "натиск (серия побед)"
	if src == "mark_fix":
		return "метка: сила ровно"
	if src.begins_with("rule:"):
		return "правило ворот"
	var parts: PackedStringArray = src.split(":", true, 1)
	if parts.size() == 2:
		var n: String = _card_name(StringName(parts[1]))
		match parts[0]:
			"arena":
				return "арена «%s»" % n
			"ability":
				return "способность «%s»" % n
			"cancelled":
				return "«%s» отменена" % n
			"trap":
				return "ловушка «%s»" % n
			"mark":
				return "метка «%s»" % n
	return src


func _unhandled_key_input(e: InputEvent) -> void:
	if not _open or not (e is InputEventKey):
		return
	var k := e as InputEventKey
	if k.pressed and not k.echo and k.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	if not _open:
		return
	_open = false
	_dim.visible = false
	_panel.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	closed.emit()
