// Foreground silhouettes between you and the play (chains hanging from
// somewhere overhead, hooks and gibbet cages on them), close to the camera
// and out of focus. Where one passes in front of the Lamplighter it thins
// away, a dither rather than see-through, so it keeps writing depth and the
// depth of field still blurs what's left of it.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 color : source_color = vec3(0.018, 0.018, 0.022);
uniform float roughness = 0.55;
// The Lamplighter on screen (0..1), and how far round them it clears
// (screen heights).
uniform vec2 player_uv = vec2(0.5);
uniform float clear_radius = 0.22;

// An ordered 4x4 dither threshold for a pixel.
float bayer2(vec2 a) {
	a = floor(a);
	return fract(a.x / 2.0 + a.y * a.y * 0.75);
}

float bayer4(vec2 a) {
	return bayer2(0.5 * a) * 0.25 + bayer2(a);
}

void fragment() {
	vec2 d = (SCREEN_UV - player_uv) * vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0);
	float keep = max(smoothstep(clear_radius * 0.55, clear_radius, length(d)), 0.12);
	if (keep < 1.0 && keep <= bayer4(FRAGCOORD.xy)) {
		discard;
	}
	ALBEDO = color;
	ROUGHNESS = roughness;
	SPECULAR = 0.4;
}
