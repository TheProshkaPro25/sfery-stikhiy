// Здания пейзажа меню (один MultiMesh из единичных кубов). Окна — сетка по метрическим координатам фасада:
// у каждого окна свой порог зажигания (доля горящих окон win_on растёт вечером и падает к утру — окна
// загораются и гаснут в разное время), тёплый или холодный свет, шторы. Плюс неоновые вывески, подсветка
// верхушек и рёбер, мигающие красные огни на антеннах. Огни — только эмиссия (без источников света).
// INSTANCE_CUSTOM: x — зерно 0..1, y — тип (0 стекло, 1 офис-ленты, 2 жилой, 3 тёмная башня, 4 надстройка,
// 5 антенна, 6 частный дом, 7 бетон моста/набережной, 8 пилон моста), z — флаги (1 неон, 2 корона, 4 рёбра,
// 8 огни на углах крыши), w — оттенок неона 0..1.
shader_type spatial;
render_mode diffuse_burley;

uniform float win_on = 0.0;
uniform float night = 0.0;
uniform float anim_t = 0.0;
uniform vec3 sky_tint : source_color = vec3(0.5, 0.6, 0.8);

varying vec3 lp;
varying vec3 sz;
varying flat vec4 cd;
varying vec3 ln;

float h11(float p) { p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }
float h21(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float h31(vec3 p3) { p3 = fract(p3 * 0.1031); p3 += dot(p3, p3.zyx + 31.32); return fract((p3.x + p3.y) * p3.z); }

vec3 hue(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}

// сглаженная прямоугольная маска окна внутри ячейки (fr — 0..1 в ячейке)
float box_mask(vec2 fr, vec2 size, vec2 fw) {
	vec2 lo = (1.0 - size) * 0.5;
	vec2 hi = 1.0 - lo;
	vec2 m = smoothstep(lo - fw, lo + fw, fr) * (1.0 - smoothstep(hi - fw, hi + fw, fr));
	return m.x * m.y;
}

void vertex() {
	lp = VERTEX + 0.5;
	sz = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	cd = INSTANCE_CUSTOM;
	ln = NORMAL;
}

void fragment() {
	int kind = int(cd.y + 0.5);
	int flags = int(cd.z + 0.5);
	float seed = cd.x;
	vec3 m = lp * sz;
	bool roof = ln.y > 0.5;
	bool side_x = abs(ln.x) > 0.5;
	vec2 f = side_x ? vec2(m.z, m.y) : vec2(m.x, m.y);
	float face_w = side_x ? sz.z : sz.x;
	float face_id = side_x ? (ln.x > 0.0 ? 1.0 : 2.0) : (ln.z > 0.0 ? 3.0 : 4.0);
	float hb = h11(seed * 917.0);

	// палитра фасада
	vec3 wall;
	vec3 glass;
	vec2 cell;
	vec2 wsize;
	float glass_metal = 0.3;
	if (kind == 0) {        // стеклянная башня
		wall = mix(vec3(0.20, 0.24, 0.28), vec3(0.55, 0.58, 0.62), hb);
		glass = mix(vec3(0.07, 0.16, 0.22), vec3(0.10, 0.20, 0.30), h11(seed * 31.0));
		cell = vec2(1.7, 3.7); wsize = vec2(0.90, 0.82);
	} else if (kind == 1) { // офис с лентами окон
		wall = mix(vec3(0.62, 0.60, 0.56), vec3(0.80, 0.78, 0.74), hb);
		glass = vec3(0.09, 0.12, 0.16);
		cell = vec2(1.9, 3.8); wsize = vec2(0.97, 0.52);
	} else if (kind == 2 || kind == 6) { // жилой: кирпич, беж, пастель
		vec3 c1 = vec3(0.55, 0.30, 0.22);
		vec3 c2 = vec3(0.78, 0.68, 0.52);
		vec3 c3 = vec3(0.62, 0.66, 0.70);
		wall = hb < 0.33 ? c1 : (hb < 0.66 ? c2 : c3);
		wall *= 0.85 + 0.3 * h11(seed * 53.0);
		glass = vec3(0.08, 0.10, 0.13);
		cell = vec2(3.3, 3.0); wsize = vec2(0.42, 0.50);
		glass_metal = 0.2;
	} else if (kind == 3) { // тёмная башня (бронза/чёрное стекло)
		wall = mix(vec3(0.08, 0.08, 0.09), vec3(0.25, 0.20, 0.14), hb);
		glass = mix(vec3(0.05, 0.05, 0.06), vec3(0.14, 0.10, 0.06), hb);
		cell = vec2(1.5, 4.0); wsize = vec2(0.80, 0.78);
	} else {
		wall = kind == 5 ? vec3(0.22) : (kind == 7 ? vec3(0.42, 0.41, 0.40) : (kind == 8 ? vec3(0.78, 0.78, 0.80) : vec3(0.36, 0.37, 0.39)));
		glass = wall;
		cell = vec2(1.0); wsize = vec2(0.0);
	}

	vec3 albedo = wall;
	float rough = 0.85;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	bool windows = kind <= 3 || kind == 6;

	if (roof) {
		// крыша: тёмный рубероид/гравий, у надстроек — металл
		float n = h21(floor(m.xz * 1.5));
		albedo = (kind <= 3 ? vec3(0.17, 0.17, 0.18) : wall * 0.8) * (0.85 + 0.25 * n);
		rough = 0.9;
	} else if (ln.y < -0.5) {
		albedo = vec3(0.1);
	} else if (windows) {
		float ground = kind == 6 ? 0.0 : 4.6;   // первый этаж — витрины
		float parapet = kind == 6 ? 0.6 : 1.6;
		float top = sz.y - parapet;
		float cols = max(floor(face_w / cell.x), 1.0);
		float u = (f.x - (face_w - cols * cell.x) * 0.5) / cell.x;
		float v = (f.y - ground) / cell.y;
		float rows = floor((top - ground) / cell.y);
		vec2 fw = fwidth(vec2(u, v)) * 0.7;
		float far = smoothstep(0.35, 0.9, max(fw.x, fw.y));   // ячейки мельче пары пикселей — среднее
		vec2 ci = floor(vec2(u, v));
		vec2 fr = fract(vec2(u, v));
		bool in_grid = u >= 0.0 && u < cols && v >= 0.0 && v < rows;
		float wm = in_grid ? box_mask(fr, wsize, fw) : 0.0;
		wm = mix(wm, in_grid ? wsize.x * wsize.y : 0.0, far);
		// межэтажные пояса чуть темнее, у офисов — вертикальные пилоны
		float belt = smoothstep(0.0, 0.06 + fw.y, fr.y) * (1.0 - smoothstep(0.94 - fw.y, 1.0, fr.y));
		albedo = wall * mix(0.82, 1.0, in_grid ? belt : 1.0);
		// огонёк окна
		float hw = h31(vec3(ci, face_id + seed * 113.0));
		float hf = h21(vec2(ci.y, seed * 71.0 + face_id));
		float bias = mix(0.45, 1.55, h11(seed * 7.7));          // одни дома ярче, другие темнее
		float order = mix(hw, hf, kind == 1 ? 0.55 : 0.3);        // офисы зажигаются этажами
		float lit = step(order, win_on * bias);
		// тёплый / холодный / офисный белый, у некоторых — синий мерцающий телевизор
		float tone = h11(hw * 97.0 + seed);
		float warmth = mix(0.45, 0.9, h11(seed * 19.0));
		vec3 lc = tone < warmth ? vec3(1.0, 0.62, 0.30) : (tone < warmth + 0.2 ? vec3(0.62, 0.78, 1.0) : vec3(1.0, 0.88, 0.70));
		if (h11(hw * 311.0) > 0.985) {
			lc = vec3(0.5, 0.6, 1.0) * (0.75 + 0.25 * sin(anim_t * 9.0 + hw * 50.0));
		}
		// внутри окна: ярче к потолку, шторы
		float inner = mix(0.55 + 0.45 * fr.y, 0.85, far) * (0.55 + 0.45 * h11(hw * 13.0));
		float bright = (kind == 6 ? 1.2 : 1.25) * mix(0.06, 1.0, night);
		vec3 we = lc * lit * inner * bright;
		// дальние фасады: средний свет по доле горящих окон (без мерцания сетки)
		we = mix(we, lc * clamp(win_on * bias, 0.0, 1.0) * 0.7 * bright, far * 0.5);
		// витрины первого этажа
		if (f.y < ground && f.y > 0.3 && kind != 6) {
			float sh = h21(vec2(floor(f.x / 6.0), seed * 17.0 + face_id));
			float shop = (1.0 - smoothstep(ground - 1.4, ground - 1.2, f.y)) * smoothstep(0.8, 1.0, f.y);
			albedo = mix(albedo, glass, shop * 0.8);
			vec3 sc = sh > 0.7 ? hue(sh * 3.0) * 0.6 + 0.4 : vec3(1.0, 0.82, 0.55);
			emit += sc * shop * step(0.25, sh) * night * 1.8;
		}
		// стекло днём отражает небо
		vec3 gl = glass * (0.8 + 0.4 * h11(hw * 5.3));
		gl += sky_tint * 0.05 * (1.0 - night);
		albedo = mix(albedo, gl, wm);
		rough = mix(rough, 0.12, wm);
		metal = mix(0.0, glass_metal, wm);
		emit += we * wm;
		// у стеклянных башен стекло и между окнами (сплошная навеска)
		if (kind == 0 || kind == 3) {
			float spandrel = in_grid ? 1.0 - wm : 0.0;
			albedo = mix(albedo, glass * 0.8, spandrel * 0.65);
			rough = mix(rough, 0.2, spandrel * 0.65);
			metal = mix(metal, 0.4, spandrel * 0.65);
		}
	} else if (kind == 7) {
		// бетон: полосы швов
		albedo *= 0.85 + 0.15 * step(0.5, fract(f.x / 8.0));
	}

	// неоновая вывеска на фасаде к камере
	if ((flags & 1) != 0 && !roof && face_id == 3.0) {
		float sh = sz.y - 10.0 - h11(seed * 3.3) * min(sz.y * 0.3, 30.0);
		float sw = min(face_w * 0.7, 26.0);
		vec2 q = vec2(f.x - face_w * 0.5, f.y - sh) / vec2(sw * 0.5, 3.2);
		if (abs(q.x) < 1.0 && abs(q.y) < 1.0) {
			vec3 nc = hue(cd.w) * 0.8 + 0.2;
			float frame = step(0.88, max(abs(q.x), abs(q.y) * 0.97));
			// «буквы»: случайные столбики
			float lx = floor((q.x + 1.0) * 6.0);
			float letter = step(0.3, h21(vec2(lx, seed * 9.0))) * step(abs(q.y), 0.6) * step(0.25, fract((q.x + 1.0) * 6.0)) * step(fract((q.x + 1.0) * 6.0), 0.8);
			float run = 0.75 + 0.25 * sin(anim_t * 3.0 - q.x * 4.0);
			float flick = step(0.04, fract(sin(floor(anim_t * 7.0) + seed * 40.0) * 43758.5));
			albedo = mix(albedo, vec3(0.05), 0.8);
			emit += nc * (frame * 1.4 + letter * run * 1.1) * mix(0.15, 3.2, night) * mix(1.0, flick, 0.6);
		}
	}
	// подсветка верхушки (корона)
	if ((flags & 2) != 0) {
		float band = smoothstep(sz.y - 5.0, sz.y - 4.4, m.y) * (1.0 - smoothstep(sz.y - 1.4, sz.y - 1.0, m.y));
		float fins = step(0.5, fract(f.x / 2.4));
		vec3 cc = mix(vec3(0.6, 0.9, 1.0), vec3(1.0, 0.8, 0.45), step(0.5, cd.w));
		emit += cc * band * (roof ? 0.0 : 1.0) * mix(0.3, 1.0, fins) * 2.6 * night;
	}
	// светодиодные рёбра башни
	if ((flags & 4) != 0 && !roof) {
		float e = min(f.x, face_w - f.x);
		float strip = 1.0 - smoothstep(0.25, 0.55, e);
		vec3 ec = hue(fract(cd.w + 0.5)) * 0.6 + 0.4;
		emit += ec * strip * 2.0 * night;
	}
	// красные огни: верх антенны и углы крыши высоких домов
	float blink = step(0.55, sin(anim_t * 3.1 + seed * 30.0));
	if (kind == 5 && lp.y > 0.965) {
		emit += vec3(1.0, 0.08, 0.04) * (0.4 + 5.0 * blink) * max(night, 0.35);
	}
	if ((flags & 8) != 0 && m.y > sz.y - 1.2) {
		vec2 c = min(m.xz, sz.xz - m.xz);
		float corner = step(max(c.x, c.y), 1.2);
		emit += vec3(1.0, 0.1, 0.05) * corner * (0.3 + 4.0 * blink) * max(night, 0.3);
	}
	if (kind == 8) {
		// пилон моста: вертикальная подсветка
		emit += vec3(1.0, 0.85, 0.6) * smoothstep(0.75, 1.0, 1.0 - abs(fract(m.y / 6.0) - 0.5) * 2.0) * night * 0.9;
	}

	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = mix(0.15, 0.5, step(rough, 0.5));
	EMISSION = emit;
}
