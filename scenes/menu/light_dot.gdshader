// Огоньки транспорта меню (самолёт, вертолёт, лодки): квад-билборд с мягкой точкой, аддитивно. Размер не меньше
// ~2 пикселей на любом расстоянии — огни видны издалека, как настоящие. MultiMesh, трансформы — MenuTraffic.
// INSTANCE_CUSTOM: rgb — цвет, a — режим: 0 горит, 1 строб (короткие вспышки), 2 маячок (мигает), 3 — скрыт.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float anim_t = 0.0;
uniform float night = 0.0;

varying flat vec4 cd;
varying flat float phase_k;

void vertex() {
	cd = INSTANCE_CUSTOM;
	vec3 wpos = MODEL_MATRIX[3].xyz;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float size = max(length(MODEL_MATRIX[0].xyz), dist * 0.0022);
	phase_k = fract(wpos.x * 0.013 + wpos.z * 0.007);
	if (cd.a > 2.5) {
		size = 0.0;
	}
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * size, INV_VIEW_MATRIX[1] * size, INV_VIEW_MATRIX[2] * size, vec4(wpos, 1.0));
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float core = smoothstep(0.45, 0.0, r);
	float halo = smoothstep(1.0, 0.0, r);
	float k = 1.0;
	if (cd.a > 0.5 && cd.a < 1.5) {
		k = step(0.9, fract(anim_t * 0.85 + phase_k)) * 2.0;
	} else if (cd.a > 1.5) {
		k = step(0.5, fract(anim_t * 0.7 + phase_k));
	}
	ALBEDO = cd.rgb * (core * 2.5 + halo * halo * 0.6) * k * mix(0.25, 1.0, night);
}
