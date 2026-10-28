shader_type spatial;
// Вспышки сферы: mode 0 — круглый ореол-билборд с лучами, mode 1 — кольцо (кольцо ускорения броска).
// Цвет и затухание — instance uniform: один общий материал на все вспышки.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

instance uniform vec4 col : source_color = vec4(1.0);
instance uniform float fade = 1.0;
instance uniform int mode = 0;

void vertex() {
	if (mode == 0) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	}
}

void fragment() {
	vec2 e = UV * 2.0 - 1.0;
	float r = length(e);
	float a;
	vec3 c;
	if (mode == 0) {
		float ang = atan(e.y, e.x);
		float rays = pow(abs(cos(ang * 3.0)), 24.0) * smoothstep(1.0, 0.1, r) * 0.7;
		float core = pow(max(0.0, 1.0 - r), 3.0);
		a = (core * 1.4 + rays) * fade;
		c = mix(col.rgb, vec3(1.0), core * 0.6);
	} else {
		a = smoothstep(0.08, 0.0, abs(r - 0.88)) * 1.2 + smoothstep(0.3, 0.0, abs(r - 0.75)) * 0.35;
		a *= fade;
		c = mix(col.rgb, vec3(1.0), 0.3);
	}
	ALBEDO = c * 1.5 * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
