// Something standing on the rooftops after the lightning shows the thing
// in the fog (scripts/storm.gd): too tall, too thin, its arms too long,
// quite still. Fogged like the houses, so it's only a darker shape
// against the haze until the next flash.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_disabled, shadows_disabled;

uniform float presence = 0.0;
uniform float lean = 0.0;
uniform vec3 color : source_color = vec3(0.006, 0.007, 0.01);

float seg(vec2 p, vec2 a, vec2 b, float ra, float rb) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - mix(ra, rb, h);
}

void fragment() {
	// Metres: x across from the middle, y up from the feet; 1.4 x 4 m.
	vec2 p = vec2((UV.x - 0.5) * 1.4, (1.0 - UV.y) * 4.0);
	p.x -= lean * p.y * 0.06;
	// A long robe narrowing upward, a small bowed head, arms to the knee.
	float d = seg(p, vec2(0.0, 0.0), vec2(0.0, 2.9), 0.26, 0.15);
	d = min(d, seg(p, vec2(0.04, 3.05), vec2(0.07, 3.35), 0.11, 0.09));
	d = min(d, seg(p, vec2(-0.16, 2.8), vec2(-0.3, 1.0), 0.06, 0.04));
	d = min(d, seg(p, vec2(0.16, 2.8), vec2(0.27, 0.95), 0.06, 0.04));
	d = min(d, seg(p, vec2(-0.3, 1.0), vec2(-0.34, 0.75), 0.03, 0.01));
	d = min(d, seg(p, vec2(0.27, 0.95), vec2(0.33, 0.7), 0.03, 0.01));
	float aa = fwidth(d);
	ALBEDO = color;
	ALPHA = smoothstep(aa, -aa, d) * presence;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
