// The pale veil that seals a door: a faintly glowing membrane, slowly
// crawling. Unlit, so it glows the same in any dark; the Lantern burns it.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;

uniform vec3 color : source_color = vec3(0.86, 0.82, 0.72);
uniform sampler2D crawl : hint_default_black, filter_linear_mipmap, repeat_enable;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = vec2(wpos.x + wpos.z, wpos.y) * 0.6;
	float a = texture(crawl, uv * vec2(1.0, 0.4) + vec2(0.0, TIME * 0.03)).r;
	float b = texture(crawl, uv * 2.3 - vec2(TIME * 0.02, TIME * 0.05)).r;
	float veins = smoothstep(0.55, 0.75, a * 0.6 + b * 0.6);
	// Brighter where you see it edge-on, like a soap film.
	float edge = 1.0 - abs(dot(NORMAL, VIEW));
	ALBEDO = color * (0.6 + 0.4 * b + 0.8 * veins + 0.6 * edge);
	ALPHA = 0.18 + 0.32 * veins + 0.25 * edge;
}
