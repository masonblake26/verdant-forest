// atmosphere.ts forestSky(): a horizon-to-zenith gradient, a warm glow around the low afternoon sun and its disc.
// In the radiance (ambient) passes the lower hemisphere returns the hemisphere light's ground colour, so Godot's sky
// ambient reproduces three.js's HemisphereLight(sky #bed9e8, ground #53603d).
shader_type sky;
render_mode use_half_res_pass;

uniform vec3 top : source_color = vec3(0.467, 0.624, 0.671);
uniform vec3 bottom : source_color = vec3(0.647, 0.757, 0.788);
uniform vec3 hemi_sky : source_color = vec3(0.745, 0.851, 0.91);
uniform vec3 hemi_ground : source_color = vec3(0.325, 0.376, 0.239);
uniform vec3 sun_dir = vec3(-0.53, 0.59, -0.64);
// three.js lights the hemisphere through BRDF_Lambert (albedo / PI), so its intensity 1.9 reaches the surface as 1.9 / PI.
// Godot's ambient_light_energy does nothing with a sky source, so the gain goes into the radiance pass.
uniform float ambient_gain = 0.605;

vec3 forest_sky(vec3 d) {
	float h = pow(max(0.0, d.y), 0.6);
	vec3 c = mix(bottom, top, h);
	float glow = pow(max(0.0, dot(d, sun_dir)), 20.0);
	c += vec3(0.65, 0.5, 0.25) * glow * 0.7;
	c += vec3(2.0, 1.8, 1.3) * smoothstep(0.9994, 0.9998, dot(d, sun_dir));
	return c;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	if (AT_CUBEMAP_PASS) {
		COLOR = mix(hemi_ground, hemi_sky, 0.5 + 0.5 * d.y) * ambient_gain;
	} else {
		COLOR = forest_sky(d);
	}
}
