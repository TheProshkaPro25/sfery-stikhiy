class_name CardView
extends Button
## 2D-карта в едином стиле с картами арены: рунный узор шейдером, имя сверху, текст на плашке снизу.
## Одна и та же карта для способностей, карт арены и существ (вид задаётся цветами и подписями).

const SHADER := """
shader_type canvas_item;
// Карта в духе карт способностей: металлическая рамка с техно-вырезами, круглое окно с символом,
// колонка «силы» и шести стихий слева, светлая плашка текста снизу. Координаты: x 0..1, y 0..aspect.
uniform vec4 base : source_color = vec4(0.3, 0.16, 0.46, 1.0);   // оттенок рамки
uniform vec4 glow : source_color = vec4(1.0, 0.8, 0.45, 1.0);    // цвет окна и символа
uniform float aspect = 1.4;
uniform float hover = 0.0;
uniform float dim = 0.0;
uniform float selected = 0.0;
uniform float compact = 0.0;
uniform int sigil = 0; // 0 эмблема, 1..6 стихии (Пламя..Прилив), 7 слияние, 8 щит, 9/10 стрелки, 11 обмен, 12 запрет, 13 плюс
uniform vec3 elem_a = vec3(0.0); // подсветка кружков стихий: Пламя, Буря, Свет
uniform vec3 elem_b = vec3(0.0); // Камень, Тень, Прилив
uniform vec3 elem_c0 : source_color = vec3(0.92, 0.32, 0.14);
uniform vec3 elem_c1 : source_color = vec3(0.30, 0.78, 0.62);
uniform vec3 elem_c2 : source_color = vec3(0.97, 0.88, 0.40);
uniform vec3 elem_c3 : source_color = vec3(0.55, 0.45, 0.35);
uniform vec3 elem_c4 : source_color = vec3(0.45, 0.28, 0.65);
uniform vec3 elem_c5 : source_color = vec3(0.20, 0.50, 0.90);

float ring(float r, float rad, float w) { return smoothstep(w, 0.0, abs(r - rad)); }
float fill(float d) { return smoothstep(0.004, -0.004, d); }
float stroke(float d, float w) { return smoothstep(w, w * 0.4, abs(d)); }

float sd_tri(vec2 p, vec2 a, vec2 b, vec2 c) {
	vec2 e0 = b - a, e1 = c - b, e2 = a - c;
	vec2 v0 = p - a, v1 = p - b, v2 = p - c;
	vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
	vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
	vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
	float s = sign(e0.x * e2.y - e0.y * e2.x);
	vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
		vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
		vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
	return -sqrt(d.x) * sign(d.y);
}

float sd_box(vec2 p, vec2 c, vec2 h) {
	vec2 d = abs(p - c) - h;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

float sd_hex(vec2 p, float r) {
	const vec3 k = vec3(-0.866025404, 0.5, 0.577350269);
	p = abs(p);
	p -= 2.0 * min(dot(k.xy, p), 0.0) * k.xy;
	p -= vec2(clamp(p.x, -k.z * r, k.z * r), r);
	return length(p) * sign(p.y);
}

// Покрытие символа (0..1) в локальных координатах эмблемы.
float sigil_mask(vec2 e, int id) {
	float r = length(e);
	if (id == 1) { // пламя: капля с языком
		float body = length(e - vec2(0.0, 0.035)) - 0.062;
		float tip = sd_tri(e, vec2(-0.058, 0.03), vec2(0.058, 0.03), vec2(0.012, -0.135));
		float inner = length(e - vec2(0.0, 0.05)) - 0.028;
		return clamp(fill(min(body, tip)) - fill(inner) * 0.7, 0.0, 1.0);
	}
	if (id == 2) { // буря: спираль
		float a = atan(e.y, e.x) / 6.28318 + 0.5;
		float t = r / 0.038 - a;
		float d = (abs(fract(t) - 0.5)) * 0.038;
		return smoothstep(0.009, 0.004, d) * smoothstep(0.125, 0.11, r) * smoothstep(0.008, 0.02, r);
	}
	if (id == 3) { // свет: восьмилучевая звезда
		float ang = atan(e.y, e.x);
		float rr = 0.045 + 0.085 * pow(abs(cos(ang * 4.0)), 10.0) + 0.03 * pow(abs(cos(ang * 4.0 + 0.785)), 10.0);
		return fill(r - rr);
	}
	if (id == 4) { // камень: шестигранник с гранью
		float h = sd_hex(e, 0.085);
		return clamp(fill(h) - stroke(sd_hex(e, 0.045), 0.006) * 0.8, 0.0, 1.0);
	}
	if (id == 5) { // тень: полумесяц
		float c1 = length(e) - 0.1;
		float c2 = length(e - vec2(0.045, -0.035)) - 0.085;
		return fill(max(c1, -c2));
	}
	if (id == 6) { // прилив: три волны
		float m = 0.0;
		for (int k = -1; k <= 1; k++) {
			float y = e.y - float(k) * 0.042 - 0.016 * sin(e.x * 55.0 + float(k));
			m = max(m, smoothstep(0.011, 0.005, abs(y)));
		}
		return m * smoothstep(0.115, 0.1, abs(e.x));
	}
	if (id == 7) { // слияние: два сцепленных кольца
		return max(stroke(length(e - vec2(-0.038, 0.0)) - 0.062, 0.012), stroke(length(e - vec2(0.038, 0.0)) - 0.062, 0.012));
	}
	if (id == 8) { // щит
		float sh = min(sd_box(e, vec2(0.0, -0.045), vec2(0.08, 0.05)), sd_tri(e, vec2(-0.08, 0.0), vec2(0.08, 0.0), vec2(0.0, 0.115)));
		return clamp(fill(sh) - fill(sd_box(e, vec2(0.0, -0.03), vec2(0.012, 0.05))) * 0.6, 0.0, 1.0);
	}
	if (id == 9 || id == 10) { // стрелка вверх (усиление) / вниз (ослабление)
		vec2 q = id == 9 ? e : vec2(e.x, -e.y);
		float a = min(sd_box(q, vec2(0.0, 0.045), vec2(0.024, 0.06)), sd_tri(q, vec2(-0.08, 0.0), vec2(0.08, 0.0), vec2(0.0, -0.115)));
		return fill(a);
	}
	if (id == 11) { // обмен: две встречные стрелки
		float a1 = min(sd_box(e, vec2(-0.02, -0.04), vec2(0.06, 0.014)), sd_tri(e, vec2(0.03, -0.085), vec2(0.03, 0.005), vec2(0.105, -0.04)));
		float a2 = min(sd_box(e, vec2(0.02, 0.04), vec2(0.06, 0.014)), sd_tri(e, vec2(-0.03, -0.005), vec2(-0.03, 0.085), vec2(-0.105, 0.04)));
		return fill(min(a1, a2));
	}
	if (id == 12) { // запрет: перечёркнутый круг
		float c = stroke(r - 0.085, 0.014);
		float l = smoothstep(0.016, 0.008, abs(e.x + e.y) * 0.7071) * step(r, 0.085);
		return max(c, l);
	}
	if (id == 13) { // спасение: крест-плюс
		return fill(min(sd_box(e, vec2(0.0), vec2(0.026, 0.09)), sd_box(e, vec2(0.0), vec2(0.09, 0.026))));
	}
	return 0.0;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// Металлическое кольцо-ободок: светлый верх, тёмный низ.
vec3 bezel(vec3 col, vec2 q, float rad, float w, vec3 tint) {
	float r = length(q);
	float m = smoothstep(w, w * 0.6, abs(r - rad));
	float lit = 0.55 + 0.45 * (-q.y / max(r, 0.001));
	return mix(col, mix(vec3(0.18), vec3(0.92), lit * 0.8) * mix(vec3(1.0), tint, 0.35), m);
}

void fragment() {
	vec2 p = UV * vec2(1.0, aspect);
	float ty = compact > 0.5 ? aspect : 0.97; // верх текстовой плашки
	// --- корпус: шлифованный металл с оттенком категории
	float brush = hash(vec2(floor(p.y * 260.0), 3.0)) * 0.06 + hash(vec2(floor(p.y * 900.0), floor(p.x * 6.0))) * 0.03;
	vec3 metal = mix(base.rgb * 0.55, base.rgb * 1.05 + 0.06, 0.5 + 0.5 * (1.0 - p.y / aspect)) + brush;
	vec3 col = metal;
	// техно-вырезы: диагональ в правом верхнем углу, полосы под заголовком и над текстом
	float cut1 = smoothstep(0.006, 0.0, abs((p.x - 0.62) - (0.17 - p.y) * 1.2)) * step(p.y, 0.17) * step(0.55, p.x);
	float bar1 = smoothstep(0.006, 0.0, abs(p.y - 0.17)) * step(0.62, p.x);
	float bar2 = smoothstep(0.006, 0.0, abs(p.y - (ty - 0.03))) * step(p.y, aspect - 0.02);
	col = mix(col, vec3(0.05), (cut1 + bar1 + bar2) * 0.7);
	col += vec3(0.25) * smoothstep(0.004, 0.0, abs(p.y - 0.176)) * step(0.62, p.x);
	// диагональные штрихи-«решётка» на правом поле рамки
	float hatch = step(0.5, fract((p.x + p.y) * 22.0)) * step(0.9, p.x) * step(0.2, p.y) * step(p.y, ty - 0.06);
	col = mix(col, col * 0.7, hatch * 0.6);

	// --- большое круглое окно
	vec2 wc = vec2(0.59, 0.6);
	vec2 e = p - wc;
	float r = length(e);
	float wr = 0.325;
	float ang = atan(e.y, e.x);
	if (r < wr) {
		float rays = pow(abs(sin(ang * 6.0 + TIME * 0.4)), 8.0) * smoothstep(wr, 0.05, r);
		float swirl = 0.5 + 0.5 * sin(r * 40.0 - ang * 3.0 - TIME * 1.5);
		vec3 inner = mix(glow.rgb * 1.1, base.rgb * 0.25, smoothstep(0.0, wr, r));
		inner += glow.rgb * (rays * 0.25 + swirl * 0.08 * smoothstep(wr, 0.0, r));
		vec2 se = e * (0.13 / 0.22);
		float sig = sigil > 0 ? sigil_mask(se, sigil) : 0.0;
		if (sigil == 0) {
			float star = pow(abs(cos(ang * 4.0)), 14.0) * smoothstep(0.26, 0.0, r);
			sig = clamp(ring(r, 0.17, 0.012) + ring(r, 0.11, 0.008) + star + smoothstep(0.04, 0.0, r), 0.0, 1.0);
		}
		float shade = 0.85 + 0.15 * smoothstep(0.15, -0.15, e.y);
		inner = mix(inner, vec3(1.0, 0.98, 0.92), sig * 0.92) * shade;
		// тёмная окантовка символа
		col = inner;
	}
	col = bezel(col, e, wr + 0.012, 0.022, glow.rgb);
	col = bezel(col, e, wr + 0.045, 0.008, base.rgb);

	// --- колонка слева: круг силы и шесть стихий
	vec2 pc = p - vec2(0.14, 0.34);
	float pr = length(pc);
	if (pr < 0.088) {
		col = mix(vec3(0.75, 0.12, 0.08), vec3(0.35, 0.03, 0.02), smoothstep(0.0, 0.088, pr + pc.y * 0.4));
	}
	col = bezel(col, pc, 0.094, 0.013, vec3(1.0, 0.85, 0.5));
	for (int i = 0; i < 6; i++) {
		vec2 cq = p - vec2(0.14, 0.49 + float(i) * 0.08);
		float cr = length(cq);
		float on = i < 3 ? elem_a[i] : elem_b[i - 3];
		vec3 ec = i == 0 ? elem_c0 : i == 1 ? elem_c1 : i == 2 ? elem_c2 : i == 3 ? elem_c3 : i == 4 ? elem_c4 : elem_c5;
		if (compact > 0.5) { continue; }
		if (cr < 0.035) {
			vec3 recess = vec3(0.08, 0.08, 0.1) + 0.05 * (1.0 - cr / 0.035);
			vec3 lit = mix(ec * 1.25, ec * 0.5, cr / 0.035);
			col = mix(recess, lit, on);
		}
		col = bezel(col, cq, 0.038, 0.007, ec);
	}

	// --- светлая плашка текста
	if (compact < 0.5) {
		vec2 tq = abs(p - vec2(0.5, (ty + aspect) * 0.5 - 0.01)) - vec2(0.44, (aspect - ty) * 0.5 - 0.035);
		float td = length(max(tq, vec2(0.0))) + min(max(tq.x, tq.y), 0.0) - 0.02;
		vec3 paper = mix(vec3(0.90, 0.89, 0.85), vec3(0.78, 0.77, 0.74), (p.y - ty) / (aspect - ty));
		col = mix(col, paper, smoothstep(0.003, -0.003, td));
		col = mix(col, vec3(0.1), smoothstep(0.004, 0.0, abs(td)) * 0.8);
	}

	// --- внешняя кайма
	vec2 dims = vec2(1.0, aspect);
	vec2 q = dims * 0.5 - abs(p - dims * 0.5);
	float d = min(q.x, q.y);
	vec3 rim = mix(vec3(0.85, 0.78, 0.6), glow.rgb, 0.3 + selected * 0.5);
	col = mix(col, rim, smoothstep(0.022, 0.012, d));
	col = mix(col, vec3(0.04), smoothstep(0.006, 0.0, abs(d - 0.026)) * 0.8);
	col += glow.rgb * (hover * 0.12 + selected * 0.25) * smoothstep(0.05, 0.0, d);
	float grey = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(grey) * 0.5, dim);
	vec2 cq2 = abs(p - dims * 0.5) - (dims * 0.5 - 0.04);
	float cd = length(max(cq2, vec2(0.0))) - 0.04;
	COLOR = vec4(col, smoothstep(0.004, -0.004, cd));
}
"""

static var _shader: Shader

var card_id: StringName = &""
var uid: int = -1

var _inner: Control
var _mat: ShaderMaterial
var _title: Label
var _kind: Label
var _text: Label
var _foot: Label
var _badge: PanelContainer
var _badge_label: Label
var _lift_tw: Tween
var _play_tw: Tween
var _dimmed := false
var _card_size := Vector2(150, 210)


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
	var bg := ColorRect.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	bg.material = _mat
	_inner.add_child(bg)

	_title = _mk_label(HORIZONTAL_ALIGNMENT_CENTER)
	_kind = _mk_label(HORIZONTAL_ALIGNMENT_CENTER)
	_text = _mk_label(HORIZONTAL_ALIGNMENT_CENTER)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_foot = _mk_label(HORIZONTAL_ALIGNMENT_CENTER)
	# Значок силы (как «G-сила» на картах): капсула поверх верхнего края плашки
	_badge = PanelContainer.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inner.add_child(_badge)
	_badge_label = Label.new()
	_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_badge.add_child(_badge_label)
	_badge.visible = false


func _mk_label(al: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.horizontal_alignment = al
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.clip_text = false
	_inner.add_child(l)
	return l


## Общая настройка карты (вид задаётся оттенком рамки base и цветом окна glow).
func setup(title: String, kind: String, text: String, foot: String, base: Color, glow: Color, size_px: Vector2 = Vector2(150, 210)) -> CardView:
	_card_size = size_px
	custom_minimum_size = size_px
	_inner.size = size_px
	var w: float = size_px.x
	var aspect: float = size_px.y / size_px.x
	var compact: bool = w < 112.0
	_mat.set_shader_parameter("base", base)
	_mat.set_shader_parameter("glow", glow)
	_mat.set_shader_parameter("aspect", aspect)
	_mat.set_shader_parameter("compact", 1.0 if compact else 0.0)
	_mat.set_shader_parameter("sigil", 0)
	set_elements([])

	# Название: наискосок, жёлтое, слева сверху (до диагонального выреза рамки)
	_title.text = title
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.add_theme_font_override("font", _title_font())
	_title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.32))
	_title.add_theme_constant_override("outline_size", maxi(3, int(w * 0.035)))
	_title.position = Vector2(w * 0.065, w * 0.03)
	_title.size = Vector2(w * (0.9 if compact else 0.66), w * 0.1)
	_fit(_title, int(w * 0.13), 9, _title.size.x, 0.0)

	_kind.text = kind.to_upper()
	_kind.visible = not compact
	_kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_kind.add_theme_font_size_override("font_size", maxi(7, int(w * 0.06)))
	_kind.add_theme_color_override("font_color", glow.lerp(Color.WHITE, 0.4))
	_kind.add_theme_constant_override("outline_size", 3)
	_kind.position = Vector2(w * 0.07, w * 0.15)
	_kind.size = Vector2(w * 0.55, w * 0.06)

	# Текст на светлой плашке: тёмный, без обводки
	_text.text = text
	_text.visible = not compact
	_text.add_theme_color_override("font_color", Color(0.1, 0.09, 0.12))
	_text.add_theme_constant_override("outline_size", 0)
	_text.add_theme_constant_override("line_spacing", -2)
	_text.position = Vector2(w * 0.09, w * 0.985)
	_text.size = Vector2(w * 0.82, size_px.y - w * 1.035)
	_fit(_text, int(w * 0.08), 7, _text.size.x, _text.size.y)
	tooltip_text = "%s\n%s" % [title, text]

	_foot.visible = false
	_badge.visible = false
	return self


static var _tfont: FontVariation


## Наклонный полужирный шрифт заголовка.
static func _title_font() -> FontVariation:
	if _tfont == null:
		_tfont = FontVariation.new()
		_tfont.base_font = ThemeDB.fallback_font
		_tfont.variation_embolden = 0.9
		_tfont.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.22, 1), Vector2.ZERO)
	return _tfont


## Подсветить кружки стихий (атрибуты 0..5).
func set_elements(attrs: Array) -> CardView:
	var on: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	for a in attrs:
		if int(a) >= 0 and int(a) < 6:
			on[int(a)] = 1.0
	_mat.set_shader_parameter("elem_a", Vector3(on[0], on[1], on[2]))
	_mat.set_shader_parameter("elem_b", Vector3(on[3], on[4], on[5]))
	return self


## Символ в окне и значение в круге силы (слева сверху).
func set_mark(sigil: int, badge: String, _glow: Color) -> CardView:
	_mat.set_shader_parameter("sigil", sigil)
	badge = badge.get_slice(" / ", 0)
	var w: float = _card_size.x
	if _badge_label.get_parent() == _badge:
		_badge.remove_child(_badge_label)
		_inner.add_child(_badge_label)
	# в круге силы только числа (как на картах: нечисловой эффект — пустой круг)
	if not badge.is_empty() and not (badge[0] in "+−-×0123456789"):
		badge = ""
	if badge == "0":
		badge = ""
	_badge_label.visible = badge != ""
	_badge.visible = false
	if badge == "":
		return self
	_badge_label.text = badge
	_badge_label.add_theme_color_override("font_color", Color.WHITE)
	_badge_label.add_theme_constant_override("outline_size", maxi(3, int(w * 0.03)))
	var d: float = w * 0.17
	_badge_label.position = Vector2(w * 0.14 - d * 0.5, w * 0.34 - d * 0.5)
	_badge_label.size = Vector2(d, d)
	_badge_label.text = badge.get_slice(" / ", 0).replace(" ×", "×")
	_badge_label.add_theme_constant_override("line_spacing", -4)
	_fit(_badge_label, int(w * 0.085), 7, d * 0.98, d * 0.98)
	_badge_label.size = Vector2(d, d)
	_badge_label.position = Vector2(w * 0.14 - d * 0.5, w * 0.34 - d * 0.5)
	return self


func _fit(l: Label, max_fs: int, min_fs: int, w: float, h: float) -> void:
	var font: Font = l.get_theme_font("font")
	var fs: int = max_fs
	while fs > min_fs:
		if h <= 0.0:
			if font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= w:
				break
		elif l.autowrap_mode != TextServer.AUTOWRAP_OFF:
			if font.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND).y <= h:
				break
		else:
			var sz: Vector2 = font.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
			if sz.x <= w and sz.y <= h:
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
	setup(def.display_name, "Существо", txt, "", def.color.darkened(0.3), ac.lightened(0.35), size_px)
	set_elements([def.attribute])
	return set_mark(def.attribute + 1, "%d" % def.base_power, ac)


## Карта неактивна (нельзя сыграть сейчас): серая, но остаётся на месте.
func set_dimmed(on: bool) -> void:
	_dimmed = on
	disabled = on
	_mat.set_shader_parameter("dim", 0.75 if on else 0.0)
	if on:
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
		_mat.set_shader_parameter("selected", 0.7)
		return
	_play_tw = create_tween().set_loops()
	_play_tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter("selected", v), 0.35, 1.0, 0.55).set_trans(Tween.TRANS_SINE)
	_play_tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter("selected", v), 1.0, 0.35, 0.55).set_trans(Tween.TRANS_SINE)


func _sync_selected() -> void:
	_mat.set_shader_parameter("selected", 1.0 if button_pressed else 0.0)
	_lift(-8.0 if button_pressed else 0.0)


func _on_hover(on: bool) -> void:
	if _dimmed:
		return
	_mat.set_shader_parameter("hover", 1.0 if on else 0.0)
	if not button_pressed:
		_lift(-8.0 if on else 0.0)


func _lift(y: float) -> void:
	if _lift_tw != null:
		_lift_tw.kill()
	if not is_inside_tree():
		_inner.position.y = y
		return
	_lift_tw = create_tween()
	_lift_tw.tween_property(_inner, "position:y", y, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
