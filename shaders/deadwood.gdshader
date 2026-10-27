// Fallen logs and their branch stubs (vegetation.ts bark + materials.ts deadwoodMaterial): the plain bark photo with
// its normal map, no wind, and on the logs dark moss in noise patches that favour the upper side.
shader_type spatial;
render_mode cull_back;

uniform bool mossy = true;
uniform vec3 tint : source_color = vec3(0.690, 0.655, 0.580);
uniform sampler2D bark_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bark_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 lpos;
varying vec3 lnrm;

float lh(vec3 p) { p = fract(p * 0.1031); p += dot(p, p.zyx + 31.32); return fract((p.x + p.y) * p.z); }
float lnz(vec3 p) {
	vec3 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(lh(i), lh(i + vec3(1, 0, 0)), f.x), mix(lh(i + vec3(0, 1, 0)), lh(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(lh(i + vec3(0, 0, 1)), lh(i + vec3(1, 0, 1)), f.x), mix(lh(i + vec3(0, 1, 1)), lh(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	lpos = VERTEX;
	lnrm = NORMAL;
}

void fragment() {
	vec3 c = texture(bark_color, UV).rgb * tint;
	if (mossy) {
		float patches = lnz(lpos * 6.0) * 0.7 + lnz(lpos * 18.0) * 0.3;
		float moss = smoothstep(0.32, 0.63, lnrm.y * 0.52 + patches * 0.68);
		c = mix(c, mix(vec3(0.04, 0.075, 0.014), vec3(0.16, 0.23, 0.046), patches), moss * 0.9);
	}
	ALBEDO = c;
	NORMAL_MAP = texture(bark_normal, UV).rgb;
	NORMAL_MAP_DEPTH = 0.7;
	ROUGHNESS = 0.96;
	SPECULAR = 0.35;
}
