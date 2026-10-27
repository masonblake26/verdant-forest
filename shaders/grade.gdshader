// Scene fog plus the parts of volumetrics.ts compositeFragment Godot doesn't already do (SSAO and volumetric fog cover the
// occlusion and mist). three.js's FogExp2 fades geometry by 1 - exp(-(density * d)^2), which no Godot fog mode can
// express, so it is applied here (the sky ignored fog). Then distant geometry fades into the directional sky between
// hazeStart and hazeEnd, the restrained pre-tonemap grade (saturation 1.085, cool shade, warm highlights) and a light
// vignette. A full-screen quad drawn first among the transparents, reading the HDR scene before tonemapping.
shader_type spatial;
render_mode unshaded, fog_disabled, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 top : source_color;
uniform vec3 bottom : source_color;
uniform vec3 sun_dir;
uniform float haze_start = 220.0;
uniform float haze_end = 435.0;
uniform float saturation = 1.085;
uniform vec3 fog_color : source_color;
uniform float fog_density = 0.0023;

vec3 forest_sky(vec3 d) {
	d = normalize(d);
	float h = pow(max(0.0, d.y), 0.6);
	vec3 c = mix(bottom, top, h);
	float glow = pow(max(0.0, dot(d, sun_dir)), 20.0);
	c += vec3(0.65, 0.5, 0.25) * glow * 0.7;
	c += vec3(2.0, 1.8, 1.3) * smoothstep(0.9994, 0.9998, dot(d, sun_dir));
	return c;
}

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float depth = texture(depth_tex, SCREEN_UV).r;
	if (depth > 0.0) {
		vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		v.xyz /= v.w;
		vec3 ray = (INV_VIEW_MATRIX * vec4(v.xyz, 0.0)).xyz;
		float d = length(ray);
		c = mix(c, fog_color, 1.0 - exp(-(fog_density * d) * (fog_density * d)));
		c = mix(c, forest_sky(ray), smoothstep(haze_start, haze_end, d));
	}
	float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(lum), c, saturation);
	c *= mix(vec3(0.94, 0.995, 1.025), vec3(1.018, 1.0, 0.97), smoothstep(0.10, 0.85, lum));
	float vignette = 1.0 - 0.10 * pow(length((SCREEN_UV - 0.5) * vec2(1.05, 0.85)), 1.8);
	ALBEDO = max(c, vec3(0.0)) * vignette;
}
