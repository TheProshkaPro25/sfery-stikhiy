shader_type spatial;
// Лицо карты ворот на арене (ArenaCardNode): тот же облик, что у 2D-карт (card_face.gdshaderinc),
// плюс освещение сцены (металл рамки отражает свет) и вспышка при раскрытии. Рубашка — frame = 9.

#include "res://scenes/shaders/card_face.gdshaderinc"

uniform vec4 flash_col : source_color = vec4(1.0, 0.85, 0.4, 1.0);
uniform float flash = 0.0;
uniform float self_light = 0.14; // собственная подсветка лица, чтобы карта читалась и в тени существа

void fragment() {
	vec2 p = UV * vec2(1.0, aspect);
	// с наклонной камеры шаг пикселя по p.y больше — сглаживаем по большему из двух
	float aa = max(fwidth(p.x), fwidth(p.y)) * 0.6 + 0.0004;
	vec3 col;
	vec3 em;
	float metal;
	float alpha;
	float osd;
	card_face(p, aa, TIME, col, em, metal, alpha, osd);
	float r = length(p - vec2(0.5, aspect * 0.5));
	float fl = flash * (0.5 + 0.8 * smoothstep(0.9, 0.0, r));
	// основа — тёмная (свет сцены её не «выбеливает»), металл рамки — как есть
	ALBEDO = col * mix(0.3, 1.0, metal);
	EMISSION = em * 0.7 + col * self_light * (1.0 - metal * 0.5) + flash_col.rgb * fl * 2.2;
	METALLIC = metal * 0.65;
	ROUGHNESS = mix(0.9, 0.32, metal);
	SPECULAR = mix(0.12, 0.5, metal);
}
