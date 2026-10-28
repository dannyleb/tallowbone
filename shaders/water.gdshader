// Canal water: the dark, wet scene above mirrored in it, rippling, with a
// glinting surface line. Reads the screen behind it, so it's drawn after
// everything it should reflect (the Water node sits above the actors).
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform vec4 deep : source_color = vec4(0.015, 0.05, 0.05, 1.0);
uniform vec4 tint : source_color = vec4(0.45, 0.62, 0.6, 1.0);
// How much of the scene shows in it, at the surface.
uniform float reflectivity : hint_range(0.0, 1.0) = 0.7;

void fragment() {
	// How far below the surface this pixel is, in screen pixels.
	float below = UV.y / max(abs(dFdy(UV.y)), 1e-5);
	float wave = sin(UV.x * 90.0 + TIME * 2.2 + UV.y * 25.0) + 0.6 * sin(UV.x * 37.0 - TIME * 1.3);
	vec2 ripple = vec2(wave * 0.0025, 0.0) * (0.3 + UV.y);
	vec2 mirrored = vec2(SCREEN_UV.x, SCREEN_UV.y - 2.0 * below * SCREEN_PIXEL_SIZE.y) + ripple;
	vec3 reflection = texture(screen, mirrored).rgb * tint.rgb;
	float fade = clamp(1.0 - UV.y * 1.4, 0.0, 1.0);
	vec3 col = mix(deep.rgb, reflection * 1.6, reflectivity * fade);
	// The surface line catches the light.
	float edge = smoothstep(0.08, 0.0, UV.y) * (0.55 + 0.45 * sin(UV.x * 140.0 + TIME * 3.0));
	col += vec3(0.3, 0.45, 0.42) * edge * 0.6;
	COLOR = vec4(col, 0.96);
}
