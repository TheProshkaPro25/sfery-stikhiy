// Транспорт пейзажа меню (MenuTraffic): машины, вагоны метро, лодки, самолёт, вертолёт — низкополигональные меши
// с плоскими гранями. Часть меша — в цвете вершины: COLOR.r * 10 = 0 краска, 1 стекло/окна, 2 фары, 3 стоп-сигналы,
// 4 тёмное (шины, днище), 5 светлое (корпус, крыша), 6 тёмный металл, 7 палуба.
// road_anim = true (машины): машина едет по своей полосе прямо в вершинном шейдере — CPU их не трогает.
//   INSTANCE_CUSTOM: x — длина полосы, м; y — скорость, м/с; z — начальная доля пути; w — зерно (цвет, присутствие).
//   Трансформ инстанса — начало полосы, ось X по ходу движения, масштаб — тип (легковая/фургон/автобус).
// road_anim = false (поезда, лодки, воздух — трансформы обновляет CPU):
//   INSTANCE_CUSTOM: x — зерно цвета, y — маска огней (1 фары, 2 хвост), z — доля горящих окон, w — 1 краска из палитры.
shader_type spatial;
render_mode diffuse_burley;

uniform bool road_anim = false;
uniform float traffic = 0.6;
uniform float night = 0.0;
uniform float anim_t = 0.0;
uniform vec3 base_paint : source_color = vec3(0.85);

varying flat float part;
varying flat vec4 cd;
varying flat float sxv;
varying vec3 lpos;

float h11(float p) { p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }

vec3 car_paint(float s) {
	float h = h11(s * 413.0);
	vec3 c;
	if (h < 0.22) c = vec3(0.82, 0.83, 0.84);        // белая
	else if (h < 0.38) c = vec3(0.50, 0.52, 0.55);   // серебро
	else if (h < 0.52) c = vec3(0.04, 0.04, 0.05);   // чёрная
	else if (h < 0.62) c = vec3(0.55, 0.06, 0.05);   // красная
	else if (h < 0.72) c = vec3(0.07, 0.17, 0.42);   // синяя
	else if (h < 0.78) c = vec3(0.85, 0.62, 0.08);   // такси
	else if (h < 0.85) c = vec3(0.10, 0.25, 0.16);   // тёмно-зелёная
	else if (h < 0.92) c = vec3(0.60, 0.50, 0.38);   // беж
	else c = vec3(0.22, 0.23, 0.25);                 // графит
	return c;
}

void vertex() {
	cd = INSTANCE_CUSTOM;
	part = floor(COLOR.r * 10.0 + 0.5);
	sxv = length(MODEL_MATRIX[0].xyz);
	lpos = VERTEX;
	if (road_anim) {
		float L = cd.x;
		float s = fract(cd.z + anim_t * cd.y / L) * L;
		// присутствие по плотности движения (по времени суток) и плавное появление на концах полосы
		float vis = smoothstep(cd.w, cd.w + 0.04, traffic) * smoothstep(0.0, 8.0, s) * smoothstep(L, L - 8.0, s);
		// ночью издалека фары и стопы — крупнее (иначе меньше пикселя и мерцают)
		if (part > 1.5 && part < 3.5) {
			vec3 wp0 = (MODEL_MATRIX * vec4(s / sxv, 0.0, 0.0, 1.0)).xyz;
			float dist = length(wp0 - CAMERA_POSITION_WORLD);
			float g = (clamp(dist / 150.0, 1.0, 6.0) - 1.0) * clamp(night * 1.4, 0.0, 1.0);
			VERTEX.z += UV.x * g * 0.30 / max(length(MODEL_MATRIX[2].xyz), 0.01);
			VERTEX.y += UV.y * g * 0.18;
		}
		VERTEX *= vis;
		VERTEX.x += s / sxv;
	}
}

void fragment() {
	float lights_on = clamp(night * 1.3 + 0.05, 0.0, 1.0);
	vec3 paint = road_anim || cd.w > 0.5 ? car_paint(road_anim ? cd.w : cd.x) : base_paint;
	if (road_anim && sxv > 2.0) {
		// автобус: красный, жёлтый или белый
		float h = h11(cd.w * 77.0);
		paint = h < 0.4 ? vec3(0.62, 0.08, 0.06) : (h < 0.7 ? vec3(0.85, 0.62, 0.10) : vec3(0.85));
	}
	float mask = road_anim ? 3.0 : cd.y;
	int lm = int(mask + 0.5);
	vec3 albedo = paint;
	float rough = 0.35;
	float metal = 0.25;
	vec3 emit = vec3(0.0);
	if (part < 0.5) {
		albedo = paint;
	} else if (part < 1.5) {
		albedo = vec3(0.04, 0.06, 0.08);
		rough = 0.08;
		metal = 0.6;
		// окна: у вагонов, автобусов и катеров ночью горят, с простенками
		float win = road_anim ? (sxv > 2.0 ? 1.0 : 0.0) : cd.z;
		if (win > 0.0) {
			float seg = step(0.18, fract(lpos.x / 1.9));
			emit = vec3(1.0, 0.86, 0.62) * seg * win * lights_on * 1.6;
		}
	} else if (part < 2.5) {
		albedo = vec3(0.9);
		rough = 0.1;
		emit = vec3(1.0, 0.93, 0.80) * float(lm & 1) * mix(0.3, 9.0, lights_on);
	} else if (part < 3.5) {
		albedo = vec3(0.5, 0.04, 0.03);
		rough = 0.2;
		emit = vec3(1.0, 0.06, 0.03) * float((lm & 2) >> 1) * mix(0.2, 6.0, lights_on);
	} else if (part < 4.5) {
		albedo = vec3(0.025);
		rough = 0.8;
		metal = 0.0;
	} else if (part < 5.5) {
		albedo = vec3(0.80, 0.80, 0.78);
		rough = 0.4;
		metal = 0.1;
	} else if (part < 6.5) {
		albedo = vec3(0.16, 0.17, 0.18);
		rough = 0.5;
		metal = 0.5;
	} else {
		albedo = vec3(0.36, 0.26, 0.17);
		rough = 0.85;
		metal = 0.0;
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
