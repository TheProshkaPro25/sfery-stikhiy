class_name UiTheme
extends RefCounted
## Общая тема интерфейса: тёмные полупрозрачные панели с золотой каймой, кнопки в том же стиле.

const ElementIcon := preload("res://scenes/element_icon.gd")

const GOLD := Color(0.95, 0.80, 0.45)
const GOLD_DIM := Color(0.62, 0.50, 0.28)
const INK := Color(0.07, 0.07, 0.12, 0.88)
const TEXT := Color(0.96, 0.93, 0.86)
const TEXT_DIM := Color(0.70, 0.67, 0.62)
const ABILITY_BASE := Color(0.30, 0.16, 0.46)
const ABILITY_GLOW := Color(1.0, 0.80, 0.45)
const ARENA_NEUTRAL := Color(0.55, 0.47, 0.33)

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _make()
	return _theme


## Плашка: фон, кайма, скругление, внутренние отступы.
static func box(bg: Color, border: Color, bw: int = 2, radius: int = 10, pad: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s


static func _make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18

	var panel := box(INK, GOLD_DIM, 2, 12, 14)
	panel.shadow_color = Color(0, 0, 0, 0.45)
	panel.shadow_size = 8
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

	var tip := box(Color(0.05, 0.05, 0.08, 0.96), GOLD_DIM, 2, 8, 8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 15)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	t.set_constant("outline_size", "Label", 4)

	var bn := box(Color(0.16, 0.13, 0.20, 0.95), GOLD_DIM, 2, 8, 10)
	var bh := box(Color(0.24, 0.19, 0.28, 0.97), GOLD, 2, 8, 10)
	var bp := box(Color(0.36, 0.27, 0.14, 0.97), GOLD, 2, 8, 10)
	var bd := box(Color(0.12, 0.12, 0.14, 0.75), Color(0.3, 0.3, 0.32), 2, 8, 10)
	var bf := box(Color(0, 0, 0, 0), GOLD, 2, 8, 10)
	bf.draw_center = false
	t.set_stylebox("normal", "Button", bn)
	t.set_stylebox("hover", "Button", bh)
	t.set_stylebox("pressed", "Button", bp)
	t.set_stylebox("hover_pressed", "Button", bp)
	t.set_stylebox("disabled", "Button", bd)
	t.set_stylebox("focus", "Button", bf)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_hover_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.5))
	t.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.8))
	t.set_constant("outline_size", "Button", 3)
	return t


const FUSION_BASE := Color(0.10, 0.30, 0.34)
const FUSION_GLOW := Color(0.70, 1.0, 0.92)
const SPECIES_BASE := Color(0.24, 0.30, 0.14)
const SPECIES_GLOW := Color(0.78, 1.0, 0.55)


## Цвета карты способности/ворот: (основа, свечение).
## Стихийные и усиления — в цвете своей стихии, видовые — болотно-зелёные, слияние — бирюзовое.
static func card_colors(def: CardDef) -> Array:
	if def == null:
		return [ARENA_NEUTRAL, GOLD]
	if def.kind == CardDef.Kind.ABILITY:
		if CardEffects.is_fusion(def):
			return [FUSION_BASE, FUSION_GLOW]
		if CardEffects.species_lock(def) != &"":
			return [SPECIES_BASE, SPECIES_GLOW]
		var lock: int = CardEffects.lock_attr(def)
		if lock >= 0:
			var lc: Color = VisualUtil.attr_color(lock)
			if def.effect_id == &"boost":
				return [lc.darkened(0.6), lc.lightened(0.15)]
			return [lc.darkened(0.45), lc.lightened(0.35)]
		return [ABILITY_BASE, ABILITY_GLOW]
	var a: int = int(def.params.get("attribute", def.params.get("attr", -1)))
	if a >= 0:
		var c: Color = VisualUtil.attr_color(a)
		return [c.darkened(0.25), c.lightened(0.45)]
	if def.effect_id == &"species_double":
		return [SPECIES_BASE, SPECIES_GLOW]
	if CardEffects.is_gate_trap(def):
		return [Color(0.42, 0.16, 0.12), Color(1.0, 0.55, 0.4)]
	return [ARENA_NEUTRAL, GOLD]


## Подпись типа под названием.
static func card_kind(def: CardDef) -> String:
	var sp: StringName = CardEffects.species_lock(def)
	if def.kind != CardDef.Kind.ABILITY:
		match CardDB.card_class(def):
			&"gold":
				return "Ворота стихии"
			&"silver":
				return "Ворота вида · %s" % CardDB.species_name(sp)
		return "Ловушка" if CardEffects.is_gate_trap(def) else "Командные ворота"
	if sp != &"":
		return "%s · %s" % ["Слияние" if CardEffects.is_fusion(def) else "Вид", CardDB.species_name(sp)]
	var lock: int = CardEffects.lock_attr(def)
	if lock >= 0:
		return "%s · %s" % ["Усиление" if def.effect_id == &"boost" else "Стихия", VisualUtil.attr_name(lock)]
	return "Способность"


## Тип рамки карты (CardView.Frame): тип читается с одного взгляда — форма окна, металл, накладки.
static func card_frame(def: CardDef) -> int:
	if def == null:
		return CardView.Frame.ELEMENT
	match CardDB.card_class(def):
		&"gold":
			return CardView.Frame.FIELD
		&"silver":
			return CardView.Frame.SPECIES_GATE
		&"bronze":
			return CardView.Frame.TRAP if CardEffects.is_gate_trap(def) else CardView.Frame.COMMAND
		&"blue":
			return CardView.Frame.BOOST
		&"green":
			return CardView.Frame.FUSION if CardEffects.is_fusion(def) else CardView.Frame.SPECIES
	return CardView.Frame.ELEMENT


## Ступени силы у медальона (усиления и видовые прибавки): 1 — до +50, 2 — до +150, 3 — больше.
static func card_tier(def: CardDef) -> int:
	if def == null or def.kind != CardDef.Kind.ABILITY or not (def.effect_id in [&"boost", &"boost_fix", &"fusion_boost"]):
		return 0
	var n: int = int(def.params.get("amount", 0))
	return 1 if n <= 50 else (2 if n <= 150 else 3)


## Знак вида (21..28 в card_face.gdshaderinc) по порядку GameData.SPECIES; -1 — нет такого вида.
static func species_sigil(sp: StringName) -> int:
	for i in range(GameData.SPECIES.size()):
		if StringName(GameData.SPECIES[i]["id"]) == sp:
			return 21 + i
	return -1


## Символ в центре карты (см. card_face.gdshaderinc, cf_sigil: 1..6 стихии, 7 слияние, 8 щит, 9/10 стрелки, 11 обмен, 12 запрет,
## 13 плюс, 14 перенос, 15 бездна, 16 возрождение, 17 копия, 18 когти, 19 ×2, 20 флаг, 21..28 виды, 0 эмблема).
static func card_sigil(def: CardDef) -> int:
	if CardEffects.is_fusion(def):
		return 7
	# ворота вида — знак своего вида; усиление стихии — знак стихии (ступени силы — ромбы у медальона)
	if def.effect_id == &"species_double" and species_sigil(CardEffects.species_lock(def)) > 0:
		return species_sigil(CardEffects.species_lock(def))
	if def.effect_id == &"boost" and CardEffects.species_lock(def) == &"" and CardEffects.lock_attr(def) >= 0:
		return CardEffects.lock_attr(def) + 1
	match String(def.effect_id):
		"negate", "cap_own_base":
			return 8
		"boost", "boost_fix", "owner_power":
			return 9 if CardEffects.species_lock(def) == &"" or def.effect_id != &"boost" else 18
		"scorch", "weaken_mark", "weaken", "funnel", "weight":
			return 10
		"drain", "siphon", "shift_gate", "mirror":
			return 11
		"purge_gate", "eclipse", "silence", "nullify_gate", "strip", "mute", "limit":
			return 12
		"reset_base", "web":
			return 13
		"gust", "swap_fighter", "ebb", "aloft":
			return 14
		"doom", "clash":
			return 15
		"revive", "recall", "fallen_call":
			return 16
		"copy":
			return 17
		"species_double":
			return 19
		"hold":
			return 20
		"radiance":
			return 3
		"pact", "dusk_throne":
			return 5
	var a: int = int(def.params.get("attr", -1))
	if def.kind == CardDef.Kind.ARENA and a >= 0:
		return a + 1
	return 0


## Короткий значок силы карты.
static func card_badge(def: CardDef) -> String:
	var n: int = int(def.params.get("amount", 0))
	match String(def.effect_id):
		"drain", "radiance", "pact", "funnel":
			return "+%d / −%d" % [n, n]
		"scorch", "eclipse", "weaken_mark", "weaken", "weight":
			return "−%d" % n
		"negate":
			return "−%d" % n if n > 0 else ""
		"species_double":
			return "×2"
		"limit":
			return "%d" % n
		"attr_bonus":
			var g: Array = def.params.get("g", [])
			var a: int = int(def.params.get("attr", 0))
			return "+%d" % (int(g[a]) if a < g.size() else n)
	if n > 0:
		return "+%d" % n
	return ""


## Какие кружки стихий подсветить на карте.
static func card_elements(def: CardDef) -> Array:
	var lock: int = CardEffects.lock_attr(def)
	if lock >= 0:
		return [lock]
	var a: int = int(def.params.get("attr", -1))
	if a >= 0:
		return [a]
	if def.effect_id == &"dusk_throne":
		return [4]
	return []


# ---------------------------------------------------------------- подсказки для новичка

const CLASS_HELP := {
	&"gold": ["Ворота стихии", "Карта поля боя. Кладётся рубашкой вверх и открывается в бою. «Поле» даёт силу только существу своей стихии (у каждой стихии своё число), «Алтарь силы» — +300 защитнику-владельцу."],
	&"silver": ["Ворота вида", "Существо этого вида на воротах удваивает базовую силу — у любой стороны, так что соперник тоже может ими воспользоваться."],
	&"bronze": ["Командные ворота", "Меняют правила боя: перекачка силы, предел силы, победитель остаётся, возврат выбывших. Ловушки срабатывают при открытии ворот, пока никто их не видит."],
	&"red": ["Стихийная способность", "Играет только существо своей стихии. У каждой стихии своя тема: Пламя жжёт, Буря переносит, Свет возрождает, Камень сдвигает, Тень губит, Прилив глушит."],
	&"blue": ["Усиление", "Лесенка силы своей стихии: +30 нельзя отменить, +100 при условии, большие числа — для отстающих (такие карты возвращаются в руку)."],
	&"green": ["Видовая способность", "Играет только существо своего вида любой стихии: отмена, сброс силы, перекачка бонусов, «нельзя отменить»."],
}
const ABILITY_WHEN := "Играется в бою (пошаговый обмен, до 3 карт на бой; бой решается после двух пасов подряд), до броска или после приземления — тогда карта прикрепляется к существу. Сыгранная карта отдыхает 2 боя и возвращается в руку (у последнего существа — сразу)."
const FUSION_WHEN := "Слияние: кладётся поверх своей способности в том же бою и усиливает её."
const GATE_WHEN := "В начале хода можно положить одну карту ворот: ближе к сопернику, рядом с другими картами. Можно сразу бросить на неё существо («Ворота + бросок»)."


## Строки подсказки для карты: [заголовок, тип, цвет типа, описание типа, эффект, когда играть].
static func card_help(def: CardDef) -> Array:
	var cls: StringName = CardDB.card_class(def)
	var info: Array = CLASS_HELP.get(cls, ["Карта", ""])
	var when: String = GATE_WHEN
	if def.kind == CardDef.Kind.ABILITY:
		when = FUSION_WHEN if CardEffects.is_fusion(def) else ABILITY_WHEN
	var kind: String = info[0]
	var lock: int = CardEffects.lock_attr(def)
	if lock >= 0:
		kind += " · только для стихии %s" % VisualUtil.attr_name(lock)
	var sp: StringName = CardEffects.species_lock(def)
	if sp != &"":
		kind += " · только для вида %s" % CardDB.species_name(sp)
	var cc := {&"gold": Color(1.0, 0.82, 0.35), &"silver": Color(0.82, 0.86, 0.92), &"bronze": Color(0.9, 0.58, 0.32),
		&"red": Color(1.0, 0.45, 0.4), &"blue": Color(0.5, 0.7, 1.0), &"green": Color(0.5, 0.92, 0.58)}
	var extra: String = ""
	if def.kind == CardDef.Kind.ARENA:
		var g: Array = def.params.get("g", [])
		var parts: PackedStringArray = []
		for a in range(mini(6, g.size())):
			if int(g[a]) != 0:
				parts.append("%s +%d" % [VisualUtil.attr_name(a), int(g[a])])
		if not parts.is_empty():
			extra = "Сила G по стихиям: " + ", ".join(parts)
	return [def.display_name, kind, cc.get(cls, GOLD), info[1], def.text, when, extra]


## Подсказка для существа: [имя, стихия, сила, кого бьёт, кому уступает].
static func creature_help(d: CreatureDef) -> Array:
	var beats: int = (d.attribute + 1) % 6
	var weak: int = Attr.beaten_by(d.attribute)
	return [d.display_name, "Существо · стихия %s" % VisualUtil.attr_name(d.attribute), VisualUtil.attr_color(d.attribute).lightened(0.3),
		"Сила G (базовая): %d. В бою к ней прибавляются ворота, преимущество стихии и способности." % d.base_power,
		"Бьёт стихию %s (+60 к силе), уступает стихии %s." % [VisualUtil.attr_name(beats), VisualUtil.attr_name(weak)],
		"Бросается на карту ворот. Проиграв бой, выбывает; победив — уходит в зону использованных.", "", d.attribute]


## Панель подсказки (используется в CardView._make_custom_tooltip).
static func help_panel(lines: Array) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(Color(0.05, 0.05, 0.08, 0.96), lines[2], 2, 10, 12))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.custom_minimum_size = Vector2(340, 0)
	p.add_child(vb)
	var t := VisualUtil.label(str(lines[0]), 20)
	t.add_theme_color_override("font_color", Color(1.0, 0.88, 0.4))
	if lines.size() > 7 and typeof(lines[7]) == TYPE_INT and int(lines[7]) >= 0:
		# существо: значок стихии перед именем
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var ic := TextureRect.new()
		ic.texture = ElementIcon.badge(int(lines[7]))
		ic.custom_minimum_size = Vector2(30, 30)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
		row.add_child(t)
		vb.add_child(row)
	else:
		vb.add_child(t)
	var k := VisualUtil.label(str(lines[1]).to_upper(), 12)
	k.add_theme_color_override("font_color", lines[2])
	vb.add_child(k)
	for i in [4, 6, 3, 5]:
		var txt: String = str(lines[i])
		if txt == "":
			continue
		var l := VisualUtil.label(txt, 15 if i == 4 else 13)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(340, 0)
		l.add_theme_color_override("font_color", TEXT if i == 4 else TEXT_DIM)
		vb.add_child(l)
	return p
