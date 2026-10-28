class_name UiTheme
extends RefCounted
## Общая тема интерфейса: тёмные полупрозрачные панели с золотой каймой, кнопки в том же стиле.

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


## Цвета карты способности/арены: (основа, свечение).
## Стихийные способности — в цвете своей стихии, слияния — бирюзовые, прочие способности — фиолетовые.
static func card_colors(def: CardDef) -> Array:
	if def == null:
		return [ARENA_NEUTRAL, GOLD]
	if def.kind == CardDef.Kind.ABILITY:
		if CardEffects.is_fusion(def):
			return [FUSION_BASE, FUSION_GLOW]
		var lock: int = CardEffects.lock_attr(def)
		if lock >= 0:
			var lc: Color = VisualUtil.attr_color(lock)
			return [lc.darkened(0.45), lc.lightened(0.35)]
		return [ABILITY_BASE, ABILITY_GLOW]
	var a: int = int(def.params.get("attribute", def.params.get("attr", -1)))
	if a >= 0:
		var c: Color = VisualUtil.attr_color(a)
		return [c.darkened(0.25), c.lightened(0.45)]
	return [ARENA_NEUTRAL, GOLD]


## Подпись типа под названием.
static func card_kind(def: CardDef) -> String:
	if def.kind != CardDef.Kind.ABILITY:
		return "Арена"
	if CardEffects.is_fusion(def):
		return "Слияние"
	var lock: int = CardEffects.lock_attr(def)
	if lock >= 0:
		return "Стихия · %s" % VisualUtil.attr_name(lock)
	return "Способность"


## Символ в центре карты (см. CardView.SHADER: 1..6 стихии, 7 слияние, 8 щит, 9/10 стрелки, 11 обмен, 12 запрет, 13 плюс, 0 эмблема).
static func card_sigil(def: CardDef) -> int:
	if CardEffects.is_fusion(def):
		return 7
	var lock: int = CardEffects.lock_attr(def)
	if lock >= 0:
		return lock + 1
	match String(def.effect_id):
		"shield", "bastion":
			return 8
		"boost_self", "all_in", "legacy", "home_element", "underdog", "overweight":
			return 9
		"weaken_foe", "trap", "backflow":
			return 10
		"overflow", "swap_base", "steal_arena", "mirror":
			return 11
		"nullify_arena", "void", "seal":
			return 12
		"throne":
			return 9
		"rescue":
			return 13
	var a: int = int(def.params.get("attr", -1))
	if def.kind == CardDef.Kind.ARENA and a >= 0:
		return a + 1
	return 0


## Короткий значок силы карты.
static func card_badge(def: CardDef) -> String:
	var n: int = int(def.params.get("amount", 0))
	match String(def.effect_id):
		"boost_self", "all_in", "home_element", "steal_advantage", "swap_attr", "rescue", "fusion_chain", "attr_bonus", "bastion", "twilight", "underdog", "throne":
			return "+%d" % n
		"weaken_foe", "trap":
			return "−%d" % absi(n)
		"drain":
			return "+%d / −%d" % [n, n]
		"stone_wall":
			return "+%d / +%d" % [n, int(def.params.get("amount_def", n))]
		"legacy", "fusion_echo":
			return "+%d ×" % n
		"fusion_double":
			return "×2"
		"absorb":
			return "½"
		"strip":
			return "= БС"
		"swap_base":
			return "БС ⇆"
		"steal_arena":
			return "поле ⇆"
		"overflow":
			return "стихия"
		"shield":
			return "блок"
		"nullify_arena", "void":
			return "0"
		"overweight":
			return "×2"
	return ""


## Какие кружки стихий подсветить на карте.
static func card_elements(def: CardDef) -> Array:
	var lock: int = CardEffects.lock_attr(def)
	if lock >= 0:
		return [lock]
	var a: int = int(def.params.get("attr", -1))
	if a >= 0:
		return [a]
	if def.effect_id == &"twilight":
		return [2, 4]
	return []


# ---------------------------------------------------------------- подсказки для новичка

const CLASS_HELP := {
	&"gold": ["Золотые ворота", "Карта поля боя. Кладётся рубашкой вверх и открывается в бою. Даёт силу G существу своей стихии (остальным — нет)."],
	&"silver": ["Серебряные ворота", "Карта поля боя с особым бонусом силы: помогает защитнику, слабейшему или нужным стихиям."],
	&"bronze": ["Бронзовые ворота", "Карта поля боя, меняющая правила боя на ней: отменяет или удваивает преимущество стихий. Бывает ловушкой: срабатывает при открытии ворот."],
	&"red": ["Красная способность", "Зависит от стихии. Стихийную может сыграть только существо этой стихии — она сильнее обычных."],
	&"blue": ["Синяя способность", "Прибавка или отнятие силы G в бою."],
	&"green": ["Зелёная способность", "Меняет ситуацию боя: отменяет карты, меняет силы местами, спасает существо."],
}
const ABILITY_WHEN := "Играется в бою (обмен по очереди, до 3 карт на бой; «Пас» окончателен), до броска или после приземления — тогда карта прикрепляется к существу. Каждая карта — один раз за игру."
const FUSION_WHEN := "Слияние: кладётся сразу поверх своей способности в том же бою и усиливает её."
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
		"Бросается на карту ворот. Проиграв бой, выбывает; победив — уходит в зону использованных.", ""]


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
