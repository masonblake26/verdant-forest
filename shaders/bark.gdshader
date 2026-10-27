// Tree bark (materials.ts treeBarkMaterial + applyTreeWind). The Poly Haven bark photo tinted per species, its normal
// map (oak strong, beech mild, birch faint), moss creeping up the first metres, beech greyed, and birch's pale paper
// bark built from continuous noise fields: ageing, stains, peeling edges, lenticels and torn scars, with rough brown
// bark returning near the roots. The whole tree sways with the same wind as its leaves.
shader_type spatial;
render_mode cull_back;

global uniform float forest_time;
global uniform float forest_wind;
uniform int species = 0;   // 0 oak, 1 beech, 2 birch
uniform vec3 tint : source_color = vec3(0.776, 0.698, 0.596);
uniform float normal_depth = 0.65;
uniform sampler2D bark_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bark_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 bpos;
varying vec3 bvar;

float bh(vec3 p) { p = fract(p * 0.1031); p += dot(p, p.zyx + 31.32); return fract((p.x + p.y) * p.z); }
float bn(vec3 p) {
	vec3 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(bh(i), bh(i + vec3(1, 0, 0)), f.x), mix(bh(i + vec3(0, 1, 0)), bh(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(bh(i + vec3(0, 0, 1)), bh(i + vec3(1, 0, 1)), f.x), mix(bh(i + vec3(0, 1, 1)), bh(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	float ph = root.x * 0.37 + root.z * 0.22;
	float wave = sin(forest_time * 1.25 + ph) + 0.36 * sin(forest_time * 2.17 + ph * 1.47);
	float bend = min(1.0, VERTEX.y * 0.05);
	VERTEX.x += wave * bend * 0.14 * forest_wind;
	VERTEX.z += cos(forest_time * 0.93 + ph) * bend * 0.068 * forest_wind;
	bpos = VERTEX;
	bvar = vec3(root.x * 0.71, root.z * 0.37, root.x * 0.23 + root.z * 0.51);
}

void fragment() {
	vec3 c = texture(bark_color, UV).rgb * tint;
	float flake = sin(bpos.y * 14.0 + sin(bpos.x * 10.0) * 3.0) * sin(bpos.z * 8.3);
	float dist = length(VERTEX);
	float relief = 0.0;
	if (species == 2) {
		vec3 bp = bpos + bvar;
		float age = bn(bp * vec3(1.7, 0.36, 1.7));
		float stain = bn(bp * vec3(4.8, 1.6, 4.8) + 13.7);
		float paper = bn(bp * vec3(5.2, 13.0, 5.2) + 31.4);
		float fine_vis = 1.0 - smoothstep(3.0, 13.0, dist);
		float fine = mix(0.5, bn(bp * vec3(90.0, 25.0, 90.0)), fine_vis);
		float wh = bp.y + (stain - 0.5) * 0.07;
		float lent = smoothstep(0.70, 0.86, bn(vec3(bp.x * 19.0, wh * 112.0, bp.z * 19.0))) * smoothstep(0.31, 0.69, stain) * mix(0.22, 1.0, fine_vis);
		float torn = smoothstep(0.76, 0.9, bn(vec3(bp.x * 8.5, wh * 31.0, bp.z * 8.5) + 71.9)) * smoothstep(0.42, 0.68, age);
		float peel = (1.0 - smoothstep(0.022, 0.065, abs(paper - 0.51))) * smoothstep(0.48, 0.74, stain);
		vec3 pale = mix(vec3(0.26, 0.265, 0.235), vec3(0.54, 0.515, 0.445), smoothstep(0.22, 0.77, age));
		pale = mix(pale, pale * vec3(0.75, 0.73, 0.69), smoothstep(0.57, 0.8, stain) * 0.5);
		pale *= 0.9 + stain * 0.16 + (fine - 0.5) * 0.055;
		pale = mix(pale, vec3(0.34, 0.29, 0.215), peel * 0.2);
		pale = mix(pale, vec3(0.135, 0.114, 0.083), lent * 0.42 + torn * 0.46);
		pale *= mix(0.9, 1.09, smoothstep(0.015, 0.22, dot(c, vec3(0.2126, 0.7152, 0.0722))));
		float base_w = 1.0 - smoothstep(0.12, 2.1 + stain * 1.5, bpos.y + (age - 0.5) * 1.4);
		c = mix(pale, c * 0.94, base_w * 0.87);
		relief = (peel * 0.00036 + fine * 0.00015 - lent * 0.0002 - torn * 0.00032) * (1.0 - smoothstep(3.0, 12.0, dist));
	} else if (species == 1) {
		float l = dot(c, vec3(0.3, 0.59, 0.11));
		c = mix(c, vec3(l * 1.15, l * 1.17, l * 1.13), 0.75);
	}
	float moss = (1.0 - smoothstep(0.1, 3.3, bpos.y)) * (0.25 + 0.3 * sin(bpos.x * 5.0 + bpos.z * 7.0) + 0.17 * flake);
	ALBEDO = mix(c, vec3(0.055, 0.085, 0.019), clamp(moss, 0.0, 0.8));
	NORMAL_MAP = texture(bark_normal, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
	if (relief != 0.0) {
		vec3 dx = dFdx(VERTEX), dy = dFdy(VERTEX);
		vec3 rx = cross(dy, NORMAL), ry = cross(NORMAL, dx);
		float det = dot(dx, rx);
		NORMAL = normalize(abs(det) * NORMAL - sign(det) * (dFdx(relief) * rx + dFdy(relief) * ry));
	}
	ROUGHNESS = 0.94;
	SPECULAR = 0.35;
}
