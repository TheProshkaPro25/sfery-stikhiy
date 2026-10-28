// Вода пейзажа меню: волны (сумма синусоид → нормаль), небо отражается картой отражений окружения,
// солнце и луна — бликами направленного света. Отражения огней города — дешёвая подделка без SSR:
// дрожащие столбики света вдоль линий «огонь → камера» (как на воде ночью), гуще напротив набережной.
// След лодок (MenuTraffic): клин Кельвина от носа и пенная дорожка за кормой — по массиву boats.
// Шары стихий в полночь (MenuOrbs) — цветные дрожащие дорожки на воде под шарами (6 сравнений на пиксель).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform float night = 0.0;
uniform float win_on = 0.0;
uniform float anim_t = 0.0;
uniform vec3 deep_col : source_color = vec3(0.02, 0.05, 0.07);
uniform vec3 cam_ground = vec3(0.0, 0.0, 300.0);   // камера на плоскости воды
uniform float shore_z = 20.0;                      // дальняя набережная (город)
uniform vec2 bridges = vec2(-150.0, 120.0);        // x мостов
uniform vec4 boats[16];                            // x, z, скорость по x (знак — направление), полудлина
uniform int boat_n = 0;
uniform float orbs_on = 0.0;
uniform vec4 orbs[6];                              // центр шара, яркость
uniform vec3 orb_cols[6];

varying vec3 wp;

float h11(float p) { p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz;
	float t = anim_t;
	// волны: несколько направлений, производные по x/z
	vec2 g = vec2(0.0);
	vec4 dirs[8] = vec4[](vec4(0.21, 0.62, 1.4, 1.0), vec4(-0.55, 0.40, 1.9, 0.6), vec4(0.95, -0.28, 2.5, 0.35), vec4(-1.6, -1.2, 3.4, 0.2),
		vec4(0.13, 1.07, 1.1, 0.5), vec4(-1.21, 0.33, 2.2, 0.3), vec4(2.3, 0.9, 3.9, 0.12), vec4(-0.4, -2.7, 4.4, 0.1));
	for (int i = 0; i < 8; i++) {
		vec2 dd = dirs[i].xy;
		float ph = dot(p, dd) + t * dirs[i].z;
		g += dd * cos(ph) * dirs[i].w;
	}
	float dist = length(wp.xz - cam_ground.xz);
	g *= 0.028 * (1.0 - smoothstep(150.0, 900.0, dist) * 0.6);
	// след лодок
	float foam = 0.0;
	for (int i = 0; i < 16; i++) {
		if (i >= boat_n) break;
		vec4 b = boats[i];
		float along = (p.x - b.x) * sign(b.z);
		float across = p.y - b.y;
		float d = b.w - along;                  // позади носа, м
		if (d < -1.0 || d > 240.0 || abs(across) > 90.0) continue;
		float spd = abs(b.z);
		float hw = b.w * 0.17;
		float k = clamp(spd / 8.0, 0.35, 1.0);
		float arm_w = 0.35 + d * 0.02;
		float arm = exp(-pow((abs(across) - hw - d * 0.34) / arm_w, 2.0)) * exp(-d / (spd * 7.0 + 12.0));
		float ds = d - 2.0 * b.w;               // позади кормы
		float trail = ds > -b.w ? exp(-pow(across / (hw * 0.9 + max(ds, 0.0) * 0.025), 2.0)) * exp(-max(ds, 0.0) / (spd * 9.0 + 18.0)) : 0.0;
		float ripple = sin(abs(across) * 1.7 - d * 0.9 - t * 4.0) * 0.5 + 0.5;
		foam += (arm * (0.4 + 0.6 * ripple) * 0.8 + trail * (0.5 + 0.5 * ripple)) * k;
		g += vec2(0.0, sign(across)) * arm * 0.05 * ripple;
	}
	foam = clamp(foam, 0.0, 1.0);
	vec3 n = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	ALBEDO = mix(deep_col, vec3(0.62, 0.66, 0.68), foam * 0.75);
	ROUGHNESS = mix(0.05, 0.35, foam);
	METALLIC = 0.0;
	SPECULAR = 0.55;

	// отражения огней: координата — тангенс угла от камеры (столбики сходятся к камере)
	float dz = max(cam_ground.z - wp.z, 1.0);
	float a = (wp.x - cam_ground.x) / dz;
	float wob = sin(wp.z * 0.9 + t * 2.0 + sin(wp.x * 0.3) * 2.0) * 0.5 + sin(wp.z * 2.3 - t * 3.1) * 0.3;
	float col_id = floor(a * 160.0 + wob * 0.35);
	float hc = h11(col_id * 1.37 + 0.5);
	// какие «окна» горят на той стороне: та же логика порога, что у зданий
	float lit = step(hc, win_on * 0.9) * step(abs(wp.x), 900.0);
	float near_shore = 1.0 - smoothstep(0.0, 90.0, wp.z - shore_z);    // столбик тянется от берега к нам
	float breakup = smoothstep(0.1, 0.7, sin(wp.z * 1.7 + wob * 3.0 + hc * 20.0) * 0.5 + 0.5);
	vec3 lc = mix(vec3(1.0, 0.68, 0.38), vec3(0.75, 0.85, 1.0), step(0.7, h11(col_id * 3.1)));
	vec3 emit = lc * lit * near_shore * breakup * 0.55 * night;
	// огни мостов — яркие оранжевые дорожки
	for (int b = 0; b < 2; b++) {
		float bx = b == 0 ? bridges.x : bridges.y;
		float ab = (bx - cam_ground.x) / dz;
		float db = abs(a - ab) * dz;          // метров в сторону от линии моста
		float lane = exp(-db * db / 60.0) * (0.6 + 0.4 * breakup);
		emit += vec3(1.0, 0.6, 0.3) * lane * 0.35 * night;
	}
	// отражения шаров стихий: дрожащие цветные дорожки на воде под каждым шаром (как дорожки огней мостов;
	// честное зеркальное отражение из этой камеры ушло бы ниже реки)
	if (orbs_on > 0.001) {
		for (int i = 0; i < 6; i++) {
			vec4 o = orbs[i];
			if (o.w < 0.001) continue;
			float ao = (o.x - cam_ground.x) / max(cam_ground.z - o.z, 1.0);
			float db = abs(a - ao) * dz;
			float w = 2.5 + 0.03 * dz;
			float lane = exp(-db * db / (w * w)) * (0.35 + 0.65 * breakup);
			float along = smoothstep(0.0, 25.0, wp.z - shore_z) * (1.0 - smoothstep(60.0, 110.0, wp.z - shore_z));
			emit += orb_cols[i] * o.w * lane * along * 0.9 * orbs_on;
		}
	}
	EMISSION = emit;
}
