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
	vec2 uv = vec2(wpos.x + wpos.z, wpos.y);
	// Hanging strands, stretched tall, slowly creeping downward; a finer
	// web between them.
	float strands = texture(crawl, vec2(uv.x * 2.2, uv.y * 0.12 + TIME * 0.015)).r;
	float web = texture(crawl, vec2(uv.x * 5.0, uv.y * 0.5 + TIME * 0.04)).r;
	float s = smoothstep(0.58, 0.82, strands) * 0.8 + smoothstep(0.66, 0.9, web) * 0.45;
	ALBEDO = color * (0.3 + 1.6 * s);
	ALPHA = clamp(0.04 + 0.5 * s, 0.0, 0.7);
}
