// The finished frame, as it's put on screen (main.gd's game view): a light
// sharpening for the upscale, a little colour fringing toward the corners,
// and film grain, heavier in the shadows. `full` off (the browser) keeps
// only the grain.
shader_type canvas_item;

uniform bool full = true;
uniform float grain = 0.03;
uniform float fringe = 0.0016;
uniform float sharpen = 0.22;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 col = texture(TEXTURE, UV).rgb;
	if (full) {
		vec2 c = UV - 0.5;
		vec2 off = c * dot(c, c) * fringe * 4.0;
		col.r = texture(TEXTURE, UV - off).r;
		col.b = texture(TEXTURE, UV + off).b;
		vec2 px = TEXTURE_PIXEL_SIZE;
		vec3 around = texture(TEXTURE, UV + vec2(px.x, 0.0)).rgb + texture(TEXTURE, UV - vec2(px.x, 0.0)).rgb
			+ texture(TEXTURE, UV + vec2(0.0, px.y)).rgb + texture(TEXTURE, UV - vec2(0.0, px.y)).rgb;
		col += (col - around * 0.25) * sharpen;
	}
	float n = hash(FRAGCOORD.xy + fract(TIME * 7.13) * 311.0) - 0.5;
	float l = dot(col, vec3(0.3, 0.59, 0.11));
	col += n * grain * (1.0 - min(l, 1.0) * 0.75);
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
