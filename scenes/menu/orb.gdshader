// Шар стихии в полуночном небе меню (MenuOrbs): квад-билборд, аддитивно. Ядро — светящийся «шар» с объёмом
// (ярче к центру, обод, медленные завихрения), вокруг — ореол и тонкие лучи. Без геометрии сферы и источников света.
// INSTANCE_CUSTOM: rgb — цвет стихии, a — яркость 0..1 (появление/вспышка/угасание).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float anim_t = 0.0;
const float HALO = 4.0;   // половина квада — в радиусах шара

varying flat vec4 cd;
varying flat float seed;

void vertex() {
	cd = INSTANCE_CUSTOM;
	vec3 wpos = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz) * HALO;
	seed = fract(wpos.x * 0.0137);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * size, INV_VIEW_MATRIX[1] * size, INV_VIEW_MATRIX[2] * size, vec4(wpos, 1.0));
}

void fragment() {
	vec2 q = (UV * 2.0 - 1.0) * HALO;       // в радиусах шара
	float r = length(q);
	float ang = atan(q.y, q.x);
	vec3 c = cd.rgb;
	vec3 hot = mix(c, vec3(1.0), 0.3);
	float t = anim_t * 0.6 + seed * 10.0;
	vec3 col = vec3(0.0);
	if (r < 1.0) {
		float z = sqrt(1.0 - r * r);       // «объём»: нормаль сферы
		float swirl = sin(ang * 3.0 + r * 5.0 - t * 2.0) * 0.5 + 0.5;
		swirl *= sin(ang * 2.0 - r * 3.0 + t * 1.3) * 0.5 + 0.5;
		float rim = pow(1.0 - z, 3.0);
		col = mix(c * 0.9, hot * 1.7, z * z) + c * swirl * 0.8 * z + hot * rim * 1.6;
		col *= smoothstep(1.0, 0.94, r);
	}
	float edge = smoothstep(0.9, 1.05, r);
	float halo = exp(-(r - 1.0) * 2.2) * 0.7 + exp(-r * r * 0.15) * 0.2;
	float rays = pow(abs(sin(ang * 4.0 + t * 0.35)), 24.0) * exp(-r * 0.9) * 0.35;
	rays += pow(abs(sin(ang * 3.0 - t * 0.5 + 1.0)), 30.0) * exp(-r * 1.1) * 0.2;
	col += c * (halo + rays) * edge;
	col *= smoothstep(HALO, HALO * 0.7, r);
	ALBEDO = col * cd.a;
}
