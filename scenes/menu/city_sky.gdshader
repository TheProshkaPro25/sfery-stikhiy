// Небо пейзажа меню: градиент по времени суток, свечение у солнца, диск солнца и луны, звёзды,
// плывущие облака (шум на плоскости) с подсветкой закатом, лунным краем и отсветом города снизу.
// Все цвета и направления задаёт menu_city.gd по DayCycle. Карта отражений (AT_CUBEMAP_PASS) — упрощённо.
shader_type sky;

uniform vec3 zenith_col : source_color = vec3(0.2, 0.4, 0.8);
uniform vec3 horizon_col : source_color = vec3(0.7, 0.8, 0.9);
uniform vec3 glow_col : source_color = vec3(1.0, 0.8, 0.6);
uniform vec3 sun_col : source_color = vec3(1.0, 0.95, 0.9);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float night = 0.0;
uniform float day = 1.0;
uniform float anim_t = 0.0;
uniform float cover = 0.5;
uniform float detail = 1.0;   // 0 — «Низкие»: меньше октав, без самозатенения облаков

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p, int oct) {
	float s = 0.0;
	float a = 0.5;
	mat2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < oct; i++) {
		s += a * vnoise(p);
		p = r * p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float y = d.y;
	vec3 sdir = normalize(sun_dir);
	vec3 mdir = normalize(moon_dir);
	float yh = max(y, 0.0);

	// градиент: горизонт → зенит
	vec3 col = mix(horizon_col, zenith_col, pow(yh, 0.42));
	float sd = max(dot(d, sdir), 0.0);
	float md = max(dot(d, mdir), 0.0);
	// заря: широкое свечение у горизонта со стороны солнца, пока солнце низко
	float low_sun = smoothstep(-0.28, 0.02, sdir.y) * (1.0 - smoothstep(0.18, 0.55, sdir.y));
	float band = exp(-yh * 4.5);
	col += glow_col * (pow(sd, 5.0) * band * 0.85 + pow(sd, 1.5) * band * 0.18) * low_sun;
	// ореол солнца днём
	col += sun_col * pow(sd, 60.0) * 0.6 * smoothstep(-0.05, 0.05, sdir.y);
	// отсвет города у горизонта ночью (засветка)
	col += vec3(1.0, 0.52, 0.26) * night * exp(-yh * 16.0) * 0.07;
	// ореол луны
	col += vec3(0.55, 0.65, 0.9) * pow(md, 90.0) * 0.18 * night;
	// под горизонтом — темнее (почти не видно за землёй)
	if (y < 0.0) {
		col = mix(horizon_col * 0.85, horizon_col * 0.35, clamp(-y * 5.0, 0.0, 1.0));
	}

	if (!AT_CUBEMAP_PASS) {
		// звёзды: точки на сетке по направлению
		if (night > 0.02 && y > 0.0) {
			vec3 g = d * 260.0;
			vec3 cell = floor(g);
			float hs = hash13(cell);
			if (hs > 0.972) {
				vec3 pos = vec3(hash13(cell + 1.3), hash13(cell + 7.1), hash13(cell + 3.7)) * 0.7 + 0.15;
				float dist = length(fract(g) - pos);
				float br = pow(hash13(cell + 11.0), 3.0) * 2.2 + 0.25;
				float tw = 0.75 + 0.25 * sin(anim_t * (2.0 + hs * 9.0) + hs * 80.0);
				vec3 sc = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.85, 0.7), hash13(cell + 5.0));
				col += sc * smoothstep(0.38, 0.0, dist) * br * tw * night * smoothstep(0.0, 0.18, y);
			}
		}
		// солнце
		float disc = smoothstep(0.99955, 0.99975, dot(d, sdir));
		col += sun_col * disc * 24.0 * smoothstep(-0.02, 0.01, sdir.y);
		// луна с пятнами
		float mdot = dot(d, mdir);
		if (mdot > 0.9997) {
			float edge = smoothstep(0.99974, 0.99982, mdot);
			vec2 mp = (d - mdir * mdot).xy * 900.0;
			float spots = vnoise(mp * 0.9) * 0.5 + vnoise(mp * 2.3) * 0.25;
			col = mix(col, vec3(0.95, 0.96, 1.0) * (1.6 - spots) * (0.35 + night * 1.2), edge * smoothstep(-0.02, 0.03, mdir.y));
		}
	}

	// облака: проекция на плоскость, ветер сдвигает шум
	if (y > 0.0) {
		vec2 uv = d.xz / (y + 0.10) * 1.15;
		vec2 wind = vec2(anim_t * 0.010, anim_t * 0.0035);
		int oct = AT_CUBEMAP_PASS ? 3 : (detail > 0.5 ? 6 : 4);
		float n = fbm(uv + wind, oct);
		// перистые полосы выше и медленнее
		float ci = fbm(uv * vec2(0.35, 2.4) + wind * 0.6 + 4.0, AT_CUBEMAP_PASS ? 2 : 3);
		float thr = 1.0 - cover;
		float c = smoothstep(thr - 0.02, thr + 0.32, n);
		float cir = smoothstep(0.55, 0.85, ci) * 0.35 * (1.0 - c);
		float fade = smoothstep(0.0, 0.16, y);
		c *= fade;
		cir *= fade;
		// самозатенение: плотность в сторону источника света
		vec3 ldir = sdir.y > -0.12 ? sdir : mdir;
		float lit = 0.65;
		if (!AT_CUBEMAP_PASS && detail > 0.5) {
			float n2 = fbm(uv + wind + normalize(ldir.xz + vec2(1e-4)) * 0.09, 4);
			lit = clamp(0.62 + (n - n2) * 3.2, 0.0, 1.0);
		}
		// освещение облаков: днём белое, на закате — цвет зари, ночью — луна и город снизу
		vec3 day_lit = mix(sun_col, vec3(1.0), 0.45) * 1.05;
		vec3 dusk_lit = mix(glow_col, sun_col, 0.3) * 1.2;
		vec3 light_c = mix(dusk_lit, day_lit, smoothstep(0.08, 0.4, sdir.y));
		light_c = mix(light_c, vec3(0.13, 0.15, 0.22), night);
		vec3 shade_c = mix(horizon_col, zenith_col, 0.55) * mix(0.75, 0.6, night);
		shade_c += vec3(0.55, 0.30, 0.16) * night * 0.10;  // снизу подсвечены городом
		vec3 cc = mix(shade_c, light_c, lit);
		// серебристый край у солнца/луны
		float edge = c * (1.0 - c) * 4.0;
		cc += sun_col * edge * pow(sd, 6.0) * 1.2 * smoothstep(-0.05, 0.1, sdir.y);
		cc += vec3(0.7, 0.8, 1.0) * edge * pow(md, 10.0) * 0.8 * night;
		col = mix(col, cc, c * 0.96);
		col = mix(col, mix(col, light_c * 1.1, 0.8), cir);
	}
	COLOR = col;
}
