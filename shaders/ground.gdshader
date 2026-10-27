// Forest floor: the flat grid is lifted to the height field here (terrain.gdshaderinc), with normals from its slope.
// Port of surfaces.ts createGround + materials.ts groundMaterial: the photographic litter texture (Poly Haven, one
// tile per 1.5625 m), the vertex tint (fbm), the darker animal trail, and beyond ~12-48 m a blend to the average
// green cover the detailed vegetation would show, everywhere except on the trail.
shader_type spatial;
render_mode cull_back;
#include "res://shaders/terrain.gdshaderinc"

uniform sampler2D ground_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 wpos;
varying vec3 tint;

float gc_hash(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float gc_noise(vec2 p) {
	vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(gc_hash(i), gc_hash(i + vec2(1.0, 0.0)), f.x), mix(gc_hash(i + vec2(0.0, 1.0)), gc_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	vec2 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	float h = fm_height(p);
	VERTEX.y = h;
	float e = 0.5;
	float hx = fm_height(p + vec2(e, 0.0)) - fm_height(p - vec2(e, 0.0));
	float hz = fm_height(p + vec2(0.0, e)) - fm_height(p - vec2(0.0, e));
	NORMAL = normalize(vec3(-hx, 2.0 * e, -hz));
	TANGENT = normalize(vec3(2.0 * e, hx, 0.0));
	BINORMAL = normalize(cross(NORMAL, TANGENT));
	wpos = vec3(p.x, h, p.y);
	float n = fm_fbm(p * 0.14);
	tint = vec3(0.48 + n * 0.12, 0.53 + n * 0.17, 0.34 + n * 0.1) * (abs(p.x - fm_trail(p.y)) < 0.6 ? 0.78 : 1.0);
}

void fragment() {
	vec2 uv = wpos.xz / 1.5625;
	vec3 col = texture(ground_color, uv).rgb * tint;
	float distant = smoothstep(12.0, 48.0, distance(CAMERA_POSITION_WORLD, wpos));
	float trail = abs(wpos.x - fm_trail(wpos.z));
	vec2 cuv = wpos.xz;
	float broad = gc_noise(cuv * 0.14);
	float medium = gc_noise(cuv * 0.57 + vec2(broad * 1.6, 21.4));
	float fine = gc_noise(cuv * 3.1 + vec2(7.3, 19.1));
	float patch = clamp(broad * 0.5 + medium * 0.35 + fine * 0.15, 0.0, 1.0);
	vec3 low = mix(vec3(0.019, 0.038, 0.009), vec3(0.060, 0.099, 0.028), patch);
	low *= 0.88 + clamp(dot(col, vec3(0.2126, 0.7152, 0.0722)) * 5.0, 0.0, 1.0) * 0.2;
	float cover = (1.0 - pow(1.0 - distant, 1.5)) * 0.985 * smoothstep(0.35, 1.2, trail);
	ALBEDO = mix(col, low, cover);
	NORMAL_MAP = texture(ground_normal, uv).rgb;
	NORMAL_MAP_DEPTH = 0.65;
	ROUGHNESS = 0.98;
	SPECULAR = 0.35;
}
