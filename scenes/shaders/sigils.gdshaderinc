// Значки стихий (SDF) — те же, что на картах (scenes/ui/card_view.gd, sigil 1..6); id = стихия 0..5.
// Координаты эмблемы ~±0.13.
float fill(float d) { return smoothstep(0.006, -0.006, d); }
float stroke(float d, float w) { return smoothstep(w, w * 0.4, abs(d)); }

float sd_tri(vec2 p, vec2 a, vec2 b, vec2 c) {
	vec2 e0 = b - a, e1 = c - b, e2 = a - c;
	vec2 v0 = p - a, v1 = p - b, v2 = p - c;
	vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
	vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
	vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
	float s = sign(e0.x * e2.y - e0.y * e2.x);
	vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
		vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
		vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
	return -sqrt(d.x) * sign(d.y);
}

float sd_hex(vec2 p, float r) {
	const vec3 k = vec3(-0.866025404, 0.5, 0.577350269);
	p = abs(p);
	p -= 2.0 * min(dot(k.xy, p), 0.0) * k.xy;
	p -= vec2(clamp(p.x, -k.z * r, k.z * r), r);
	return length(p) * sign(p.y);
}

// Значки стихий — те же, что на картах (scenes/ui/card_view.gd, sigil 1..6), id = стихия.
float sigil_mask(vec2 e, int id) {
	float r = length(e);
	if (id == 0) { // пламя
		float body = length(e - vec2(0.0, 0.035)) - 0.062;
		float tip = sd_tri(e, vec2(-0.058, 0.03), vec2(0.058, 0.03), vec2(0.012, -0.135));
		float inner = length(e - vec2(0.0, 0.05)) - 0.028;
		return clamp(fill(min(body, tip)) - fill(inner) * 0.7, 0.0, 1.0);
	}
	if (id == 1) { // буря: спираль
		float a = atan(e.y, e.x) / 6.28318 + 0.5;
		float t = r / 0.038 - a;
		float d = abs(fract(t) - 0.5) * 0.038;
		return smoothstep(0.01, 0.005, d) * smoothstep(0.125, 0.11, r) * smoothstep(0.008, 0.02, r);
	}
	if (id == 2) { // свет: звезда
		float ang = atan(e.y, e.x);
		float rr = 0.045 + 0.085 * pow(abs(cos(ang * 4.0)), 10.0) + 0.03 * pow(abs(cos(ang * 4.0 + 0.785)), 10.0);
		return fill(r - rr);
	}
	if (id == 3) { // камень: шестигранник
		return clamp(fill(sd_hex(e, 0.085)) - stroke(sd_hex(e, 0.045), 0.008) * 0.8, 0.0, 1.0);
	}
	if (id == 4) { // тень: полумесяц
		return fill(max(length(e) - 0.1, -(length(e - vec2(0.045, -0.035)) - 0.085)));
	}
	float m = 0.0; // прилив: три волны
	for (int k = -1; k <= 1; k++) {
		float y = e.y - float(k) * 0.042 - 0.016 * sin(e.x * 55.0 + float(k));
		m = max(m, smoothstep(0.012, 0.006, abs(y)));
	}
	return m * smoothstep(0.115, 0.1, abs(e.x));
}
