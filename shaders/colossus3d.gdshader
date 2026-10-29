// What stands in the fog beyond the city, drawn on one huge quad far
// behind it (scripts/storm.gd): hunched shoulders, a long skull crowned
// with branching growths, arms longer than the district, one hand on the
// rooftops at the edge of the world, and a cluster of eyes.
//
// It isn't fogged: the lightning brightens the fog and the sky behind it,
// and it stands out black. `reveal` fades it in and out; `eyes` opens
// them, and they glow on after the light has gone.
shader_type spatial;
render_mode unshaded, fog_disabled, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float reveal = 0.0;
uniform float eyes = 0.0;
// The quad's size in metres (the shape is drawn in metres, x across from
// the middle, y up from the bottom edge).
uniform vec2 size = vec2(420.0, 320.0);
uniform vec3 body_color : source_color = vec3(0.004, 0.005, 0.009);
uniform vec3 eye_color : source_color = vec3(1.0, 0.32, 0.12);
uniform sampler2D grain : filter_linear_mipmap, repeat_enable;

float seg(vec2 p, vec2 a, vec2 b, float ra, float rb) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - mix(ra, rb, h);
}

float ell(vec2 p, vec2 c, vec2 r, float tilt) {
	vec2 q = p - c;
	float s = sin(tilt);
	float co = cos(tilt);
	q = vec2(co * q.x + s * q.y, -s * q.x + co * q.y);
	return (length(q / r) - 1.0) * min(r.x, r.y);
}

float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

// A growth from the crown: three bending segments, thinning, forking once.
float horn(vec2 p, vec2 root, float ang, float len, float bend, float thick) {
	vec2 dir = vec2(sin(ang), cos(ang));
	vec2 a = root;
	float d = 1e5;
	float r = thick;
	for (int i = 0; i < 3; i++) {
		float l = len * (0.45 - float(i) * 0.1);
		vec2 b = a + dir * l;
		d = min(d, seg(p, a, b, r, r * 0.7));
		if (i == 1) {
			vec2 fdir = normalize(dir + vec2(-bend * 2.5, 0.2));
			d = min(d, seg(p, b, b + fdir * l * 0.8, r * 0.6, r * 0.15));
		}
		ang += bend;
		dir = vec2(sin(ang), cos(ang));
		a = b;
		r *= 0.7;
	}
	return d;
}

float body(vec2 p) {
	float d = ell(p, vec2(0.0, 40.0), vec2(80.0, 110.0), 0.0);
	// Shoulders, hunched, the left higher.
	d = smin(d, ell(p, vec2(-62.0, 142.0), vec2(52.0, 30.0), 0.25), 18.0);
	d = smin(d, ell(p, vec2(64.0, 132.0), vec2(55.0, 27.0), -0.2), 18.0);
	// The neck thrust forward, the long skull hanging from it.
	d = smin(d, seg(p, vec2(0.0, 140.0), vec2(8.0, 176.0), 22.0, 15.0), 10.0);
	d = smin(d, ell(p, vec2(10.0, 196.0), vec2(21.0, 34.0), -0.12), 6.0);
	// Mandibles.
	d = min(d, seg(p, vec2(-2.0, 170.0), vec2(-12.0, 132.0), 3.5, 1.0));
	d = min(d, seg(p, vec2(20.0, 168.0), vec2(30.0, 128.0), 3.5, 1.0));
	d = min(d, seg(p, vec2(9.0, 166.0), vec2(10.0, 140.0), 2.5, 0.6));
	// The crown.
	vec2 crown = vec2(12.0, 222.0);
	d = min(d, horn(p, crown + vec2(-14.0, -4.0), -0.9, 120.0, -0.25, 5.0));
	d = min(d, horn(p, crown + vec2(-8.0, 0.0), -0.45, 150.0, -0.18, 5.5));
	d = min(d, horn(p, crown + vec2(-2.0, 2.0), -0.12, 110.0, 0.2, 4.5));
	d = min(d, horn(p, crown + vec2(5.0, 2.0), 0.18, 160.0, 0.15, 5.5));
	d = min(d, horn(p, crown + vec2(12.0, -2.0), 0.55, 130.0, 0.24, 5.0));
	d = min(d, horn(p, crown + vec2(16.0, -6.0), 1.0, 95.0, 0.3, 4.0));
	// Left arm: up to a high elbow, down to a hand on the horizon.
	d = smin(d, seg(p, vec2(-95.0, 145.0), vec2(-160.0, 196.0), 13.0, 9.0), 10.0);
	d = smin(d, seg(p, vec2(-160.0, 196.0), vec2(-186.0, 72.0), 9.0, 6.0), 6.0);
	for (int i = 0; i < 4; i++) {
		float f = float(i);
		vec2 k = vec2(-186.0, 72.0);
		vec2 j = k + vec2(-14.0 + f * 9.0, -20.0 + abs(f - 1.5) * 4.0);
		d = min(d, seg(p, k, j, 2.6, 2.0));
		d = min(d, seg(p, j, j + vec2(-6.0 + f * 4.0, -18.0), 2.0, 0.6));
	}
	// Right arm: reaching over the city toward you.
	d = smin(d, seg(p, vec2(100.0, 132.0), vec2(168.0, 168.0), 12.0, 8.0), 10.0);
	d = smin(d, seg(p, vec2(168.0, 168.0), vec2(150.0, 90.0), 8.0, 5.5), 6.0);
	for (int i = 0; i < 5; i++) {
		float f = float(i);
		vec2 k = vec2(150.0, 90.0);
		vec2 j = k + vec2(-16.0 + f * 8.0, -26.0 + abs(f - 2.0) * 5.0);
		d = min(d, seg(p, k, j, 2.4, 1.6));
		d = min(d, seg(p, j, j + vec2(-4.0 + f * 2.5, -22.0), 1.6, 0.4));
	}
	return d;
}

const vec2 EYES[7] = vec2[](
	vec2(2.0, 204.0), vec2(16.0, 207.0), vec2(9.0, 193.0), vec2(-6.0, 192.0),
	vec2(22.0, 194.0), vec2(10.0, 216.0), vec2(-3.0, 213.0)
);
const float EYE_R[7] = float[](3.2, 2.6, 2.2, 1.6, 1.4, 1.8, 1.2);

void fragment() {
	vec2 p = vec2((UV.x - 0.5) * size.x, (1.0 - UV.y) * size.y);
	float d = body(p);
	// A ragged, shifting edge.
	d += (texture(grain, p * 0.006).r - 0.5) * 9.0;
	d += (texture(grain, p * 0.03 + vec2(TIME * 0.004, 0.0)).r - 0.5) * 3.0;
	float aa = fwidth(d) + 0.5;
	float shape = smoothstep(aa, -aa, d);
	// The bottom sinks into the haze at the horizon.
	shape *= smoothstep(10.0, 70.0, p.y);
	float glow = 0.0;
	for (int i = 0; i < 7; i++) {
		float open = clamp(eyes * 1.4 - float(i) * 0.06, 0.0, 1.0);
		vec2 q = (p - EYES[i]) / vec2(EYE_R[i], EYE_R[i] * mix(0.05, 0.7, open));
		float e = smoothstep(1.0, 0.3, length(q));
		glow += e * open + smoothstep(4.0, 0.0, length(p - EYES[i]) / EYE_R[i]) * 0.15 * open;
	}
	glow *= 0.85 + 0.15 * sin(TIME * 1.7);
	ALBEDO = body_color + eye_color * glow * 6.0;
	ALPHA = clamp(shape * reveal + glow * eyes, 0.0, 1.0);
}
