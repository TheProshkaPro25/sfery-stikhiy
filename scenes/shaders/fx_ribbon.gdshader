shader_type spatial;
// Лента следа летящей сферы: UV.x — 0 у шара, 1 у хвоста; UV.y — поперёк ленты. Цвет и прозрачность — COLOR.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

void fragment() {
	float across = 1.0 - abs(UV.y * 2.0 - 1.0);
	float core = pow(across, 3.0);
	float t = UV.x;
	float streak = 0.75 + 0.25 * sin(t * 40.0 - TIME * 30.0);
	float a = COLOR.a * pow(1.0 - t, 1.6) * (across * 0.6 + core * 0.8) * streak;
	ALBEDO = mix(COLOR.rgb, vec3(1.0), core * (1.0 - t) * 0.6) * 1.2 * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
