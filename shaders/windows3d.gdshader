// Lit windows in the city behind: warm, a few flickering (candles). Unlit
// and bright enough to bloom. COLOR.r is each window's brightness, COLOR.g
// its flicker phase (0 = steady), COLOR.b how far its curtains are drawn.
// A window with UVs (0..1 across, from the top left) shows its sash: a
// mullion and transom, glazing bars, curtains at the sides, and the lamp
// inside brightest low down; anything without (gas lamps, the church's
// glass) just glows.
shader_type spatial;
render_mode unshaded, cull_back;

// Deep amber (sRGB here; linear 1, 0.32, 0.05): the film tonemapping
// bleaches anything brighter toward a flat peach, so the glow stays low
// and saturated and only the lamp's own spot runs hot.
uniform vec3 warm : source_color = vec3(1.0, 0.6, 0.25);
uniform float energy = 0.9;

float bar(float x, float at, float w) {
	return 1.0 - smoothstep(w, w * 1.8, abs(x - at));
}

void fragment() {
	float flicker = COLOR.g > 0.0 ? 0.75 + 0.25 * sin(TIME * (3.0 + COLOR.g * 5.0) + COLOR.g * 40.0) * sin(TIME * 1.7 + COLOR.g * 9.0) : 1.0;
	vec3 col = warm * energy * COLOR.r * flicker;
	if (UV.x >= 0.0) {
		vec2 uv = UV;
		float frame = max(max(bar(uv.x, 0.0, 0.06), bar(uv.x, 1.0, 0.06)), max(bar(uv.y, 0.0, 0.05), bar(uv.y, 1.0, 0.05)));
		float bars = max(bar(uv.x, 0.5, 0.035), bar(uv.y, 0.38, 0.03));
		bars = max(bars, max(bar(uv.y, 0.7, 0.015), bar(uv.x, 0.25, 0.012) * step(0.38, uv.y)));
		bars = max(bars, bar(uv.x, 0.75, 0.012) * step(0.38, uv.y));
		float open = 0.12 + COLOR.b * 0.25;
		float curtain = smoothstep(open, open - 0.08, uv.x) + smoothstep(1.0 - open, 1.0 - open + 0.08, uv.x);
		float lamp = 0.3 + 1.1 * clamp(1.0 - length((uv - vec2(0.5, 0.9)) * vec2(1.3, 1.0)), 0.0, 1.0);
		col *= lamp * (1.0 - 0.8 * clamp(curtain, 0.0, 1.0));
		col *= vec3(1.0) - max(frame, bars) * 0.94;
	}
	ALBEDO = col;
}
