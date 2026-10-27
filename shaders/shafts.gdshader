// volumetrics.ts volumeFragment as a Godot fog volume: the same drifting value-noise mist, (0.002 + n * 0.006) per metre,
// thinning above 1 m by exp(-0.062 h), scaled by volumeStrength. Godot's froxel fog marches it and samples the sun's
// canopy shadow, which is what turns the gaps in the crowns into shafts.
shader_type fog;

global uniform float forest_time;
uniform float strength = 0.48;
uniform vec3 albedo : source_color = vec3(0.94, 0.82, 0.56);
uniform vec3 shade : source_color = vec3(0.13, 0.21, 0.23);
uniform float shade_gain = 1.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 p = floor(x), f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(p), hash(p + vec3(1, 0, 0)), f.x), mix(hash(p + vec3(0, 1, 0)), hash(p + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(p + vec3(0, 0, 1)), hash(p + vec3(1, 0, 1)), f.x), mix(hash(p + vec3(0, 1, 1)), hash(p + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fog() {
	vec3 p = WORLD_POSITION;
	float n = noise3(p * 0.065 + vec3(forest_time * 0.004, 0.0, 0.0));
	float d = (0.002 + n * 0.006) * exp(-max(p.y - 1.0, 0.0) * 0.062) * strength;
	DENSITY = d;
	ALBEDO = albedo;
	// The shaded mist's own cool tone (three.js mixed it in where the sun is blocked); emission is per unit density.
	EMISSION = shade * shade_gain * d;
}
