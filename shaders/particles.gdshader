// atmosphere.ts addParticles(): 600 warm motes in a 110 m tile that wraps around the eye, drifting on slow sines, fading
// out between 34 and 49 m. A faint glow everywhere, bright only where the sun reaches them: three.js read the shadow map
// in the vertex shader; here the light() pass's ATTENUATION carries the same canopy shadow.
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, fog_disabled, ambient_light_disabled;

global uniform float forest_time;
uniform float px_scale = 1.0;
const vec3 MOTE = vec3(0.83, 0.73, 0.48);

varying float v_shimmer;
varying float v_glow;

void vertex() {
	vec3 p = VERTEX;
	float seed = COLOR.r;
	float t = forest_time;
	vec3 eye = CAMERA_POSITION_WORLD;
	p.xz += floor((eye.xz - p.xz) / 110.0 + 0.5) * 110.0;
	p.x += sin(t * 0.24 + seed * 50.0) * 0.7;
	p.y += sin(t * 0.38 + seed * 90.0) * 0.35;
	p.z += cos(t * 0.22 + seed * 34.0) * 0.55;
	VERTEX = p;
	float edge = 1.0 - smoothstep(34.0, 49.0, distance(p.xz, eye.xz));
	v_shimmer = edge * (0.5 + 0.5 * pow(sin(seed * 17.0 + t * 0.4) * 0.5 + 0.5, 4.0));
	vec4 mv = MODELVIEW_MATRIX * vec4(p, 1.0);
	POINT_SIZE = clamp(24.0 / max(1.0, -mv.z), 0.8, 2.5) * px_scale;
}

void fragment() {
	float disc = 1.0 - smoothstep(0.05, 1.0, length(POINT_COORD - 0.5) * 2.0);
	ALBEDO = vec3(0.0);
	EMISSION = MOTE * 0.018 * v_shimmer * disc;
	v_glow = 0.34 * v_shimmer * disc;
	ALPHA = 1.0;
}

void light() {
	SPECULAR_LIGHT += MOTE * v_glow * ATTENUATION;
}
