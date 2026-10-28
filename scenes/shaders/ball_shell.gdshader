shader_type spatial;
// Оболочка сферы существа: лакированные пластины-лепестки с металлической окантовкой, швы со светом
// сердцевины, гравированная эмблема стихии на полюсах, кольцо цвета владельца на экваторе.
// Один материал на все шары: стихия, цвет владельца и состояние — instance uniform (без новых материалов).
// Меш — единичная сфера (BallShell): UV.x/UV.y — дуга (рад) до ближайшего края пластины по долготе/широте,
// UV2.x — вид части: 0 лепесток, 1 полярная крышка, 2 экваторный пояс.
render_mode cull_disabled;

instance uniform int element = 0;          // 0 Пламя, 1 Буря, 2 Свет, 3 Камень, 4 Тень, 5 Прилив
instance uniform vec4 owner_col : source_color = vec4(0.4, 0.6, 1.0, 1.0);
instance uniform float glow = 0.0;         // вспышка сердцевины (бросок, раскрытие)
instance uniform float crack = 0.0;        // нокаут: трещины 0..1
instance uniform float dim = 0.0;          // нокаут: сфера гаснет 0..1

const vec3 ELEM_COLS[6] = vec3[6](vec3(1.0, 0.42, 0.12), vec3(0.35, 0.95, 0.78), vec3(1.0, 0.85, 0.42),
	vec3(1.0, 0.62, 0.25), vec3(0.62, 0.32, 1.0), vec3(0.3, 0.68, 1.0));

varying vec3 opos;
varying vec3 oview;

void vertex() {
	opos = VERTEX;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	oview = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD - wp, 0.0)).xyz;
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.03 + 3.1) * 0.3 + vnoise(p * 4.1 + 7.7) * 0.15;
}

#include "res://scenes/shaders/sigils.gdshaderinc"

void fragment() {
	int el = clamp(element, 0, 5);
	vec3 ec = ELEM_COLS[el];
	vec3 p = normalize(opos);
	float lat = asin(clamp(p.y, -1.0, 1.0));
	float lon = atan(p.z, p.x);
	float part = UV2.x;
	float edge = min(UV.x, UV.y);
	float pulse = 0.5 + 0.5 * sin(TIME * 3.2 + float(el));
	float core_k = (1.0 + 0.45 * pulse + glow * 2.5) * (1.0 - dim);

	vec3 alb;
	float rough;
	float metal;
	vec3 emi = vec3(0.0);
	if (el == 0) { // Пламя: обожжённый лак с тлеющими трещинами
		float n = fbm(p * 3.5);
		float cr = 1.0 - smoothstep(0.0, 0.035, abs(n - 0.5));
		cr *= smoothstep(0.3, 0.6, fbm(p * 1.7 + 11.0));
		alb = mix(vec3(0.16, 0.035, 0.02), vec3(0.32, 0.08, 0.03), n);
		alb = mix(alb, vec3(1.0, 0.45, 0.1), cr * 0.6);
		rough = 0.32 - n * 0.1;
		metal = 0.15;
		emi = vec3(1.0, 0.38, 0.06) * cr * (1.4 + 0.8 * sin(TIME * 4.0 + n * 12.0));
	} else if (el == 1) { // Буря: бирюзовый металл со спиральными прожилками
		float n = fbm(p * 2.5);
		float s = sin(lon * 3.0 + lat * 7.0 + n * 3.0 - TIME * 1.6);
		float vein = smoothstep(0.93, 1.0, s);
		alb = mix(vec3(0.03, 0.2, 0.19), vec3(0.08, 0.36, 0.32), n);
		rough = 0.24;
		metal = 0.55;
		alb = mix(alb, vec3(0.7, 1.0, 0.95), vein * 0.5);
		emi = vec3(0.45, 1.0, 0.9) * vein * 1.3;
	} else if (el == 2) { // Свет: золото с лучами от полюсов
		float ray = smoothstep(0.9, 1.0, abs(cos(lon * 6.0)));
		float band = 0.5 + 0.5 * sin(abs(lat) * 18.0 - TIME * 3.0);
		alb = vec3(1.0, 0.74, 0.3);
		rough = mix(0.3, 0.5, ray);
		metal = 0.7;
		alb *= 1.0 - ray * 0.3;
		// тёмное небо почти не отражается: золото подсвечено изнутри, чтобы не чернело
		emi = vec3(0.55, 0.36, 0.1) * 0.35 + vec3(1.0, 0.85, 0.45) * ray * band * 0.9;
	} else if (el == 3) { // Камень: гранит с рунами
		float n = fbm(p * 9.0);
		float sp = step(0.8, vnoise(p * 40.0));
		float dk = step(0.78, vnoise(p * 33.0 + 5.0));
		alb = mix(vec3(0.2, 0.15, 0.11), vec3(0.42, 0.34, 0.26), n);
		alb = mix(alb, vec3(0.6, 0.57, 0.52), sp * 0.5);
		alb = mix(alb, vec3(0.1, 0.09, 0.08), dk * 0.6);
		rough = 0.78;
		metal = 0.0;
		// руны поясом на широте ~30°: по ячейке долготы — вертикальная черта и косые засечки
		float al = abs(lat);
		float cells = 7.0;
		float cu = lon / 6.28318 * cells;
		float cid = floor(cu);
		vec2 q = vec2(fract(cu) - 0.5, (al - 0.55) / 0.2);
		float h = hash3(vec3(cid, sign(lat), 3.0));
		float rune = smoothstep(0.07, 0.03, abs(q.x)) * step(abs(q.y), 0.45);
		rune = max(rune, smoothstep(0.06, 0.02, abs(q.y - q.x * (h > 0.5 ? 1.6 : -1.6) - (h - 0.5) * 0.5)) * step(abs(q.x), 0.28) * step(abs(q.y), 0.45));
		rune = max(rune, smoothstep(0.06, 0.02, abs(q.y + 0.25 - fract(h * 7.0) * 0.5)) * step(abs(q.x), 0.25));
		rune *= step(abs(q.y), 0.5) * step(0.5, part < 0.5 ? 1.0 : 0.0);
		alb = mix(alb, vec3(0.08, 0.05, 0.03), rune);
		emi = vec3(1.0, 0.55, 0.2) * rune * (1.4 + 1.0 * pulse);
	} else if (el == 4) { // Тень: тёмное стекло, внутри — фиолетовый дымок
		vec3 v = normalize(oview);
		float sm = 0.0;
		for (int k = 1; k <= 3; k++) {
			vec3 q = p - v * float(k) * 0.28;
			sm += fbm(q * 2.6 + vec3(0.0, TIME * 0.35, TIME * 0.2));
		}
		sm = smoothstep(1.2, 2.3, sm);
		alb = vec3(0.025, 0.015, 0.04);
		rough = 0.05;
		metal = 0.0;
		emi = vec3(0.55, 0.22, 1.0) * sm * 1.1;
	} else { // Прилив: перламутр с волнами
		float w = sin(lat * 14.0 + sin(lon * 3.0 + TIME * 0.8) * 1.4);
		float fres = 1.0 - abs(dot(NORMAL, VIEW));
		vec3 iri = 0.5 + 0.5 * cos(6.28318 * (vec3(0.0, 0.33, 0.67) + fres * 0.7 + w * 0.12));
		alb = mix(vec3(0.16, 0.42, 0.85), iri, 0.4 + 0.15 * w);
		rough = 0.16;
		metal = 0.35;
		emi = vec3(0.4, 0.75, 1.0) * smoothstep(0.85, 1.0, w) * 0.5;
	}

	// окантовка швов: металлическая рамка, у самого края — щель со светом сердцевины
	vec3 trim_c = (el == 0 || el == 2) ? vec3(0.95, 0.72, 0.36) : (el == 4 ? vec3(0.55, 0.45, 0.7) : vec3(0.78, 0.78, 0.8));
	float trim = 1.0 - smoothstep(0.045, 0.06, edge);
	float slit = 1.0 - smoothstep(0.0, 0.018, edge);
	if (part > 1.5) { // экваторный пояс: металл и полоска цвета владельца
		trim = 1.0;
		float stripe = 1.0 - smoothstep(0.012, 0.02, abs(p.y));
		alb = mix(trim_c * 0.8, owner_col.rgb, stripe);
		rough = mix(0.25, 0.35, stripe);
		metal = mix(1.0, 0.0, stripe);
		emi = owner_col.rgb * stripe * 1.6 * (1.0 - dim * 0.7);
		slit = 0.0;
	} else {
		alb = mix(alb, trim_c, trim);
		rough = mix(rough, 0.22, trim);
		metal = mix(metal, 1.0, trim);
		emi *= 1.0 - trim;
	}
	// гравированная эмблема на полюсе
	if (part > 0.5 && part < 1.5) {
		float m = sigil_mask(p.xz * 0.27, el);
		float halo = sigil_mask(p.xz * 0.24, el) - m;
		alb = mix(alb, alb * 0.25, m);
		rough = mix(rough, 0.6, m);
		emi += ec * m * 1.5 * core_k + ec * max(halo, 0.0) * 0.25 * core_k;
	}
	emi = emi * (1.0 - dim) + ec * slit * 1.8 * core_k;
	emi += ec * glow * 0.35 * (1.0 - trim);

	// нокаут: трещины светятся и гаснут
	if (crack > 0.0) {
		float n = fbm(p * 5.0 + 20.0);
		float cl = (1.0 - smoothstep(0.0, 0.02 + 0.03 * crack, abs(n - 0.5))) * step(fbm(p * 2.0 + 40.0), crack * 0.9);
		alb = mix(alb, vec3(0.02), cl);
		emi += mix(vec3(1.0), ec, dim) * cl * 2.5 * (1.0 - dim * 0.8);
	}
	alb *= 1.0 - dim * 0.65;

	if (!FRONT_FACING) { // изнанка раскрытых лепестков: светится сердцевиной
		alb = trim_c * 0.3;
		metal = 0.6;
		rough = 0.4;
		emi = ec * (0.9 + glow) * (1.0 - dim);
	}
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.6;
	EMISSION = emi;
}
