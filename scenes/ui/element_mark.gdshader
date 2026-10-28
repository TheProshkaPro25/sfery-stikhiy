shader_type canvas_item;
// Значок стихии в интерфейсе: знак (как на картах) в светящемся кольце цвета стихии.

uniform int element = 0;
uniform vec4 col : source_color = vec4(1.0);
uniform float lit = 1.0;   // 0 — тусклый (не выбран), 1 — горит

#include "res://scenes/shaders/sigils.gdshaderinc"

void fragment() {
	vec2 e = (UV - 0.5) * 0.36;   // круг радиуса 0.18, знак ~0.13
	float r = length(e);
	float m = sigil_mask(e * 1.12, clamp(element, 0, 5));
	float disc = smoothstep(0.172, 0.165, r);
	float rim = smoothstep(0.012, 0.0, abs(r - 0.163));
	vec3 bg = mix(col.rgb * 0.18, col.rgb * 0.38, smoothstep(0.17, 0.0, r)) * (0.6 + 0.4 * lit);
	vec3 c = mix(bg, mix(col.rgb, vec3(1.0), 0.55 * lit), m);
	c = mix(c, col.rgb * (0.8 + 0.6 * lit), rim);
	COLOR = vec4(c, max(disc, rim) * COLOR.a);
}
