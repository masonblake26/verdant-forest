// The walkable edge: a soft blue light curtain standing on the ground where the camera clamp stops you (±95 m). UV.y
// runs 0 at the ground to 1 at the top; bright foot and top lines, a glow fading upwards and faint drifting bands.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

global uniform float forest_time;
uniform vec3 tint : source_color = vec3(0.24, 0.58, 1.0);

void fragment() {
	float h = UV.y;
	float glow = pow(1.0 - h, 1.3) * 0.9;
	float foot = exp(-h * 30.0) * 2.0;
	float top = exp(-(1.0 - h) * 60.0) * 1.4;
	float bands = 0.75 + 0.25 * sin(UV.x * 1.3 - forest_time * 1.2 + h * 6.0);
	float near = 1.0 - smoothstep(30.0, 80.0, length(VERTEX));   // VERTEX is view space: fade with distance
	ALBEDO = tint * (glow * bands + foot + top) * (0.25 + 0.75 * near);
	ALPHA = 1.0;
}
