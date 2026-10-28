shader_type canvas_item;
// 2D-карта интерфейса (CardView): облик из card_face.gdshaderinc + ховер, выбор, затемнение.
// Прямоугольник шире карты на margin с каждой стороны — там рисуется ореол выбранной/наведённой карты.

#include "res://scenes/shaders/card_face.gdshaderinc"

uniform float hover = 0.0;
uniform float selected = 0.0;
uniform float dim = 0.0;
uniform float margin = 0.0; // поля под ореол, в долях ширины карты

void fragment() {
	vec2 full = vec2(1.0 + 2.0 * margin, aspect + 2.0 * margin);
	vec2 p = UV * full - vec2(margin);
	float aa = fwidth(p.x) * 0.7;
	vec3 col;
	vec3 em;
	float metal;
	float alpha;
	float osd;
	card_face(p, aa, TIME, col, em, metal, alpha, osd);
	float lift = clamp(hover * 0.6 + selected, 0.0, 1.0);
	// перелив: светлая полоса скользит по металлу и кромкам при наведении/выборе
	float sweep = fract(TIME * 0.32) * 2.2 - 0.6;
	float diag = (p.x * 0.8 + p.y * 0.45) / (0.8 + aspect * 0.45);
	float shine = smoothstep(0.09, 0.0, abs(diag - sweep));
	vec3 c = col + em;
	c += mix(vec3(1.0), glow.rgb, 0.4) * shine * lift * (0.05 + metal * 0.4);
	// мягкий свет кромки
	float d = -osd;
	c += glow.rgb * smoothstep(0.05, 0.0, d) * step(0.0, d) * (hover * 0.35 + selected * 0.55);
	c += glow.rgb * em * 0.25 * lift;
	// тонирование «света» без пересвета: мягкое насыщение ярких мест
	c = c / (1.0 + max(max(c.r, c.g), c.b) * 0.18);
	c *= 1.12;
	// затемнение недоступной карты
	float grey = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(c, vec3(grey) * 0.45, dim);
	// ореол снаружи карты
	float outside = max(osd, 0.0);
	float aura = exp(-outside / 0.022) * (1.0 - alpha) * step(0.0, osd) * (hover * 0.4 + selected * 0.85) * (1.0 - dim);
	vec3 out_c = mix(glow.rgb * 1.2, c, alpha);
	COLOR = vec4(out_c, max(alpha, aura * 0.9));
}
