// Здания пейзажа меню (один MultiMesh из единичных кубов). Окна — сетка по метрическим координатам фасада:
// у каждого окна свой порог зажигания (доля горящих окон win_on растёт вечером и падает к утру — окна
// загораются и гаснут в разное время), тёплый или холодный свет, шторы. Плюс неоновые вывески, подсветка
// верхушек и рёбер, мигающие красные огни на антеннах. Огни — только эмиссия (без источников света).
// INSTANCE_CUSTOM: x — зерно 0..1, y — тип (0 стекло, 1 офис-ленты, 2 жилой, 3 тёмная башня, 4 надстройка,
// 5 антенна, 6 частный дом, 7 бетон моста/набережной, 8 пилон моста), z — флаги (1 неон, 2 корона, 4 рёбра,
// 8 огни на углах крыши), w — оттенок неона 0..1.
// Днём фасады — с деталями (всё процедурно, без текстур): рамы и импосты окон, подоконники, этажные карнизы
// с тенью, цоколь, маркизы над витринами, руст на углах кирпичных домов, верхний карниз, потёки и грязь
// у земли. Крыши: парапет с тенью, гравий/плитка, вентрешётки, у части — сады, солнечные панели, вертолётные площадки.
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
		if (kind <= 3 || kind == 6) {
			vec2 e2 = min(m.xz, sz.xz - m.xz);
			float e = min(e2.x, e2.y);
			vec2 rf = fwidth(m.xz);
			float px = max(rf.x, rf.y);
			float rh = h11(seed * 59.0);
			// плитка/рубероид полосами, вентрешётки
			float tiles = step(0.5, fract(m.x / 2.0)) * 0.06;
			albedo *= 0.94 + tiles;
			vec2 vc = fract(m.xz / 7.0);
			float vent = box_mask(vc, vec2(0.22), vec2(0.02 + px / 7.0)) * step(0.55, h21(floor(m.xz / 7.0) + seed * 31.0));
			albedo = mix(albedo, vec3(0.55, 0.56, 0.57), vent * 0.8);
			if (kind == 2 && rh < 0.3 && sz.x > 12.0) {
				// сад на крыше: зелёные грядки с дорожками
				float bed = step(0.25, fract(m.x / 4.0)) * step(0.2, fract(m.z / 5.0));
				albedo = mix(albedo, vec3(0.13, 0.22, 0.07) * (0.8 + 0.4 * n), bed * step(2.0, e));
			} else if (kind == 1 && rh < 0.45) {
				// солнечные панели рядами
				vec2 pc = fract(m.xz / vec2(2.2, 3.0));
				float pan = step(0.08, pc.x) * step(pc.x, 0.92) * step(0.1, pc.y) * step(pc.y, 0.75) * step(2.0, e);
				albedo = mix(albedo, vec3(0.05, 0.08, 0.16), pan);
				rough = mix(rough, 0.25, pan);
				metal = mix(metal, 0.5, pan);
			} else if ((kind == 0 || kind == 3) && sz.y > 130.0 && min(sz.x, sz.z) > 18.0 && rh < 0.6) {
				// вертолётная площадка: круг и «H»
				vec2 q = m.xz - sz.xz * 0.5;
				float r = length(q);
				float ring = 1.0 - smoothstep(0.35, 0.35 + px, abs(r - 6.5));
				float hh = step(abs(q.x), 2.2) * step(abs(q.y), 3.0) * (step(1.6, abs(q.x)) + step(abs(q.y), 0.35));
				albedo = mix(albedo, vec3(0.22, 0.23, 0.24), step(r, 7.5));
				albedo = mix(albedo, vec3(0.85, 0.82, 0.3), clamp(ring + hh, 0.0, 1.0));
				emit += vec3(0.4, 1.0, 0.5) * step(abs(r - 7.3), 0.25) * step(0.5, fract(atan(q.y, q.x) * 2.546)) * night * 1.5;
			}
			// парапет: светлая кромка и тень за ней
			float lip = 1.0 - smoothstep(0.55, 0.55 + px, e);
			float shadow = 1.0 - smoothstep(0.55, 1.6, e);
			albedo *= mix(1.0, 0.6, shadow * (1.0 - lip));
			albedo = mix(albedo, kind <= 1 ? vec3(0.55, 0.55, 0.54) : wall * 0.95, lip);
		}
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
		float near = 1.0 - far;
		if (kind == 2 || kind == 6 || kind == 1) {
			// этажный карниз: светлая полка, под ней тень
			float ledge = (1.0 - smoothstep(0.07, 0.07 + fw.y, fr.y));
			float under = smoothstep(0.93 - fw.y, 0.97, fr.y) * (1.0 - smoothstep(0.985, 1.0, fr.y));
			vec3 trim = kind == 1 ? wall * 1.12 : mix(wall, vec3(0.86, 0.84, 0.80), 0.55);
			albedo = mix(albedo, trim, ledge * near * (in_grid ? 1.0 : 0.0));
			albedo *= 1.0 - under * 0.25 * near * (in_grid ? 1.0 : 0.0);
		}
		if (kind == 1 && in_grid) {
			// офис: вертикальные ламели между лентами окон
			float fin = 1.0 - smoothstep(0.035, 0.035 + fw.x, min(fr.x, 1.0 - fr.x));
			albedo = mix(albedo, wall * 1.15, fin * near);
		}
		if (kind == 2 || kind == 6) {
			// руст на углах кирпичных/оштукатуренных домов
			float edge = min(f.x, face_w - f.x);
			float quoin = step(edge, 0.9 + 0.5 * step(0.5, fract(f.y / 1.2))) * step(hb, 0.33);
			albedo = mix(albedo, vec3(0.78, 0.74, 0.66), quoin * near);
		}
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
			// цоколь и маркизы над витринами (днём)
			float plinth = 1.0 - smoothstep(0.75, 0.8 + fw.y, f.y);
			albedo = mix(albedo, wall * 0.55, plinth);
			float awn = step(ground - 1.35, f.y) * step(f.y, ground - 0.75) * step(0.35, fract(f.x / 6.0)) * step(0.45, sh);
			vec3 ac = hue(fract(sh * 5.0)) * 0.55 + 0.2;
			float stripes = step(0.5, fract(f.x / 0.8));
			albedo = mix(albedo, ac * mix(0.75, 1.0, stripes), awn * near);
		}
		// верхний карниз
		float cornice = step(top + 0.1, f.y) * step(f.y, top + 0.55);
		albedo = mix(albedo, kind == 0 || kind == 3 ? wall * 1.2 : mix(wall, vec3(0.85, 0.83, 0.78), 0.5), cornice * near);
		albedo *= 1.0 - step(top - 0.35, f.y) * step(f.y, top + 0.1) * 0.3 * near;
		// потёки под окнами и грязь у земли
		float streak = h21(vec2(floor(f.x * 1.3), seed * 7.0));
		albedo *= 1.0 - 0.09 * streak * smoothstep(0.3, 1.0, fract(v)) * near * (kind == 0 || kind == 3 ? 0.3 : 1.0);
		albedo *= mix(0.78, 1.0, smoothstep(0.0, 7.0, f.y));
		// стекло днём отражает небо
		vec3 gl = glass * (0.8 + 0.4 * h11(hw * 5.3));
		gl += sky_tint * 0.05 * (1.0 - night);
		// рама окна, импост (у жилых и с фрамугой) и подоконник
		float frame_k = 0.0;
		if (in_grid && kind != 0 && kind != 3) {
			vec2 fsz = kind == 1 ? vec2(0.06, 0.10) : vec2(0.10, 0.10);   // толщина рамы, м
			float inner = box_mask(fr, max(wsize - 2.0 * fsz / cell, vec2(0.0)), fw);
			float mull = (1.0 - smoothstep(0.025, 0.025 + fw.x, abs(fr.x - 0.5))) * (kind == 1 ? step(0.5, fract(ci.x * 0.5)) : 1.0);
			float transom = kind == 1 ? 0.0 : (1.0 - smoothstep(0.02, 0.02 + fw.y, abs(fr.y - (0.5 + wsize.y * 0.22))));
			frame_k = clamp(wm - inner + (mull + transom) * wm, 0.0, 1.0) * near;
			float sill_y = (1.0 - wsize.y) * 0.5;
			float sill = step(sill_y - 0.06, fr.y) * step(fr.y, sill_y) * step(abs(fr.x - 0.5), wsize.x * 0.5 + 0.06);
			albedo = mix(albedo, vec3(0.80, 0.78, 0.74), sill * near * (kind == 1 ? 0.0 : 0.9));
		}
		vec3 frame_col = kind == 1 ? vec3(0.22, 0.23, 0.25) : (h11(seed * 41.0) < 0.6 ? vec3(0.88, 0.87, 0.84) : vec3(0.32, 0.22, 0.15));
		gl = mix(gl, frame_col, frame_k);
		albedo = mix(albedo, gl, wm);
		rough = mix(rough, 0.12, wm);
		metal = mix(0.0, glass_metal, wm);
		emit += we * wm * (1.0 - frame_k * 0.85);
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
