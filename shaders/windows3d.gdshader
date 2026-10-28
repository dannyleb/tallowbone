// Lit windows in the city behind: warm, a few flickering (candles). Unlit
// and bright enough to bloom. COLOR.r is each window's brightness, COLOR.g
// its flicker phase (0 = steady).
shader_type spatial;
render_mode unshaded, cull_back;

uniform vec3 warm : source_color = vec3(1.0, 0.62, 0.28);
uniform float energy = 1.6;

void fragment() {
	float flicker = COLOR.g > 0.0 ? 0.75 + 0.25 * sin(TIME * (3.0 + COLOR.g * 5.0) + COLOR.g * 40.0) * sin(TIME * 1.7 + COLOR.g * 9.0) : 1.0;
	ALBEDO = warm * energy * COLOR.r * flicker;
}
