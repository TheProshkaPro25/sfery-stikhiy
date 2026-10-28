shader_type spatial;
// Сердцевина сферы: светящийся шар цвета стихии под пластинами (виден в швах и при раскрытии), пульсирует.
render_mode unshaded, shadows_disabled;

instance uniform vec4 col : source_color = vec4(1.0, 0.6, 0.2, 1.0);
instance uniform float glow = 0.0;
instance uniform float dim = 0.0;

varying vec3 opos;

void vertex() {
	opos = VERTEX;
}

void fragment() {
	float fres = abs(dot(NORMAL, VIEW));
	float sw = sin(atan(opos.z, opos.x) * 3.0 + opos.y * 6.0 - TIME * 4.0) * 0.5 + 0.5;
	float pulse = 0.5 + 0.5 * sin(TIME * 3.2);
	float k = (1.1 + 0.5 * pulse + glow * 2.0) * (1.0 - dim);
	ALBEDO = mix(col.rgb, vec3(1.0), 0.35 * fres + 0.15 * sw) * k * (0.7 + 0.5 * fres);
}
