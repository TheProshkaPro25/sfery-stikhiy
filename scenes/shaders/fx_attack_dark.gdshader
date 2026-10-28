shader_type spatial;
// Тёмные эффекты удара (AttackFx, Тень): щупальца и разрыв. Обычное смешивание: тьма закрывает свет,
// по краю — фиолетовое свечение, по телу ползут прожилки. col — цвет свечения, fade — общая прозрачность.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

instance uniform vec4 col : source_color = vec4(0.62, 0.32, 1.0, 1.0);
instance uniform float fade = 1.0;
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

void fragment() {
	float t = TIME + seed * 5.0;
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	float vein = smoothstep(0.62, 0.8, vnoise(vec2(UV.x * 8.0, UV.y * 10.0 - t * 2.5)));
	vec3 dark = vec3(0.03, 0.01, 0.06);
	ALBEDO = mix(dark, col.rgb * 1.8, clamp(fres * 0.85 + vein * 0.6, 0.0, 1.0));
	ALPHA = clamp((0.82 + fres * 0.18) * fade, 0.0, 1.0);
}
