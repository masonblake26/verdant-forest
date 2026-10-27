// The forest's height field on the GPU: the same integer hash, value noise and fbm as forest_math.gd (math.ts), so the
// displaced terrain matches the CPU heights used to place every tree, rock and plant.
uint fm_hash_u(int x, int z) {
	uint h = uint(x) * 374761393u + uint(z) * 668265263u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	return h ^ (h >> 16u);
}
float fm_hash(int x, int z) { return float(fm_hash_u(x, z)) / 4294967295.0; }
float fm_noise(vec2 p) {
	ivec2 i = ivec2(floor(p));
	vec2 f = p - floor(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(fm_hash(i.x, i.y), fm_hash(i.x + 1, i.y), u.x), mix(fm_hash(i.x, i.y + 1), fm_hash(i.x + 1, i.y + 1), u.x), u.y);
}
float fm_fbm(vec2 p) {
	return fm_noise(p) * 0.53 + fm_noise(p * 2.03 + vec2(12.0, 5.0)) * 0.27 + fm_noise(p * 4.09) * 0.13 + fm_noise(p * 8.21) * 0.07;
}
float fm_height(vec2 p) {
	return (fm_fbm(p * 0.045 + vec2(14.0, -2.0)) - 0.5) * 5.4 + sin(p.x * 0.037 + p.y * 0.013) * 1.5 + sin(p.y * 0.043) * 0.8
		+ (fm_noise(p * 0.39) - 0.5) * 0.12;
}
float fm_trail(float z) { return sin(z * 0.09) * 3.6 + sin(z * 0.027) * 4.0; }
