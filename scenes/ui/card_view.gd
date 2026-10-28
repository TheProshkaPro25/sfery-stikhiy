class_name CardView
extends Button
## 2D-карта в едином стиле с картами арены (облик — scenes/shaders/card_face.gdshaderinc):
## тёмная эфирная основа, гравированная рамка по типу карты, окно с символом, плашка названия, медальон силы, стекло с текстом.
## Одна и та же карта для способностей, карт арены и существ (тип задаётся рамкой, стихия — свечением).

const SHADER: Shader = preload("res://scenes/shaders/card_ui.gdshader")

## Типы рамки (см. card_face.gdshaderinc).
enum Frame { FIELD, SPECIES_GATE, COMMAND, TRAP, ELEMENT, BOOST, SPECIES, FUSION, CREATURE, BACK }

## Поля вокруг карты под ореол (доля ширины).
const MARGIN := 0.07

var card_id: StringName = &""
var uid: int = -1

var _inner: Control
var _bg: ColorRect
var _mat: ShaderMaterial
var _title: Label
var _kind: Label
var _text: Label
var _power: Label
var _lift_tw: Tween
var _hover_tw: Tween
var _play_tw: Tween
var _dimmed := false
var _card_size := Vector2(150, 210)
var _lay: Dictionary = {}
var _glow := Color.WHITE


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())
	_build()
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	toggled.connect(func(_on: bool) -> void: _sync_selected())


func _build() -> void:
	_inner = Control.new()
	_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_inner)
	_bg = ColorRect.new()
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("margin", MARGIN)
	for u in ["hover", "selected", "dim"]:
		_mat.set_shader_parameter(u, 0.0)
	_mat.set_shader_parameter("detail", detail_level())
	_bg.material = _mat
	_inner.add_child(_bg)

	_title = _mk_label(title_font())
	_kind = _mk_label(null)
	_text = _mk_label(null)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_power = _mk_label(power_font())
	_power.visible = false


func _mk_label(font: Font) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.clip_text = false
	if font != null:
		l.add_theme_font_override("font", font)
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.02, 0.95))
	_inner.add_child(l)
	return l


# ---------------------------------------------------------------- раскладка (общая с картой арены)

## Раскладка карты в долях ширины: окно, плашка названия, медальон силы, стекло текста.
## with_text — 2D-карта с текстом эффекта; иначе компактная (мелкие карты и карты арены).
## short_text — текста мало (карта существа): окно крупнее, стекло ниже.
static func layout(aspect: float, with_text: bool, short_text: bool = false) -> Dictionary:
	if with_text and short_text:
		return {
			"title": Rect2(0.075, 0.05, 0.85, 0.14),
			"kind_y": 0.2,
			"win": Vector3(0.5, 0.6, 0.262),
			"plaque": Vector4(0.5, 0.95, 0.2, 0.056),
			"text": Rect2(0.075, 0.95, 0.85, aspect - 0.95 - 0.055),
		}
	if with_text:
		return {
			"title": Rect2(0.075, 0.05, 0.85, 0.14),
			"kind_y": 0.2,
			"win": Vector3(0.5, 0.555, 0.232),
			"plaque": Vector4(0.5, 0.85, 0.2, 0.056),
			"text": Rect2(0.075, 0.85, 0.85, aspect - 0.85 - 0.055),
		}
	return {
		"title": Rect2(0.07, 0.05, 0.86, 0.165),
		"kind_y": -1.0,
		"win": Vector3(0.5, aspect * 0.5 + 0.03, 0.285),
		"plaque": Vector4(0.5, aspect - 0.155, 0.23, 0.072),
		"text": Rect2(),
	}


## Подобрать вид надписи под ширину w и высоту h (px): одна строка с кеглем до 80% от max_fs →
## одна строка с ужатием по ширине (не уже 74%) и кеглем до 62% → две строки → ужатие любого слова.
## Возврат: {text, fs, sx (масштаб по ширине), lines}.
static func fit_title(font: Font, text: String, max_fs: int, w: float, h: float) -> Dictionary:
	var min1: int = maxi(6, int(max_fs * 0.8))
	for fs in range(max_fs, min1 - 1, -1):
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= w:
			return {"text": text, "fs": fs, "sx": 1.0, "lines": 1}
	var tw: float = 0.0
	for fs in range(min1, maxi(6, int(max_fs * 0.62)) - 1, -1):
		tw = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if tw * 0.74 <= w:
			return {"text": text, "fs": fs, "sx": w / tw, "lines": 1}
	var words: PackedStringArray = text.split(" ", false)
	if words.size() >= 2:
		# разрыв, при котором длиннейшая строка короче всего
		var best := ""
		var best_w := INF
		for i in range(1, words.size()):
			var a: String = " ".join(words.slice(0, i))
			var b: String = " ".join(words.slice(i))
			var lw: float = maxf(font.get_string_size(a, HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x, font.get_string_size(b, HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x)
			if lw < best_w:
				best_w = lw
				best = a + "\n" + b
		var fs2: int = mini(int(max_fs * 0.86), int(h / (2.0 * font.get_height(100) / 100.0)))
		fs2 = maxi(fs2, 6)
		var lw2: float = best_w * fs2 / 100.0
		return {"text": best, "fs": fs2, "sx": minf(1.0, w / maxf(lw2, 1.0)), "lines": 2}
	return {"text": text, "fs": maxi(6, int(max_fs * 0.62)), "sx": w / maxf(tw, 1.0), "lines": 1}


## Короткая надпись в медальон силы: «+100 / −100» → «±100»; нечисловое — пусто.
static func power_text(badge: String) -> String:
	if badge.contains(" / "):
		var a: String = badge.get_slice(" / ", 0)
		var b: String = badge.get_slice(" / ", 1)
		if a.substr(1) == b.substr(1):
			return "±" + a.substr(1)
		return a
	if badge.is_empty() or not (badge[0] in "+−-×0123456789") or badge == "0":
		return ""
	return badge.replace(" ×", "×")


## Детализация облика по уровню графики: «Низкие» 0 (без рун и второго слоя дымки), «Средние» 0.6
## (руны и кольца портала, дымка в один слой), «Высокие» 1 (дымка с завихрением).
static func detail_level() -> float:
	match GraphicsSettings.current():
		GraphicsSettings.Level.LOW:
			return 0.0
		GraphicsSettings.Level.MEDIUM:
			return 0.6
	return 1.0


static var _tfont: FontVariation
static var _pfont: FontVariation


## Полужирный шрифт названия (чуть сжатый).
static func title_font() -> FontVariation:
	if _tfont == null:
		_tfont = FontVariation.new()
		_tfont.base_font = ThemeDB.fallback_font
		_tfont.variation_embolden = 0.55
		_tfont.spacing_glyph = 0
	return _tfont


## Жирный шрифт цифры силы.
static func power_font() -> FontVariation:
	if _pfont == null:
		_pfont = FontVariation.new()
		_pfont.base_font = ThemeDB.fallback_font
		_pfont.variation_embolden = 1.1
		_pfont.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.12, 1), Vector2.ZERO)
	return _pfont


# ---------------------------------------------------------------- настройка

## Общая настройка карты: base — оттенок глубины, glow — свечение стихии/типа.
## short_text — мало текста (карта существа): крупнее окно.
func setup(title: String, kind: String, text: String, _foot: String, base: Color, glow: Color, size_px: Vector2 = Vector2(150, 210), short_text: bool = false) -> CardView:
	_card_size = size_px
	_glow = glow
	custom_minimum_size = size_px
	_inner.size = size_px
	var w: float = size_px.x
	var aspect: float = size_px.y / size_px.x
	var with_text: bool = w >= 112.0
	_lay = layout(aspect, with_text, short_text)
	var m: float = MARGIN * w
	_bg.position = Vector2(-m, -m)
	_bg.size = size_px + Vector2(m, m) * 2.0
	_mat.set_shader_parameter("base", base)
	_mat.set_shader_parameter("glow", glow)
	_mat.set_shader_parameter("aspect", aspect)
	var tr: Rect2 = _lay["title"]
	_mat.set_shader_parameter("title_box", Vector4(tr.position.x, tr.position.y, tr.end.x, tr.end.y))
	var wn: Vector3 = _lay["win"]
	_mat.set_shader_parameter("win", wn)
	var xr: Rect2 = _lay["text"]
	_mat.set_shader_parameter("text_box", Vector4(xr.position.x, xr.position.y, xr.end.x, xr.end.y) if with_text else Vector4.ZERO)
	_mat.set_shader_parameter("plaque", Vector4.ZERO)
	_mat.set_shader_parameter("sigil", 0)
	_mat.set_shader_parameter("tier", 0.0)
	set_frame(Frame.ELEMENT)
	set_elements([])

	# Название на плашке: светлое золото с тёмной обводкой и отсветом стихии; никогда не вылезает за плашку
	_title.add_theme_color_override("font_color", Color(1.0, 0.94, 0.8))
	_title.add_theme_constant_override("outline_size", maxi(3, int(w * 0.03)))
	_title.add_theme_color_override("font_shadow_color", Color(glow, 0.55))
	_title.add_theme_constant_override("shadow_outline_size", maxi(4, int(w * 0.05)))
	_title.add_theme_constant_override("shadow_offset_x", 0)
	_title.add_theme_constant_override("shadow_offset_y", 0)
	_title.add_theme_constant_override("line_spacing", -int(w * 0.03))
	_place_title(_title, title, Rect2(tr.position * w, tr.size * w), int(w * (0.112 if with_text else 0.125)))

	_kind.text = kind.to_upper()
	_kind.visible = with_text and kind != ""
	_kind.add_theme_font_size_override("font_size", maxi(7, int(w * 0.056)))
	_kind.add_theme_color_override("font_color", glow.lerp(Color.WHITE, 0.45))
	_kind.add_theme_constant_override("outline_size", 3)
	if _kind.visible:
		var kw: float = w * 0.8
		var ky: float = float(_lay["kind_y"]) * w
		var kf: Dictionary = fit_title(_kind.get_theme_font("font"), _kind.text, int(w * 0.056), kw, w * 0.06)
		_kind.text = String(kf["text"]).replace("\n", " ")
		_kind.add_theme_font_size_override("font_size", int(kf["fs"]))
		_kind.size = Vector2(kw / float(kf["sx"]), w * 0.06)
		_kind.pivot_offset = _kind.size * 0.5
		_kind.scale = Vector2(float(kf["sx"]), 1.0)
		_kind.position = Vector2(w * 0.5, ky + w * 0.03) - _kind.size * 0.5

	# Текст эффекта на тёмном стекле: светлый
	_text.text = text
	_text.visible = with_text
	_text.add_theme_color_override("font_color", Color(0.93, 0.91, 0.86))
	_text.add_theme_constant_override("outline_size", 2)
	_text.add_theme_constant_override("line_spacing", -2)
	if with_text:
		_text.position = Vector2(xr.position.x + 0.035, xr.position.y + 0.065) * w
		_text.size = Vector2(xr.size.x - 0.07, xr.size.y - 0.08) * w
		_fit(_text, int(w * 0.078), 7, _text.size.x, _text.size.y)
	tooltip_text = "%s\n%s" % [title, text]
	_power.visible = false
	return self


## Название в прямоугольнике плашки r (px): отступ под заострённые концы, подбор кегля/строк/ужатия.
func _place_title(l: Label, text: String, r: Rect2, max_fs: int) -> void:
	var inset: float = r.size.y * 0.42
	var aw: float = r.size.x - inset * 2.0
	var ah: float = r.size.y * 0.96
	var f: Dictionary = fit_title(l.get_theme_font("font"), text, max_fs, aw, ah)
	l.text = f["text"]
	l.add_theme_font_size_override("font_size", int(f["fs"]))
	var sx: float = float(f["sx"])
	l.size = Vector2(aw / sx, ah)
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2(sx, 1.0)
	l.position = r.get_center() - l.size * 0.5


## Тип рамки и ступени силы (усиления: 1..3).
func set_frame(fr: int, p_tier: int = 0) -> CardView:
	_mat.set_shader_parameter("frame", fr)
	_mat.set_shader_parameter("tier", float(p_tier))
	return self


## Камни накладок горят цветом стихии (первой из attrs), иначе — тусклые.
func set_elements(attrs: Array) -> CardView:
	var a: int = int(attrs[0]) if not attrs.is_empty() else -1
	if a >= 0 and a < 6:
		_mat.set_shader_parameter("gem", Color(VisualUtil.attr_color(a).lightened(0.25), 1.0))
	else:
		_mat.set_shader_parameter("gem", Color(_glow, 0.0))
	return self


## Символ в окне и число в медальоне силы.
func set_mark(sigil: int, badge: String, _glow_unused: Color) -> CardView:
	_mat.set_shader_parameter("sigil", sigil)
	var txt: String = power_text(badge)
	var w: float = _card_size.x
	var pq: Vector4 = _lay.get("plaque", Vector4.ZERO)
	_power.visible = txt != ""
	if txt == "":
		_mat.set_shader_parameter("plaque", Vector4.ZERO)
		return self
	_mat.set_shader_parameter("plaque", pq)
	_power.text = txt
	_power.add_theme_color_override("font_color", Color(1.0, 0.98, 0.92))
	_power.add_theme_constant_override("outline_size", maxi(3, int(w * 0.035)))
	_power.add_theme_color_override("font_shadow_color", Color(_glow, 0.8))
	_power.add_theme_constant_override("shadow_outline_size", maxi(5, int(w * 0.07)))
	_power.add_theme_constant_override("shadow_offset_x", 0)
	_power.add_theme_constant_override("shadow_offset_y", 0)
	var pw: float = (pq.z * 2.0 - pq.w * 1.4) * w
	var ph: float = pq.w * 2.0 * w
	var f: Dictionary = fit_title(_power.get_theme_font("font"), txt, int(ph * 1.02), pw, ph)
	_power.text = String(f["text"]).replace("\n", "")
	_power.add_theme_font_size_override("font_size", int(f["fs"]))
	_power.size = Vector2(pw / float(f["sx"]), ph * 1.2)
	_power.pivot_offset = _power.size * 0.5
	_power.scale = Vector2(float(f["sx"]), 1.0)
	_power.position = Vector2(pq.x, pq.y) * w - _power.size * 0.5 + Vector2(0, -ph * 0.02)
	return self


func _fit(l: Label, max_fs: int, min_fs: int, w: float, h: float) -> void:
	var font: Font = l.get_theme_font("font")
	var fs: int = max_fs
	while fs > min_fs:
		if font.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND).y <= h:
			break
		fs -= 1
	l.add_theme_font_size_override("font_size", fs)


var _help: Array = []


## Подробная подсказка для новичка: тип карты, эффект, когда играть.
func _make_custom_tooltip(_for_text: String) -> Object:
	if _help.is_empty():
		return null
	return UiTheme.help_panel(_help)


## Карта способности или арены из CardDef.
func for_card(def: CardDef, size_px: Vector2 = Vector2(150, 210)) -> CardView:
	card_id = def.id
	_help = UiTheme.card_help(def)
	var cols: Array = UiTheme.card_colors(def)
	setup(def.display_name, UiTheme.card_kind(def), def.text, "", cols[0], cols[1], size_px)
	set_frame(UiTheme.card_frame(def), UiTheme.card_tier(def))
	set_elements(UiTheme.card_elements(def))
	return set_mark(UiTheme.card_sigil(def), UiTheme.card_badge(def), cols[1])


## Карта существа.
func for_creature(def: CreatureDef, p_uid: int, note: String = "", size_px: Vector2 = Vector2(150, 210)) -> CardView:
	uid = p_uid
	_help = UiTheme.creature_help(def)
	var ac: Color = VisualUtil.attr_color(def.attribute)
	var txt := "Стихия: %s" % VisualUtil.attr_name(def.attribute)
	if note != "":
		txt += "\n" + note
	setup(def.display_name, "Существо · %s" % VisualUtil.attr_name(def.attribute), txt, "", ac.darkened(0.35), ac.lightened(0.3), size_px, true)
	set_frame(Frame.CREATURE)
	set_elements([def.attribute])
	# в окне — знак вида (стихию показывают свечение и камни накладок)
	var sg: int = UiTheme.species_sigil(def.species)
	return set_mark(sg if sg > 0 else def.attribute + 1, "%d" % def.base_power, ac)


## Карта неактивна (нельзя сыграть сейчас): серая, но остаётся на месте.
func set_dimmed(on: bool) -> void:
	_dimmed = on
	disabled = on
	_mat.set_shader_parameter("dim", 0.75 if on else 0.0)
	for l in [_title, _kind, _text, _power]:
		(l as Label).self_modulate = Color(0.55, 0.55, 0.55) if on else Color.WHITE
	if on:
		_set_hover(0.0)
		_lift(0.0)


## Играбельная карта: мягкая пульсирующая подсветка рамки, пока её можно сыграть.
func set_playable(on: bool) -> void:
	if _play_tw != null:
		_play_tw.kill()
		_play_tw = null
	if not on:
		_mat.set_shader_parameter("selected", 1.0 if button_pressed else 0.0)
		return
	if not is_inside_tree():
		_mat.set_shader_parameter("selected", 0.6)
		return
	_play_tw = create_tween().set_loops()
	_play_tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter("selected", v), 0.25, 0.85, 0.7).set_trans(Tween.TRANS_SINE)
	_play_tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter("selected", v), 0.85, 0.25, 0.7).set_trans(Tween.TRANS_SINE)


func _sync_selected() -> void:
	_mat.set_shader_parameter("selected", 1.0 if button_pressed else 0.0)
	_lift(-8.0 if button_pressed else 0.0)


func _on_hover(on: bool) -> void:
	if _dimmed:
		return
	_set_hover(1.0 if on else 0.0)
	if not button_pressed:
		_lift(-8.0 if on else 0.0)


## Плавное наведение (свет кромки и перелив разгораются за ~0.15 с).
func _set_hover(v: float) -> void:
	if _hover_tw != null:
		_hover_tw.kill()
	if not is_inside_tree():
		_mat.set_shader_parameter("hover", v)
		return
	var from: float = float(_mat.get_shader_parameter("hover"))
	_hover_tw = create_tween()
	_hover_tw.tween_method(func(x: float) -> void: _mat.set_shader_parameter("hover", x), from, v, 0.15)


func _lift(y: float) -> void:
	if _lift_tw != null:
		_lift_tw.kill()
	if not is_inside_tree():
		_inner.position.y = y
		return
	_lift_tw = create_tween()
	_lift_tw.tween_property(_inner, "position:y", y, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
