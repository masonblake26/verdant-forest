// Things fixed to a tree (materials.ts treeAttachedMaterial): vertex colours, rough, double-sided, and the tree's own
// wind so they ride the trunk exactly as the bark does (same root phase, same height bend).
shader_type spatial;
render_mode cull_disabled;

global uniform float forest_time;
global uniform float forest_wind;
uniform float roughness = 0.95;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	float ph = root.x * 0.37 + root.z * 0.22;
	float wave = sin(forest_time * 1.25 + ph) + 0.36 * sin(forest_time * 2.17 + ph * 1.47);
	float bend = min(1.0, VERTEX.y * 0.05);
	VERTEX.x += wave * bend * 0.14 * forest_wind;
	VERTEX.z += cos(forest_time * 0.93 + ph) * bend * 0.068 * forest_wind;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = roughness;
	SPECULAR = 0.4;
}
