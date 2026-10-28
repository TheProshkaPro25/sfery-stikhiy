// Земля пейзажа меню: город (асфальт/бетон кварталов), трава и лес на холмах, скалы на склонах, песок у воды.
// Ночью город слегка подсвечен снизу (засветка), без источников света.
shader_type spatial;
render_mode diffuse_burley;

uniform float night = 0.0;
uniform vec4 city = vec4(60.0, -380.0, 820.0, 520.0);   // центр xz и полуоси города

varying vec3 wp;
varying vec3 wn;

float h21(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = NORMAL;
}

void fragment() {
	float n = vn(wp.xz * 0.02) * 0.6 + vn(wp.xz * 0.11) * 0.4;
	vec3 grass = mix(vec3(0.10, 0.15, 0.06), vec3(0.17, 0.21, 0.09), n);
	vec3 forest = vec3(0.07, 0.12, 0.07);
	vec3 rock = mix(vec3(0.30, 0.28, 0.26), vec3(0.42, 0.40, 0.37), n);
	vec3 col = mix(grass, forest, smoothstep(0.45, 0.65, vn(wp.xz * 0.008 + 3.0)));
	float slope = 1.0 - clamp(wn.y, 0.0, 1.0);
	col = mix(col, rock, smoothstep(0.25, 0.5, slope));
	col = mix(col, vec3(0.45, 0.42, 0.35), 1.0 - smoothstep(0.4, 2.2, wp.y));   // берег
	// город: кварталы бетона, иногда парки
	vec2 cq = (wp.xz - city.xy) / city.zw;
	float urban = 1.0 - smoothstep(0.85, 1.05, length(cq));
	vec3 conc = mix(vec3(0.20, 0.20, 0.21), vec3(0.30, 0.29, 0.28), h21(floor(wp.xz / 9.0)));
	float park = step(0.86, h21(floor(wp.xz / 70.0) + 5.0));
	col = mix(col, mix(conc, grass * 0.9, park), urban);
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
	EMISSION = vec3(1.0, 0.55, 0.28) * urban * (1.0 - park) * night * 0.035;
}
