// Grass clumps placed on the GPU (vegetation.ts grass + compact-grass.ts + windMaterial('grass', compact)). Each
// 10 m patch is one MultiMesh of clump instances with no stored transforms: the instance index and the patch's world
// corner hash to the clump's position, yaw and size, so every patch always grows the same grass. The trail keeps a
// bare strip, trunks and stones are kept clear through a footprint mask, clumps thin with distance by rank (the
// original's cover curve) and every blade sways from its own root.
shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/terrain.gdshaderinc"

global uniform float forest_time;
global uniform float forest_wind;
instance uniform vec2 patch_origin;
uniform float per_patch = 2300.0;
uniform float patch_size = 10.0;
uniform sampler2D block_mask : filter_nearest, repeat_disable;
uniform float mask_extent = 400.0;

varying vec2 buv;
varying float tone;

vec4 h4(vec2 p, float k) {
	vec4 p4 = fract(vec4(p.xyx, k).xyzw * vec4(0.1031, 0.1030, 0.0973, 0.1099));
	p4 += dot(p4, p4.wzxy + 33.33);
	return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}

void vertex() {
	float id = float(INSTANCE_ID);
	// The hash is offset off zero: at patch origin (0, 0), just ahead of the entrance, h4's x and y inputs vanished and
	// all 2,300 clumps fell on one curve, leaving a lone strip of grass on bare ground.
	vec4 a = h4(patch_origin + vec2(73.13, 19.71), id);
	vec4 b = h4(patch_origin + 17.3, id * 1.37 + 5.0);
	vec2 root = patch_origin + a.xy * patch_size;
	float d = abs(root.x - fm_trail(root.y));
	float n = fm_noise(vec2(root.x * 0.19 + 11.0, root.y * 0.19));
	float keep = (d < 0.34 && a.z < 0.77) ? 0.0 : 1.0;
	vec2 muv = root / mask_extent + 0.5;
	if (muv.x > 0.0 && muv.x < 1.0 && muv.y > 0.0 && muv.y < 1.0 && texture(block_mask, muv).r > 0.5) keep = 0.0;
	float scale = 0.44 + n * 0.42 + a.w * 0.31;
	if (d < 0.68) scale *= 0.28;
	float sx = scale * (0.8 + b.x * 0.4) * 1.42;
	float sz = scale * (0.8 + b.y * 0.4) * 1.42;
	// distance cover: dense to 22 m, thinning to nothing by ~88 m (the original's grassDensity / cover curve)
	float gd = distance(root, CAMERA_POSITION_WORLD.xz);
	float cover = gd < 22.0 ? 1.0 : gd < 36.0 ? mix(1.0, 0.55, (gd - 22.0) / 14.0) : gd < 51.0 ? mix(0.55, 0.22, (gd - 36.0) / 15.0)
		: gd < 70.0 ? mix(0.22, 0.1, (gd - 51.0) / 19.0) : mix(0.1, 0.0, clamp((gd - 70.0) / 18.0, 0.0, 1.0));
	float rank = id / per_patch;
	float emerge = (1.0 - smoothstep(cover - 0.028, cover + 0.028, rank)) * smoothstep(0.0, 0.02, cover) * keep;
	// wind from the clump's root
	float ph = root.x * 0.37 + root.y * 0.22;
	float wave = sin(forest_time * 1.25 + ph) + 0.36 * sin(forest_time * 2.17 + ph * 1.47);
	vec3 v = VERTEX;
	float bend = pow(max(v.y, 0.0), 1.4);
	v.x += wave * bend * 0.13 * forest_wind;
	v.z += cos(forest_time * 0.93 + ph) * bend * 0.068 * forest_wind;
	v *= vec3(sx, scale, sz) * emerge;
	float yaw = a.z * 6.28318 + b.z;
	float cy = cos(yaw), sy = sin(yaw);
	v.xz = mat2(vec2(cy, -sy), vec2(sy, cy)) * v.xz;
	NORMAL.xz = mat2(vec2(cy, -sy), vec2(sy, cy)) * (NORMAL.xz / vec2(sx, sz));
	NORMAL = normalize(NORMAL);
	vec3 world = vec3(root.x, fm_height(root) - 0.015, root.y) + v;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(NORMAL, 0.0)).xyz;
	buv = UV;
	tone = b.w;
}

void fragment() {
	float midrib = exp(-pow((buv.x - 0.5) * 88.0, 2.0));
	float vein = pow(0.5 + 0.5 * cos((buv.y * 16.0 - abs(buv.x - 0.5) * 5.0) * 6.28318), 16.0);
	float tv = sin(buv.x * 143.0 + sin(buv.y * 91.0) * 2.0) * sin(buv.y * 177.0);
	vec3 c = COLOR.rgb * (0.9 + tv * 0.035 + midrib * 0.18 + vein * 0.065) * mix(0.89, 1.1, tone);
	ALBEDO = c;
	ROUGHNESS = 0.87;
	SPECULAR = 0.4;
	EMISSION = c * 0.055 * 0.6;
	BACKLIGHT = c * 0.6;
}
