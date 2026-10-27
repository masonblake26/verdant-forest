// Leaves, grass, ferns, shrubs and herbs (materials.ts windMaterial). Vertex-coloured, double-sided real geometry.
// Wind sways each plant from its root (kind sets how the bend grows with height); leaves also flutter. The surface
// adds a midrib, veins and fine variation along the leaf's UV, a per-plant tone, a raised-vein normal close up, a
// little fill light and sunlight passing through the lamina.
shader_type spatial;
render_mode cull_disabled;

global uniform float forest_time;
global uniform float forest_wind;
uniform int kind = 0;   // 0 leaf, 1 grass, 2 fern, 3 shrub
uniform float roughness = 0.76;

varying vec2 buv;
varying float tone;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	float ph = root.x * 0.37 + root.z * 0.22;
	float wave = sin(forest_time * 1.25 + ph) + 0.36 * sin(forest_time * 2.17 + ph * 1.47);
	float y = VERTEX.y;
	float bend = kind == 0 ? min(1.0, y * 0.05) : (kind == 1 ? pow(max(y, 0.0), 1.4) : (kind == 2 ? max(y, 0.0) * 0.38 : max(y, 0.0) * 0.24));
	VERTEX.x += wave * bend * (kind == 0 ? 0.14 : 0.13) * forest_wind;
	VERTEX.z += cos(forest_time * 0.93 + ph) * bend * 0.068 * forest_wind;
	if (kind == 0) {
		float fl = sin(forest_time * 4.3 + VERTEX.x * 13.0 + VERTEX.z * 17.0) * 0.012 * UV.y * forest_wind;
		VERTEX.y += fl;
		VERTEX.x += fl * 0.45;
	}
	buv = UV;
	vec3 hp = fract(vec3(root.xzx) * 0.1031);
	hp += dot(hp, hp.yzx + 33.33);
	tone = fract((hp.x + hp.y) * hp.z);
}

void fragment() {
	float midrib = exp(-pow((buv.x - 0.5) * 88.0, 2.0));
	float vein = pow(0.5 + 0.5 * cos((buv.y * 16.0 - abs(buv.x - 0.5) * 5.0) * 6.28318), 16.0);
	float tv = sin(buv.x * 143.0 + sin(buv.y * 91.0) * 2.0) * sin(buv.y * 177.0);
	vec3 c = COLOR.rgb * (0.9 + tv * 0.035 + midrib * 0.18 + vein * 0.065) * mix(0.89, 1.1, tone);
	ALBEDO = c;
	ROUGHNESS = roughness;
	SPECULAR = 0.4;
	if (kind != 1) {
		float fade = 1.0 - smoothstep(2.5, 6.0, length(VERTEX));
		float vh = (midrib * 0.7 + vein * 0.18 + tv * 0.035) * (kind == 2 ? 0.000035 : 0.00009) * fade;
		vec3 dx = dFdx(VERTEX), dy = dFdy(VERTEX);
		vec3 rx = cross(dy, NORMAL), ry = cross(NORMAL, dx);
		float det = dot(dx, rx);
		NORMAL = normalize(max(abs(det), 1e-12) * NORMAL - sign(det) * (dFdx(vh) * rx + dFdy(vh) * ry));
	}
	// the original's indirect fill (+6.5% of the albedo) and leaf translucency towards the sun
	EMISSION = c * (kind == 1 ? 0.055 : 0.065) * 0.6;
	BACKLIGHT = c * (kind == 1 ? 0.6 : 0.85);
}
