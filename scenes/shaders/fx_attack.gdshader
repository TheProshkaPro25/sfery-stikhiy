shader_type spatial;
// Эффекты удара (AttackFx): один общий аддитивный материал, вид — instance uniform mode.
// mode 0 — пламя (рваные языки вверх по цилиндру/конусу), 1 — ветер (косые режущие полосы),
// 2 — луч/копьё света (яркая сердцевина, мерцание), 3 — вода (пена и струи), 4 — серп/когти (квад),
// 5 — шар-взрыв (сфера: ореол по краю и шум). UV.x — по окружности, UV.y — 0 верх, 1 низ (меши Godot).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

instance uniform vec4 col : source_color = vec4(1.0);
instance uniform float fade = 1.0;
instance uniform int mode = 0;
instance uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.6 + vnoise(p * 2.1 + 3.7) * 0.3 + vnoise(p * 4.3 + 9.1) * 0.1;
}

void fragment() {
	float t = TIME + seed * 7.0;
	vec2 uv = UV;
	float h = 1.0 - uv.y;  // 0 низ, 1 верх
	float a = 0.0;
	vec3 c = col.rgb;
	if (mode == 0) {
		// пламя: шум уходит вверх и закручивается, верх рвётся языками
		float n = fbm(vec2(uv.x * 7.0 + h * 2.5 + t * 0.8, h * 3.0 - t * 4.0));
		float tongue = smoothstep(h * 1.1 - 0.15, h * 1.1 + 0.2, n);
		a = tongue * smoothstep(0.0, 0.12, h);
		c = mix(vec3(1.0, 0.95, 0.7), col.rgb, smoothstep(0.1, 0.7, h)) * (1.2 + 1.4 * n);
	} else if (mode == 1) {
		// ветер: косые тонкие полосы бегут по кругу
		float s = fract(uv.x * 6.0 + h * 2.2 - t * 2.6 + vnoise(vec2(h * 5.0, t)) * 0.3);
		float band = smoothstep(0.0, 0.05, s) * smoothstep(0.22, 0.05, s);
		a = band * sin(h * 3.14159) * 1.3;
		c = mix(col.rgb, vec3(1.0), 0.45) * 1.6;
	} else if (mode == 2) {
		// луч: края по окружности мягкие, сердцевина белая, мерцает по длине
		float edge = pow(abs(sin(uv.x * 3.14159)), 2.0);
		float flick = 0.75 + 0.25 * vnoise(vec2(h * 12.0 - t * 18.0, seed));
		a = edge * flick * smoothstep(0.0, 0.08, h) * smoothstep(1.0, 0.85, h);
		c = mix(col.rgb, vec3(1.0), edge * 0.7) * 2.2;
	} else if (mode == 3) {
		// вода: тёмная толща со светлой пеной, струи бегут вверх
		float n = fbm(vec2(uv.x * 9.0, h * 4.0 - t * 3.0));
		float foam = smoothstep(0.55, 0.8, n);
		a = (0.35 + foam * 0.9) * smoothstep(0.0, 0.1, h) * smoothstep(1.0, 0.75, h + n * 0.2);
		c = mix(col.rgb * 0.8, vec3(0.9, 0.97, 1.0), foam) * 1.4;
	} else if (mode == 4) {
		// серп: дуга между двумя смещёнными окружностями, острые концы
		vec2 e = uv * 2.0 - 1.0;
		float r1 = length(e);
		float r2 = length(e - vec2(0.0, 0.32));
		float cres = smoothstep(0.98, 0.9, r1) * smoothstep(0.78, 0.9, r2);
		float core = smoothstep(0.96, 0.92, r1) * smoothstep(0.84, 0.9, r2);
		a = cres * smoothstep(-0.2, 0.4, e.y);
		c = mix(col.rgb, vec3(1.0), core) * 2.0;
	} else {
		// шар: яркий край (френель) и рваный шум
		float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 1.6);
		float n = fbm(uv * vec2(10.0, 6.0) + vec2(t * 0.6, -t * 1.5));
		a = (fres * 1.1 + n * 0.45) * (0.6 + n * 0.6);
		c = mix(vec3(1.0, 0.95, 0.8), col.rgb, fres) * (1.3 + n);
	}
	a *= fade;
	ALBEDO = c * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
