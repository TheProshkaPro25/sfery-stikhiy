// Деревья пейзажа меню (MultiMesh по видам крон, меши — MenuCity._tree_meshes): крона из нескольких икосаэдров
// с плоскими гранями, ствол. COLOR.r * 10: 0 крона, 1 ствол; COLOR.g — оттенок шара кроны (светлее/темнее).
// INSTANCE_CUSTOM: rgb — цвет листвы/хвои дерева. Лёгкое покачивание кроны — в вершинном шейдере.
shader_type spatial;
render_mode diffuse_burley;

uniform float anim_t = 0.0;

varying flat vec4 cd;
varying flat float part;
varying flat float shade;

void vertex() {
	cd = INSTANCE_CUSTOM;
	part = floor(COLOR.r * 10.0 + 0.5);
	shade = COLOR.g;
	float ph = MODEL_MATRIX[3].x * 0.045 + MODEL_MATRIX[3].z * 0.031;
	float sway = sin(anim_t * 1.2 + ph) * 0.5 + sin(anim_t * 2.3 + ph * 1.7) * 0.25;
	VERTEX.xz += vec2(0.018, 0.010) * sway * VERTEX.y * VERTEX.y;
}

void fragment() {
	vec3 leaf = cd.rgb * (0.72 + 0.6 * shade);
	ALBEDO = part > 0.5 ? vec3(0.17, 0.11, 0.07) : leaf;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	BACKLIGHT = part > 0.5 ? vec3(0.0) : leaf * 0.5;
}
