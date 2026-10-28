shader_type spatial;
// Вспышка знака стихии на карте при приземлении/раскрытии: знак в круге, плоский квад на полу, аддитивно.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

instance uniform int element = 0;
instance uniform vec4 col : source_color = vec4(1.0);
instance uniform float fade = 1.0;

#include "res://scenes/shaders/sigils.gdshaderinc"

void fragment() {
	vec2 e = (UV - 0.5) * 0.36;  // круг радиуса 0.18, знак ~0.13
	float r = length(e);
	float m = sigil_mask(e, clamp(element, 0, 5));
	float rim = smoothstep(0.012, 0.0, abs(r - 0.165)) + smoothstep(0.006, 0.0, abs(r - 0.148)) * 0.6;
	float ticks = smoothstep(0.85, 1.0, abs(cos(atan(e.y, e.x) * 12.0))) * smoothstep(0.006, 0.0, abs(r - 0.156) - 0.006);
	float halo = smoothstep(0.18, 0.0, r) * 0.12;
	float a = (m + rim + ticks * 0.8 + halo) * fade;
	ALBEDO = mix(col.rgb, vec3(1.0), m * 0.25) * 1.1 * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
