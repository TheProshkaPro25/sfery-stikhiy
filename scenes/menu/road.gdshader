// Дороги и мосты пейзажа меню (один MultiMesh из плоскостей 1×1): асфальт, разметка, бордюр. Фонари — оранжевые
// точки по краям и тёплые пятна на асфальте ночью. Машины — отдельные меши (MenuTraffic, vehicle.gdshader).
// INSTANCE_CUSTOM: x — длина, м; y — зерно; z — полос в одну сторону; w — скорость (множитель).
shader_type spatial;
render_mode diffuse_burley;

uniform float night = 0.0;
uniform float anim_t = 0.0;

varying flat vec4 cd;
varying float width;

float h21(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }

void vertex() {
	cd = INSTANCE_CUSTOM;
	width = length(MODEL_MATRIX[2].xyz);
}

void fragment() {
	float L = cd.x;
	float seed = cd.y;
	float lanes = max(cd.z, 1.0);
	float s = UV.x * L;                 // вдоль дороги, м
	float w = (UV.y - 0.5) * width;     // поперёк, м (знак — направление)
	float aw = abs(w);
	float half_w = width * 0.5;
	vec2 fw = fwidth(vec2(s, w));
	float pix = max(fw.y, 0.02);

	vec3 asphalt = vec3(0.055, 0.056, 0.06) * (0.9 + 0.2 * h21(floor(vec2(s, w) * 0.5)));
	vec3 albedo = asphalt;
	vec3 emit = vec3(0.0);
	// разметка: двойная осевая и прерывистые между полосами
	float lane_w = (half_w - 0.6) / lanes;
	float axis = 1.0 - smoothstep(0.08, 0.08 + pix, abs(aw - 0.18));
	float dash = 0.0;
	if (lanes > 1.5) {
		float lx = abs(aw - 0.3 - lane_w);
		dash = (1.0 - smoothstep(0.07, 0.07 + pix, lx)) * step(0.5, fract(s / 9.0));
	}
	vec3 mark = vec3(0.75, 0.72, 0.6);
	albedo = mix(albedo, mark, clamp(axis + dash, 0.0, 1.0) * 0.8);
	// бордюр
	float curb = smoothstep(half_w - 0.35 - pix, half_w - 0.35, aw);
	albedo = mix(albedo, vec3(0.32), curb);

	// фонари по обочинам: точки и тёплые пятна
	float lamp_s = fract(s / 26.0 + seed) * 26.0;
	float ld = length(vec2(min(lamp_s, 26.0 - lamp_s), aw - (half_w - 0.4)));
	float lamp = 1.0 - smoothstep(0.35, 0.35 + max(fw.x, fw.y) * 1.5, ld);
	float pool = exp(-ld * ld / 30.0);
	vec3 sodium = vec3(1.0, 0.62, 0.28);
	emit += sodium * (lamp * 4.0 + pool * 0.10) * night;

	ALBEDO = albedo;
	ROUGHNESS = 0.8;
	EMISSION = emit;
}
