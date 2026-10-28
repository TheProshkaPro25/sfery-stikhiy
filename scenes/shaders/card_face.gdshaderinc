// Общий облик карт: 2D (scenes/ui/card_view.gd → card_ui.gdshader) и 3D на арене (scenes/arena_card_node.gd → card_arena.gdshader).
// Тёмная «эфирная» основа (туманность в цвете стихии, искры), гравированная металлическая рамка с угловыми накладками,
// окно с символом под ореолом и кольцом рун, плашка названия и медальон силы. Свет стихии — в рунах, кромках и символе.
// Координаты p: x 0..1, y 0..aspect (в долях ширины карты), y растёт вниз. Раскладку (окно, плашки) задаёт скрипт.
//
// frame — тип рамки (читается с одного взгляда):
//   0 ворота-поле: золото, полукруглая арка-портал;      1 ворота вида: серебро, арка, выемки в углах;
//   2 командные ворота: бронза, стрельчатая арка, срезанные углы;   3 ловушка: тёмная медь с багрянцем + знак ловушки;
//   4 стихийная способность: воронёная сталь, круглый медальон;   5 усиление: сталь, ромб-кристалл, ступени силы (tier);
//   6 видовая способность: патина, шестигранник;   7 слияние: патина, сдвоенное окно;   8 существо: сфера;   9 рубашка.

uniform vec4 base : source_color = vec4(0.22, 0.14, 0.36, 1.0);  // оттенок глубины (туманность)
uniform vec4 glow : source_color = vec4(1.0, 0.8, 0.45, 1.0);   // свечение стихии: символ, руны, кромки
uniform vec4 gem : source_color = vec4(1.0, 0.8, 0.45, 0.0);    // камни накладок: цвет; a > 0.5 — горят цветом стихии
uniform int frame = 4;
uniform int sigil = 0;      // см. cf_sigil
uniform float tier = 0.0;   // ступени силы у медальона (усиления): 0..3
uniform float aspect = 1.4;
uniform vec3 win = vec3(0.5, 0.6, 0.27);              // окно: центр, радиус
uniform vec4 title_box = vec4(0.1, 0.05, 0.9, 0.19);  // плашка названия: x0, y0, x1, y1 (y1 <= y0 — нет)
uniform vec4 plaque = vec4(0.5, 0.9, 0.2, 0.06);      // медальон силы: центр, полуразмеры (hx = 0 — нет)
uniform vec4 text_box = vec4(0.0);                    // стекло под текст: x0, y0, x1, y1 (y1 <= y0 — нет)
uniform float detail = 1.0;                           // 0 — дёшево («Низкие»), 0.6 — без завихрения дымки («Средние»), 1 — всё

const float CF_PI = 3.14159265;
const vec2 CF_LIGHT = vec2(-0.55, -0.835); // свет на металл: слева сверху

float cf_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float cf_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = cf_hash(i);
	float b = cf_hash(i + vec2(1.0, 0.0));
	float c = cf_hash(i + vec2(0.0, 1.0));
	float d = cf_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float cf_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * cf_noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v / 0.875;
}

float cf_fill(float d, float aa) { return smoothstep(aa, -aa, d); }
float cf_line(float d, float w, float aa) { return smoothstep(w + aa, max(w - aa, 0.0), abs(d)); }

float cf_box(vec2 p, vec2 c, vec2 h) {
	vec2 d = abs(p - c) - h;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

float cf_tri(vec2 p, vec2 a, vec2 b, vec2 c) {
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

float cf_hex(vec2 p, float r) {
	const vec3 k = vec3(-0.866025404, 0.5, 0.577350269);
	p = abs(p);
	p -= 2.0 * min(dot(k.xy, p), 0.0) * k.xy;
	p -= vec2(clamp(p.x, -k.z * r, k.z * r), r);
	return length(p) * sign(p.y);
}

float cf_rhombus(vec2 p, vec2 b) {
	p = abs(p);
	float h = clamp((-2.0 * (p.x * b.x - p.y * b.y) + (b.x * b.x - b.y * b.y)) / dot(b, b), -1.0, 1.0);
	float d = length(p - 0.5 * b * vec2(1.0 - h, 1.0 + h));
	return d * sign(p.x * b.y + p.y * b.x - b.x * b.y);
}

// Плашка с заострёнными концами (центр c, полуразмеры h).
float cf_banner(vec2 p, vec2 c, vec2 h) {
	vec2 q = abs(p - c);
	return max(q.y - h.y, (q.x + q.y * 0.9 - h.x) * 0.743);
}

// ---------------------------------------------------------------- символы

// Покрытие символа (0..1); e — локальные координаты эмблемы (~±0.13), aa — ширина сглаживания в них же.
// 0 эмблема, 1..6 стихии, 7 слияние, 8 щит, 9/10 стрелки, 11 обмен, 12 запрет, 13 плюс, 14 перенос, 15 бездна,
// 16 возрождение, 17 копия, 18 когти, 19 ×2, 20 флаг; 21..28 виды: дракон, клык, перо, глаз циклопа, жук, змей, меч, крылатый глаз.
float cf_sigil(vec2 e, int id, float aa) {
	float r = length(e);
	float ang = atan(e.y, e.x);
	if (id == 0) { // эмблема «сфер стихий»: шестилучевая звезда в кольце с шестью сферами
		float star = cf_fill(r - (0.024 + 0.04 * pow(abs(cos(ang * 3.0)), 8.0)), aa);
		float sa = floor(ang / 1.0472 + 0.5) * 1.0472;
		float orbs = cf_fill(length(e - vec2(cos(sa), sin(sa)) * 0.108) - 0.017, aa);
		float ring = cf_line(r - 0.108, 0.004, aa) * (1.0 - cf_fill(length(e - vec2(cos(sa), sin(sa)) * 0.108) - 0.027, aa));
		return clamp(ring + cf_line(r - 0.074, 0.0025, aa) + star + orbs, 0.0, 1.0);
	}
	if (id == 1) { // пламя
		float body = length(e - vec2(0.0, 0.035)) - 0.062;
		float tip = cf_tri(e, vec2(-0.058, 0.03), vec2(0.058, 0.03), vec2(0.012, -0.135));
		float inner = length(e - vec2(0.0, 0.05)) - 0.028;
		return clamp(cf_fill(min(body, tip), aa) - cf_fill(inner, aa) * 0.7, 0.0, 1.0);
	}
	if (id == 2) { // буря: спираль
		float a = ang / 6.28318 + 0.5;
		float t = r / 0.038 - a;
		float d = abs(fract(t) - 0.5) * 0.038;
		return smoothstep(0.009 + aa, 0.005 - aa * 0.5, d) * smoothstep(0.125, 0.11, r) * smoothstep(0.008, 0.02, r);
	}
	if (id == 3) { // свет: восьмилучевая звезда
		float rr = 0.045 + 0.085 * pow(abs(cos(ang * 4.0)), 10.0) + 0.03 * pow(abs(cos(ang * 4.0 + 0.785)), 10.0);
		return cf_fill(r - rr, aa);
	}
	if (id == 4) { // камень: шестигранник с гранью
		return clamp(cf_fill(cf_hex(e, 0.085), aa) - cf_line(cf_hex(e, 0.045), 0.004, aa) * 0.8, 0.0, 1.0);
	}
	if (id == 5) { // тень: полумесяц
		return cf_fill(max(r - 0.1, -(length(e - vec2(0.045, -0.035)) - 0.085)), aa);
	}
	if (id == 6) { // прилив: три волны
		float m = 0.0;
		for (int k = -1; k <= 1; k++) {
			float y = e.y - float(k) * 0.042 - 0.016 * sin(e.x * 55.0 + float(k));
			m = max(m, cf_line(y, 0.007, aa));
		}
		return m * smoothstep(0.115, 0.1, abs(e.x));
	}
	if (id == 7) { // слияние: два сцепленных кольца
		return max(cf_line(length(e - vec2(-0.038, 0.0)) - 0.062, 0.009, aa), cf_line(length(e - vec2(0.038, 0.0)) - 0.062, 0.009, aa));
	}
	if (id == 8) { // щит
		float sh = min(cf_box(e, vec2(0.0, -0.045), vec2(0.08, 0.05)), cf_tri(e, vec2(-0.08, 0.0), vec2(0.08, 0.0), vec2(0.0, 0.115)));
		return clamp(cf_fill(sh, aa) - cf_fill(cf_box(e, vec2(0.0, -0.03), vec2(0.012, 0.05)), aa) * 0.6, 0.0, 1.0);
	}
	if (id == 9 || id == 10) { // стрелка вверх / вниз
		vec2 q = id == 9 ? e : vec2(e.x, -e.y);
		return cf_fill(min(cf_box(q, vec2(0.0, 0.045), vec2(0.024, 0.06)), cf_tri(q, vec2(-0.08, 0.0), vec2(0.08, 0.0), vec2(0.0, -0.115))), aa);
	}
	if (id == 11) { // обмен: две встречные стрелки
		float a1 = min(cf_box(e, vec2(-0.02, -0.04), vec2(0.06, 0.014)), cf_tri(e, vec2(0.03, -0.085), vec2(0.03, 0.005), vec2(0.105, -0.04)));
		float a2 = min(cf_box(e, vec2(0.02, 0.04), vec2(0.06, 0.014)), cf_tri(e, vec2(-0.03, -0.005), vec2(-0.03, 0.085), vec2(-0.105, 0.04)));
		return cf_fill(min(a1, a2), aa);
	}
	if (id == 12) { // запрет: перечёркнутый круг
		return max(cf_line(r - 0.085, 0.011, aa), cf_line((e.x + e.y) * 0.7071, 0.011, aa) * step(r, 0.085));
	}
	if (id == 13) { // плюс
		return cf_fill(min(cf_box(e, vec2(0.0), vec2(0.026, 0.09)), cf_box(e, vec2(0.0), vec2(0.09, 0.026))), aa);
	}
	if (id == 14) { // перенос: дуга-стрелка к точке
		float arc = cf_line(r - 0.075, 0.01, aa) * step(0.0, -e.y + 0.02) * step(-2.6, ang) * step(ang, -0.4);
		float head = cf_fill(cf_tri(e, vec2(0.04, -0.07), vec2(0.11, -0.03), vec2(0.085, -0.115)), aa);
		float dt = cf_fill(length(e - vec2(-0.06, 0.06)) - 0.025, aa);
		return clamp(arc + head + dt, 0.0, 1.0);
	}
	if (id == 15) { // бездна: разорванное кольцо с крестом
		float rg = cf_line(r - 0.09, 0.009, aa) * step(0.025, abs(e.x));
		float x1 = cf_line((e.x - e.y) * 0.7071, 0.009, aa) * step(r, 0.065);
		float x2 = cf_line((e.x + e.y) * 0.7071, 0.009, aa) * step(r, 0.065);
		return clamp(rg + x1 + x2, 0.0, 1.0);
	}
	if (id == 16) { // возрождение: восходящее солнце с лучами
		vec2 s = e - vec2(0.0, 0.03);
		float sun = cf_fill(length(s) - 0.055, aa) * step(e.y, 0.03);
		float rays = smoothstep(0.75, 0.95, abs(cos(atan(-s.y, s.x) * 3.5))) * step(0.07, length(s)) * step(length(s), 0.11) * step(e.y, 0.03);
		float bl = cf_fill(cf_box(e, vec2(0.0, 0.05), vec2(0.11, 0.009)), aa);
		return clamp(sun + rays + bl, 0.0, 1.0);
	}
	if (id == 17) { // копия: два наложенных квадрата
		float a1 = cf_line(cf_box(e, vec2(-0.025, -0.025), vec2(0.055, 0.055)), 0.008, aa);
		float a2 = cf_fill(cf_box(e, vec2(0.03, 0.03), vec2(0.055, 0.055)), aa);
		return clamp(max(a1 * (1.0 - a2), a2 - cf_fill(cf_box(e, vec2(0.03, 0.03), vec2(0.035, 0.035)), aa) * 0.7), 0.0, 1.0);
	}
	if (id == 18) { // когти: три косых удара
		float m = 0.0;
		for (int k = -1; k <= 1; k++) {
			vec2 q = e - vec2(float(k) * 0.045, 0.0);
			m = max(m, cf_line((q.x + q.y * 0.35) * 0.94, max(0.012 - abs(q.y) * 0.1, 0.0015), aa) * step(abs(q.y), 0.1));
		}
		return m;
	}
	if (id == 19) { // ×2: два шеврона вверх
		float c1 = cf_line(((e.y + 0.07) - abs(e.x)) * 0.7071, 0.015, aa) * step(abs(e.x), 0.09);
		float c2 = cf_line((e.y - abs(e.x)) * 0.7071, 0.015, aa) * step(abs(e.x), 0.09);
		return clamp(c1 + c2, 0.0, 1.0);
	}
	if (id == 20) { // удержание: флаг на древке
		float pole = cf_fill(cf_box(e, vec2(-0.05, 0.0), vec2(0.011, 0.11)), aa);
		float flag = cf_fill(cf_tri(e, vec2(-0.04, -0.105), vec2(-0.04, -0.015), vec2(0.09, -0.06)), aa);
		return clamp(pole + flag, 0.0, 1.0);
	}
	if (id == 21) { // дракон: перепончатое крыло
		float wing = cf_tri(e, vec2(-0.1, -0.1), vec2(0.11, -0.03), vec2(-0.07, 0.11));
		float sc = min(min(length(e - vec2(0.03, 0.06)) - 0.05, length(e - vec2(0.09, 0.0)) - 0.045), length(e - vec2(-0.03, 0.115)) - 0.04);
		float ribs = cf_line((e.x + 0.1) * 0.3 - (e.y + 0.1) * 0.95, 0.004, aa) + cf_line((e.x + 0.1) * 0.8 - (e.y + 0.1) * 0.6, 0.004, aa);
		return clamp(cf_fill(max(wing, -sc), aa) - ribs * 0.7 * step(-0.09, e.y), 0.0, 1.0);
	}
	if (id == 22) { // клык: два клыка из пасти
		float jaw = cf_box(e, vec2(0.0, -0.075), vec2(0.105, 0.018));
		float f1 = cf_tri(e, vec2(-0.085, -0.06), vec2(-0.025, -0.06), vec2(-0.06, 0.1));
		float f2 = cf_tri(e, vec2(0.025, -0.06), vec2(0.085, -0.06), vec2(0.06, 0.1));
		float f3 = cf_tri(e, vec2(-0.018, -0.06), vec2(0.018, -0.06), vec2(0.0, 0.0));
		return cf_fill(min(min(jaw, f3), min(f1, f2)), aa);
	}
	if (id == 23) { // перо: лист со стержнем и бородками
		vec2 q = vec2(e.x * 0.94 + e.y * 0.34, -e.x * 0.34 + e.y * 0.94);
		float leaf = max(length(q - vec2(-0.075, 0.0)) - 0.105, length(q - vec2(0.075, 0.0)) - 0.105);
		float barbs = smoothstep(0.55, 0.8, abs(sin((q.y + abs(q.x) * 0.9) * 75.0))) * step(0.012, abs(q.x));
		float shaft = cf_line(q.x, 0.005, aa) * step(-0.135, q.y) * step(q.y, 0.135);
		return clamp(cf_fill(leaf, aa) * (1.0 - barbs * 0.75) + shaft, 0.0, 1.0);
	}
	if (id == 24) { // глаз циклопа: миндаль с радужкой
		float eye = max(length(e - vec2(0.0, 0.085)) - 0.13, length(e - vec2(0.0, -0.085)) - 0.13);
		float iris = length(e) - 0.042;
		return clamp(cf_line(eye, 0.008, aa) + cf_fill(iris, aa) - cf_fill(length(e - vec2(0.012, -0.012)) - 0.012, aa) * 0.8, 0.0, 1.0);
	}
	if (id == 25) { // жук: панцирь и рог
		float shell = length(vec2(e.x * 1.15, e.y - 0.03)) - 0.075;
		float split = cf_line(e.x, 0.004, aa) * step(-0.01, e.y);
		float horn = cf_tri(e, vec2(-0.025, -0.03), vec2(0.025, -0.03), vec2(0.0, -0.13));
		float hk = cf_tri(e, vec2(0.0, -0.1), vec2(0.0, -0.075), vec2(0.045, -0.115));
		return clamp(cf_fill(min(min(shell, horn), hk), aa) - split, 0.0, 1.0);
	}
	if (id == 26) { // змей: изгиб кольцом и голова
		float body = cf_line(e.x - 0.05 * sin(e.y * 30.0), 0.016 - e.y * 0.05, aa) * step(-0.09, e.y) * step(e.y, 0.12);
		float head = cf_fill(length(vec2(e.x * 0.8, e.y + 0.1)) - 0.03, aa);
		return clamp(body + head, 0.0, 1.0);
	}
	if (id == 27) { // меч: клинок, гарда, навершие
		float blade = cf_tri(e, vec2(-0.017, 0.045), vec2(0.017, 0.045), vec2(0.0, -0.13));
		float guard = cf_box(e, vec2(0.0, 0.05), vec2(0.07, 0.011));
		float grip = cf_box(e, vec2(0.0, 0.085), vec2(0.009, 0.03));
		float pom = length(e - vec2(0.0, 0.122)) - 0.016;
		return cf_fill(min(min(blade, guard), min(grip, pom)), aa);
	}
	if (id == 28) { // крылатый глаз
		float eye = length(e) - 0.04;
		float w1 = cf_tri(vec2(abs(e.x), e.y), vec2(0.035, -0.01), vec2(0.13, -0.08), vec2(0.1, 0.04));
		return clamp(cf_fill(min(eye, w1), aa) - cf_fill(length(e) - 0.016, aa) * 0.9, 0.0, 1.0);
	}
	return 0.0;
}

// ---------------------------------------------------------------- рамка и окно

vec3 cf_metal_color(vec3 g) {
	if (frame == 0) { return vec3(0.98, 0.76, 0.38); }        // золото
	if (frame == 1) { return vec3(0.80, 0.84, 0.92); }        // серебро
	if (frame == 2) { return vec3(0.84, 0.52, 0.30); }        // бронза
	if (frame == 3) { return vec3(0.70, 0.30, 0.22); }        // тёмная медь
	if (frame == 6 || frame == 7) { return vec3(0.50, 0.76, 0.62); } // патина
	if (frame == 9) { return mix(vec3(0.66, 0.68, 0.76), g, 0.3); }
	return mix(vec3(0.66, 0.68, 0.74), g, 0.35);              // воронёная сталь с отливом стихии
}

// Металл по профилю кромки: t поперёк полосы (0 снаружи, 1 внутри), lit — повёрнутость стороны к свету (-1..1).
vec3 cf_shade_metal(vec3 m, float t, float lit) {
	float prof = cos(clamp(t, 0.0, 1.0) * CF_PI);
	float l = 0.52 + 0.4 * lit * prof + 0.14 * (1.0 - abs(prof));
	vec3 c = m * (0.18 + 0.95 * l);
	return c + vec3(1.0, 0.97, 0.9) * pow(max(l, 0.0), 7.0) * 0.45;
}

// Контур окна по типу рамки (центр — центр окна).
float cf_window_sd(vec2 e, float r) {
	if (frame <= 3) { // арка ворот: свод сверху, прямые стены вниз
		vec2 a = e - vec2(0.0, -0.12 * r);
		float rw = r * 0.86;
		if (a.y >= 0.0) { return max(abs(a.x) - rw, a.y - 1.2 * r); }
		if (frame >= 2) { // стрельчатый свод
			float k = r * 0.5;
			return max(length(a - vec2(-k, 0.0)) - (rw + k), length(a - vec2(k, 0.0)) - (rw + k));
		}
		return length(a) - rw;
	}
	if (frame == 5) { return cf_rhombus(e, vec2(r * 0.9, r * 1.12)); }
	if (frame == 6) { return cf_hex(vec2(e.y, e.x), r * 0.88); }
	if (frame == 7) { return min(length(e - vec2(-0.3 * r, 0.0)) - 0.72 * r, length(e - vec2(0.3 * r, 0.0)) - 0.72 * r); }
	return length(e) - r;
}

// Руна в клетке uv (0..1): ствол и штрихи по битам h.
float cf_rune(vec2 uv, float h) {
	float w = 0.13;
	float inside = step(0.0, uv.x) * step(uv.x, 1.0);
	float g = smoothstep(w, w * 0.3, abs(uv.x - 0.5)) * step(0.12, uv.y) * step(uv.y, 0.88);
	if (h > 0.5) { g = max(g, smoothstep(w, w * 0.3, abs(uv.y - 0.35 - (uv.x - 0.5) * 0.9)) * step(abs(uv.x - 0.5), 0.36)); }
	if (fract(h * 7.0) > 0.45) { g = max(g, smoothstep(w, w * 0.3, abs(uv.y - 0.74)) * step(abs(uv.x - 0.5), 0.32)); }
	if (fract(h * 13.0) > 0.6) { g = max(g, smoothstep(w, w * 0.3, abs(length(uv - vec2(0.5, 0.3)) - 0.2)) * step(uv.x, 0.5)); }
	return g * inside;
}

// Металлическая накладка в углу: q — координаты от угла внутрь (≥ 0).
void cf_corner(vec2 q, float aa, vec3 metal_c, inout vec3 col, inout vec3 em, inout float metal) {
	vec2 gc = vec2(0.082, 0.082);           // центр камня
	float plate;
	if (frame == 0) { // золото: круглая накладка с завитками-дугами
		plate = min(length(q - gc) - 0.04, abs(length(q - vec2(0.02)) - 0.11) - 0.006 + step(0.17, q.x + q.y) * 1.0);
	} else if (frame == 1) { // серебро: ромб
		plate = (abs(q.x - gc.x) + abs(q.y - gc.y) - 0.055) * 0.7071;
	} else if (frame == 2 || frame == 3) { // бронза: треугольный клин со срезом
		plate = max((q.x + q.y - 0.17) * 0.7071, -min(q.x, q.y) + 0.035);
		if (frame == 3) { plate = min(plate, cf_tri(q, vec2(0.11, 0.035), vec2(0.035, 0.11), vec2(0.15, 0.15))); }
	} else if (frame == 6 || frame == 7) { // патина: шестигранник и коготь
		plate = min(cf_hex(q - gc, 0.04), abs((q.x - q.y) * 0.7071) - 0.006 + step(0.2, q.x + q.y));
	} else { // сталь: уголок-скоба с ромбом
		float arm = min(cf_box(q, vec2(0.115, 0.06), vec2(0.06, 0.006)), cf_box(q, vec2(0.06, 0.115), vec2(0.006, 0.06)));
		plate = min(arm, (abs(q.x - gc.x) + abs(q.y - gc.y) - 0.045) * 0.7071);
	}
	float pm = cf_fill(plate, aa);
	// тень под накладкой на основу
	col *= 1.0 - smoothstep(0.02, 0.0, plate - 0.004) * 0.5 * (1.0 - pm);
	float lit = dot(normalize(q - gc + vec2(0.0001)), -CF_LIGHT);
	vec3 mc = cf_shade_metal(metal_c, 0.5 + 0.5 * clamp(-plate / 0.02, 0.0, 1.0), lit * 0.6);
	mc *= 1.0 - cf_line(plate + 0.008, 0.0015, aa) * 0.45;   // гравированная обводка
	col = mix(col, mc, pm);
	metal = max(metal, pm);
	// камень
	float gr = 0.018;
	float gd = frame == 1 || frame == 4 || frame == 5 ? (abs(q.x - gc.x) + abs(q.y - gc.y) - gr * 1.25) * 0.7071 : length(q - gc) - gr;
	float gm = cf_fill(gd, aa);
	vec3 gcol = gem.a > 0.5 ? gem.rgb : metal_c * 0.35 + base.rgb * 0.3;
	vec2 gl = q - gc;
	float facet = 0.6 + 0.4 * clamp(dot(normalize(gl + vec2(0.0001)), -CF_LIGHT), -1.0, 1.0) * smoothstep(0.0, gr, length(gl));
	col = mix(col, gcol * facet * 0.6, gm);
	em += gcol * gm * (gem.a > 0.5 ? 0.9 : 0.1) + vec3(1.0) * gm * smoothstep(0.012, 0.0, length(gl - vec2(-0.006, -0.006))) * 0.6;
	metal = mix(metal, 0.0, gm);
}

// Основной облик. Выход: col — поверхность (освещаемая), em — собственный свет (руны, символ, кромки),
// metal — доля металла, alpha — покрытие карты, osd — расстояние до внешнего края (< 0 внутри).
void card_face(vec2 p, float aa, float t, out vec3 col, out vec3 em, out float metal, out float alpha, out float osd) {
	vec3 g = glow.rgb;
	vec3 metal_c = cf_metal_color(g);
	vec2 c = vec2(0.5, aspect * 0.5);
	vec2 q = abs(p - c) - vec2(0.5, aspect * 0.5);
	// внешний контур
	float rad = 0.04;
	osd = length(max(q + rad, vec2(0.0))) + min(max(q.x + rad, q.y + rad), 0.0) - rad;
	if (frame == 2 || frame == 3) {
		osd = max(max(q.x, q.y), (q.x + q.y + 0.075) * 0.7071);
	} else if (frame == 1) {
		osd = max(max(q.x, q.y), 0.055 - length(q));
	}
	alpha = cf_fill(osd, aa);
	float d = -osd;
	em = vec3(0.0);
	metal = 0.0;

	// --- основа: туманность стихии, дымка и искры
	vec2 nq = p * 2.4 + vec2(t * 0.022, -t * 0.016);
	float n1 = cf_fbm(nq);
	float n2 = detail > 0.75 ? cf_fbm(nq * 1.7 + vec2(n1 * 2.4, -n1 * 1.6) + vec2(3.1, 1.3) - vec2(t * 0.03, 0.0)) : n1;
	col = base.rgb * 0.16 + vec3(0.012, 0.012, 0.026);
	col = mix(col, base.rgb * 0.55 + g * 0.05, smoothstep(0.3, 0.85, n1) * 0.6);
	em += g * smoothstep(0.5, 0.95, n2) * 0.16 * smoothstep(0.0, 0.25, d);
	float vig = length((p - c) / vec2(0.62, aspect * 0.62));
	col *= 1.05 - 0.45 * smoothstep(0.55, 1.0, vig);
	vec2 sg = p * 30.0 + vec2(0.0, t * 0.05);
	vec2 cell = floor(sg);
	float sh = cf_hash(cell);
	vec2 sp = fract(sg) - 0.5 - (vec2(cf_hash(cell + 7.1), cf_hash(cell + 3.7)) - 0.5) * 0.6;
	float star = step(0.9, sh) * smoothstep(0.08 + aa * 30.0, 0.0, length(sp)) * (0.45 + 0.55 * sin(t * 1.7 + sh * 60.0));
	em += mix(g, vec3(1.0), 0.6) * max(star, 0.0) * 0.55;

	// --- окно
	vec2 e = p - win.xy;
	float wr = win.z;
	float ang = atan(e.y, e.x);
	float wsd = cf_window_sd(e, wr);
	float rr = length(e) / wr;
	// круг рун позади окна (тонкий, едва светится) — мистический «круг призыва»
	float back_ring = cf_line(length(e) - wr * 1.32, 0.0018, aa) + cf_line(length(e) - wr * 1.4, 0.0012, aa);
	float ticks = smoothstep(0.6, 1.0, abs(cos(ang * 18.0 + t * 0.05))) * step(wr * 1.32, length(e)) * step(length(e), wr * 1.4);
	em += g * (back_ring * 0.35 + ticks * 0.12) * smoothstep(0.02, 0.08, d);
	if (frame == 0) { // поле: лучи солнца за аркой
		em += g * pow(abs(cos(ang * 12.0)), 30.0) * smoothstep(wr * 1.6, wr, length(e)) * step(0.0, wsd) * 0.25;
	}
	// ореол вокруг ободка
	em += g * exp(-max(wsd, 0.0) / (wr * 0.12)) * step(0.0, wsd) * 0.22;

	float wm = cf_fill(wsd, aa);
	if (wm > 0.0) { // внутренность окна считаем только внутри него
		// внутренность: свет из глубины, вращающийся эфир
		vec3 inner = mix(g * 0.38 + base.rgb * 0.25, base.rgb * 0.08 + vec3(0.01, 0.01, 0.02), smoothstep(0.0, 1.1, rr));
		vec3 inner_em = g * 0.22 * smoothstep(1.0, 0.0, rr);
		float ca = cos(t * 0.12);
		float sa = sin(t * 0.12);
		vec2 re = vec2(ca * e.x - sa * e.y, sa * e.x + ca * e.y) / wr;
		float mist = cf_fbm(re * 2.2 + vec2(5.0, 2.0));
		inner_em += g * smoothstep(0.45, 0.95, mist) * 0.3 * (1.0 - 0.5 * rr);
		inner_em += g * pow(abs(sin(ang * 3.0 + t * 0.15)), 14.0) * smoothstep(1.0, 0.15, rr) * 0.12;
		if (detail > 0.5) { // глубина портала: медленные кольца, уходящие внутрь
			inner_em += g * pow(0.5 + 0.5 * sin(rr * 24.0 + t * 1.1), 6.0) * smoothstep(1.0, 0.25, rr) * smoothstep(0.05, 0.3, rr) * 0.07;
		}
		if (frame == 8 || frame == 9) { // сфера: объём шара
			float z = sqrt(max(1.0 - rr * rr, 0.0));
			inner = mix(inner, g * 0.18 * (0.3 + z), 0.6);
			inner_em += vec3(1.0) * pow(max(dot(normalize(vec3(e / wr, z)), normalize(vec3(-0.45, -0.6, 0.65))), 0.0), 24.0) * 0.5 * step(rr, 1.0);
		}
		// руны по кромке окна
		if (detail > 0.25) {
			float rb0 = wr * 0.06;
			float rb1 = wr * 0.2;
			float v = (-wsd - rb0) / (rb1 - rb0);
			float n = frame == 5 ? 12.0 : 16.0;
			float a = fract(ang / (2.0 * CF_PI) + 0.5 + t * 0.006) * n;
			float ci = floor(a);
			float k = (2.0 * CF_PI * wr * 0.86 / n) / (rb1 - rb0);
			vec2 uv = vec2((fract(a) - 0.5) * k * 1.4 + 0.5, v);
			float rune = cf_rune(uv, cf_hash(vec2(ci, float(frame)))) * step(0.0, v) * step(v, 1.0);
			float pulse = 0.55 + 0.45 * sin(t * 1.3 - ci * 0.8);
			inner_em += g * rune * (0.5 + 0.6 * pulse);
			inner = mix(inner, inner * 0.6, cf_line(-wsd - rb1 - wr * 0.03, 0.0015, aa)); // тонкая черта под рунами
			inner_em += g * cf_line(-wsd - rb1 - wr * 0.03, 0.0012, aa) * 0.4;
		}
		// символ с ореолом
		vec2 so = frame <= 3 ? vec2(0.0, 0.08 * wr) : vec2(0.0);
		float sk = 0.13 / (wr * (frame == 5 ? 0.52 : 0.6));
		vec2 se = (e - so) * sk;
		int sid = sigil;
		float sm = 0.0;
		float halo = 0.0;
		if (frame == 9) { // рубашка: звезда в кольцах
			sid = 0;
		}
		sm = cf_sigil(se, sid, aa * sk * 1.2);
		halo = cf_sigil(se * 0.86, sid, aa * sk * 3.0 + 0.016);
		inner_em += g * halo * 0.75;
		inner = mix(inner, mix(g, vec3(1.0), 0.55) * 0.7, sm);
		inner_em += mix(g, vec3(1.0, 0.98, 0.94), 0.62) * sm * 1.15;
		inner *= 1.0 - smoothstep(0.0, wr * 0.15, wsd + wr * 0.15) * 0.4; // затенение у ободка
		if (frame == 3) { // знак ловушки: багровый глаз под самым сводом стрельчатой арки
			vec2 ey = (e - vec2(0.0, -0.98 * wr)) / wr;
			float lid = max(length(ey - vec2(0.0, 0.2)) - 0.32, length(ey - vec2(0.0, -0.2)) - 0.32) * wr;
			float pupil = (length(vec2(ey.x * 1.6, ey.y)) - 0.075) * wr;
			float lm = cf_fill(lid, aa);
			inner = mix(inner, vec3(0.05, 0.0, 0.005), cf_fill(lid - wr * 0.04, aa));
			inner_em *= 1.0 - cf_fill(lid - wr * 0.04, aa);
			inner_em += vec3(1.0, 0.16, 0.07) * (lm * 0.9 - cf_fill(pupil, aa) * 0.85 + cf_line(lid, 0.002, aa) * 0.6);
			inner_em += vec3(1.0, 0.2, 0.08) * smoothstep(wr * 0.18, 0.0, lid) * (1.0 - lm) * 0.35;
		}
		col = mix(col, inner, wm);
		em = mix(em, inner_em + em * 0.2, wm);
	}
	// металлический ободок окна + светящаяся внутренняя кромка
	float bz = 0.019;
	float bm = cf_fill(wsd - bz, aa) * (1.0 - wm);
	vec2 en = normalize(e + vec2(0.0001));
	vec3 bc = cf_shade_metal(metal_c, wsd / bz, dot(en, CF_LIGHT) * -1.0);
	bc *= 1.0 - cf_line(wsd - bz * 0.5, 0.0012, aa) * 0.5;
	col = mix(col, bc, bm);
	metal = max(metal, bm);
	em *= 1.0 - bm * 0.85;
	em += g * cf_line(wsd + 0.001, 0.0015, aa) * 0.9;
	col = mix(col, col * 0.3, cf_line(wsd - bz - 0.003, 0.002, aa) * (1.0 - bm)); // тень снаружи ободка

	// --- плашка названия
	if (title_box.w > title_box.y) {
		vec2 tc = (title_box.xy + title_box.zw) * 0.5;
		vec2 th = (title_box.zw - title_box.xy) * 0.5;
		float tsd = cf_banner(p, tc, th);
		float tm = cf_fill(tsd, aa);
		col *= 1.0 - smoothstep(0.03, 0.0, tsd) * 0.45 * (1.0 - tm);
		float ty = (p.y - title_box.y) / (title_box.w - title_box.y);
		vec3 lac = mix(vec3(0.05, 0.05, 0.085) + base.rgb * 0.18, vec3(0.015, 0.015, 0.03), ty);
		col = mix(col, lac, tm);
		em *= 1.0 - tm * 0.8;
		em += g * tm * smoothstep(0.5, 0.0, abs(ty - 0.5)) * 0.04;
		float tb = cf_line(tsd + 0.004, 0.004, aa);
		vec3 tbc = cf_shade_metal(metal_c, 0.5, (p.y < tc.y ? 1.0 : -1.0) * 0.8);
		col = mix(col, tbc, tb);
		metal = max(metal, tb);
		em += g * cf_line(tsd + 0.012, 0.0012, aa) * 0.45 * tm;
	}

	// --- стекло под текст
	if (text_box.w > text_box.y) {
		vec2 xc = (text_box.xy + text_box.zw) * 0.5;
		vec2 xh = (text_box.zw - text_box.xy) * 0.5;
		float xsd = cf_box(p, xc, xh - 0.015) - 0.015;
		float xm = cf_fill(xsd, aa);
		col = mix(col, col * 0.25 + vec3(0.012, 0.012, 0.024), xm * 0.85);
		em *= 1.0 - xm * 0.75;
		float xb = cf_line(xsd + 0.002, 0.0022, aa);
		col = mix(col, cf_shade_metal(metal_c, 0.5, 0.0) * 0.75, xb);
		metal = max(metal, xb);
		em += g * cf_line(p.y - text_box.y - 0.01, 0.0012, aa) * step(abs(p.x - xc.x), xh.x * 0.6) * 0.5 * (1.0 - abs(p.x - xc.x) / xh.x);
	}

	// --- медальон силы
	if (plaque.z > 0.0) {
		float psd = cf_banner(p, plaque.xy, plaque.zw);
		float pm = cf_fill(psd, aa);
		col *= 1.0 - smoothstep(0.035, 0.0, psd) * 0.55 * (1.0 - pm);
		float py = (p.y - plaque.y) / plaque.w;
		vec3 pc = mix(vec3(0.03, 0.03, 0.05) + g * 0.12, vec3(0.01, 0.01, 0.02), py * 0.5 + 0.5);
		col = mix(col, pc, pm);
		em *= 1.0 - pm;
		em += g * pm * exp(-abs(py) * 2.2) * 0.12;
		float pb = cf_line(psd + 0.006, 0.006, aa);
		col = mix(col, cf_shade_metal(metal_c, 0.5 - py * 0.5, -py * 0.8), pb);
		metal = max(metal, pb);
		em += g * cf_line(psd + 0.015, 0.0015, aa) * 0.7;
		// ступени силы — ромбы по бокам
		for (int i = 0; i < 3; i++) {
			if (float(i) >= tier) { break; }
			float dx = plaque.z + 0.032 + float(i) * 0.042;
			float rd = min(cf_rhombus(p - vec2(plaque.x - dx, plaque.y), vec2(0.018, 0.03)),
				cf_rhombus(p - vec2(plaque.x + dx, plaque.y), vec2(0.018, 0.03)));
			float rm = cf_fill(rd, aa);
			col = mix(col, g * 0.5, rm);
			em += mix(g, vec3(1.0), 0.35) * rm * 0.9 + g * smoothstep(0.02, 0.0, rd) * 0.2;
		}
	}

	// --- угловые накладки
	vec2 cq = vec2(min(p.x, 1.0 - p.x), min(p.y, aspect - p.y));
	if (cq.x + cq.y < 0.3) {
		cf_corner(cq, aa, metal_c, col, em, metal);
	}

	// --- металлическая рамка: скат, желобок с ромбиками, внутренний кант и свет эфира
	float bw = 0.04;
	vec2 side_n = q.x > q.y ? vec2(sign(p.x - c.x), 0.0) : vec2(0.0, sign(p.y - c.y));
	float lit = dot(side_n, CF_LIGHT) * -1.0;
	vec3 fm = cf_shade_metal(metal_c, d / bw, lit);
	float along = abs(side_n.x) > 0.5 ? p.y : p.x;
	float groove = cf_line(d - bw * 0.5, 0.0018, aa);
	float dia = (abs(fract(along * 10.0) - 0.5) / 10.0 + abs(d - bw * 0.5)) - 0.009;
	fm *= 1.0 - groove * 0.55;
	fm = mix(fm, fm * 1.35 + metal_c * 0.12, cf_fill(dia, aa));
	float band = cf_fill(d - bw, aa);
	col = mix(col, fm, band);
	metal = max(metal, band);
	em *= 1.0 - band;
	float fillet = cf_line(d - bw - 0.009, 0.0025, aa);
	col = mix(col, cf_shade_metal(metal_c, 0.5, lit) * 0.85, fillet);
	metal = max(metal, fillet);
	col *= 1.0 - cf_line(d - bw - 0.0035, 0.002, aa) * 0.6;
	em += g * cf_line(d - bw - 0.018, 0.0012, aa) * 0.4;
	em += g * smoothstep(0.07, 0.0, d - bw - 0.012) * step(bw + 0.012, d) * 0.06;
}
