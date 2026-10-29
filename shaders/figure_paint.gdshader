// Applied while an actor's drawing is painted into its figure viewport
// (scripts/figure.gd). VERTEX is in the actor's own coordinates: world
// pixels, feet at 0, 0, y down. See figure.gd for what it does.
shader_type canvas_item;

uniform float flash = 0.0;
uniform bool textured = true;

varying vec2 local;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec3 c = COLOR.rgb;
	if (textured) {
		vec2 p = local;
		float weave = vnoise(p * 1.9) * 0.45 + vnoise(p * 4.3) * 0.3 + vnoise(p * 0.5) * 0.25;
		float folds = vnoise(vec2(p.x * 0.55, p.y * 0.07));
		float l = dot(c, vec3(0.3, 0.59, 0.11));
		c = mix(vec3(l), c, 0.8);
		c *= 0.78 + 0.32 * weave;
		c *= 0.86 + 0.2 * folds;
		// The hem soaked dark from the wet streets.
		c *= 1.0 - 0.28 * smoothstep(-14.0, -1.0, p.y);
	}
	COLOR.rgb = mix(c, vec3(1.0), flash);
}
