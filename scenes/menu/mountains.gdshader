// Дальние горы — силуэты слоями: чем дальше слой (COLOR.r 0..1), тем ближе к цвету горизонта.
// Освещённая сторона хребта (COLOR.g — наклон к солнцу) теплее, на дальнем слое днём — снег.
shader_type spatial;
render_mode unshaded, fog_disabled;

uniform vec3 horizon_col : source_color = vec3(0.7, 0.8, 0.9);
uniform vec3 zenith_col : source_color = vec3(0.2, 0.4, 0.8);
uniform vec3 light_col : source_color = vec3(1.0);
uniform float day = 1.0;
uniform float night = 0.0;

varying float layer;
varying float h01;
varying vec3 wp;

void vertex() {
	layer = COLOR.r;
	h01 = COLOR.b;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = mix(vec3(0.10, 0.13, 0.16), vec3(0.20, 0.24, 0.30), day);
	base = mix(base, vec3(0.012, 0.016, 0.03), night);
	float haze = mix(0.25, 0.78, layer);
	vec3 col = mix(base, horizon_col, haze);
	// верх хребта чуть светлее (свет неба), снег на дальних вершинах днём
	col += light_col * smoothstep(0.55, 1.0, h01) * 0.10 * day * (1.0 - layer * 0.5);
	float snow = smoothstep(0.78, 0.92, h01) * step(0.5, layer);
	col = mix(col, mix(horizon_col, vec3(0.95, 0.96, 1.0), 0.6) * mix(1.0, 0.35, night), snow * mix(0.65, 0.25, night));
	// дымка у подножия
	col = mix(col, horizon_col, (1.0 - smoothstep(0.0, 0.35, h01)) * 0.5);
	ALBEDO = col;
}
