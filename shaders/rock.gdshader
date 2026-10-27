// Moss rock (materials.ts mossRockMaterial): the Poly Haven rock photo and normal map projected tri-planar in the
// rock's own space (so every instance keeps its pattern), a grey vertex mottle, and moss settling on the upward faces
// through two noise octaves with a fine grain. The tri-planar normal is rebuilt in rock space and turned by the instance.
shader_type spatial;
render_mode cull_back;

uniform vec3 base : source_color = vec3(0.757, 0.773, 0.702);
uniform sampler2D rock_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 mpos;
varying vec3 mnrm;
varying vec3 ax;
varying vec3 ay;
varying vec3 az;

float rh(vec3 p) { p = fract(p * 0.1031); p += dot(p, p.zyx + 31.32); return fract((p.x + p.y) * p.z); }
float rn(vec3 p) {
	vec3 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(rh(i), rh(i + vec3(1, 0, 0)), f.x), mix(rh(i + vec3(0, 1, 0)), rh(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(rh(i + vec3(0, 0, 1)), rh(i + vec3(1, 0, 1)), f.x), mix(rh(i + vec3(0, 1, 1)), rh(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// The normal map may be imported as two channels, so z is rebuilt.
vec3 nmap(vec2 uv) {
	vec2 xy = texture(rock_normal, uv).xy * 2.0 - 1.0;
	return vec3(xy * 0.72, sqrt(max(1.0 - dot(xy, xy), 0.0)));
}

void vertex() {
	mpos = VERTEX;
	mnrm = NORMAL;
	ax = normalize((MODELVIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
	ay = normalize((MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	az = normalize((MODELVIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
}

void fragment() {
	vec3 w = pow(abs(normalize(mnrm)), vec3(4.0));
	w /= max(dot(w, vec3(1.0)), 0.001);
	vec2 uvx = mpos.yz * 0.56, uvy = mpos.xz * 0.56, uvz = mpos.xy * 0.56;
	vec3 rock = texture(rock_color, uvx).rgb * w.x + texture(rock_color, uvy).rgb * w.y + texture(rock_color, uvz).rgb * w.z;
	vec3 c = base * COLOR.rgb * rock;
	float coarse = rn(mpos * 5.0) * 0.65 + rn(mpos * 14.0) * 0.35;
	float fine = rn(mpos * 165.0);
	float moss = smoothstep(0.38, 0.78, mnrm.y * 0.65 + coarse * 0.45);
	ALBEDO = c * mix(vec3(0.8, 0.85, 0.79), vec3(0.38, 0.55, 0.19), moss * 0.67) * (0.86 + fine * 0.2);
	vec3 s = sign(mnrm);
	vec3 nx = nmap(uvx), ny = nmap(uvy), nz = nmap(uvz);
	vec3 ln = normalize(vec3(nx.z * s.x, nx.x, nx.y) * w.x + vec3(ny.x, ny.z * s.y, ny.y) * w.y + vec3(nz.x, nz.y, nz.z * s.z) * w.z);
	NORMAL = normalize(ax * ln.x + ay * ln.y + az * ln.z);
	ROUGHNESS = 0.96;
	SPECULAR = 0.35;
}
