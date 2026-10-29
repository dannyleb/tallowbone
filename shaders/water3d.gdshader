// Canal water for the 3D stage: near black, mirror-smooth, rippled by two
// drifting normal maps and pocked by rain, rings spreading from every drop. Reflections come from the
// renderer (screen-space reflections and the sky), so lamps and the moon
// show in it.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 color : source_color = vec3(0.012, 0.03, 0.032);
uniform sampler2D ripples : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float scale = 0.35;

uniform float ring_strength = 0.5;
uniform float ring_cell = 0.4;

varying vec3 wpos;
varying float facing_up;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Rain rings (as in stone3d.gdshader): the surface's slope at p, in cells.
vec2 rings(vec2 p, float t) {
	vec2 g = floor(p);
	vec2 slope = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = g + vec2(float(i), float(j));
			vec2 h = hash2(c);
			float phase = fract(t * (0.8 + h.x * 0.5) + h.y);
			vec2 d = p - (c + 0.15 + h * 0.7);
			float r = length(d);
			float x = (r - phase * 1.2) * 8.0;
			float wave = cos(x * 3.1416) * exp(-x * x * 0.5);
			float amp = (1.0 - phase) * (1.0 - phase) * smoothstep(1.3, 0.2, r);
			slope += d / max(r, 1e-3) * wave * amp;
		}
	}
	return slope;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	facing_up = (MODEL_MATRIX * vec4(NORMAL, 0.0)).y;
}

void fragment() {
	vec2 uv = (abs(NORMAL.y) > 0.5 ? wpos.xz : wpos.xy) * scale;
	vec3 a = texture(ripples, uv + vec2(TIME * 0.031, TIME * 0.017)).xyz;
	vec3 b = texture(ripples, uv * 1.9 + vec2(-TIME * 0.023, TIME * 0.041)).xyz;
	vec3 c = texture(ripples, uv * 5.3 + vec2(TIME * 0.11, -TIME * 0.09)).xyz;
	NORMAL_MAP = normalize((a + b + c * 0.6) * 2.0 - 2.6) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.35;
	if (facing_up > 0.5 && ring_strength > 0.0) {
		vec2 rip = rings(wpos.xz / ring_cell, TIME) + rings(wpos.xz / ring_cell * 1.41 + 3.7, TIME * 1.17) * 0.6;
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(rip.x, 0.0, rip.y, 0.0)).xyz * ring_strength);
	}
	ALBEDO = color;
	ROUGHNESS = 0.03;
	SPECULAR = 0.6;
}
