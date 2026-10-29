// The night over the Canal District: near black overhead, a cold haze at
// the horizon, ragged cloud, and the moon.
//
// The moon is drawn where you can see it (moon_dir, high over the
// rooftops), not where the moonlight comes from, which is low behind the
// city and always hidden by it. It isn't quite a moon: look at it long
// enough and there is an iris, and a slit, and the slit widens when the
// lightning shows what stands in the fog (pupil, 0 to 1).
//
// flash lights the clouds from inside for the lightning (scripts/storm.gd).
// No TIME here: a sky that changes every frame makes the renderer rebuild
// its reflections every frame, so these only change during a storm.
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.006, 0.008, 0.016);
uniform vec3 horizon : source_color = vec3(0.09, 0.11, 0.15);
uniform vec3 moon_color : source_color = vec3(0.92, 0.93, 1.0);
uniform vec3 moon_dir = vec3(0.42, 0.36, -1.0);
// Angular radius of the moon, radians.
uniform float moon_size = 0.05;
uniform float pupil = 0.0;
uniform float flash = 0.0;
uniform vec3 flash_color : source_color = vec3(0.75, 0.8, 1.0);
uniform sampler2D clouds : hint_default_black, filter_linear_mipmap, repeat_enable;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

// The moon's face at m (disc radius 1): a pale disc with maria, and under
// them, faintly, an eye.
vec3 moon_face(vec2 m) {
	float r = length(m);
	float a = atan(m.y, m.x);
	// Maria.
	float maria = smoothstep(0.35, 0.1, length(m - vec2(-0.25, 0.2))) * 0.25 + smoothstep(0.3, 0.05, length(m - vec2(0.3, -0.15))) * 0.2;
	// The iris: fine radial fibres, darker toward a ring at its edge.
	float fibres = 0.0;
	for (int i = 0; i < 3; i++) {
		float k = 23.0 + float(i) * 17.0;
		fibres += abs(sin(a * k + hash(float(i)) * 6.0 + r * (3.0 + float(i)))) * 0.33;
	}
	float iris = smoothstep(0.78, 0.7, r) * smoothstep(0.08, 0.2, r);
	float limbus = smoothstep(0.55, 0.72, r) * smoothstep(0.86, 0.74, r);
	// The slit: tall and narrow, widening with `pupil`.
	float w = mix(0.05, 0.3, pupil);
	float slit = smoothstep(1.0, 0.85, length(vec2(m.x / w, m.y / mix(0.62, 0.7, pupil))));
	float shade = 1.0 - maria - iris * (0.12 + fibres * 0.1) - limbus * 0.18;
	vec3 col = moon_color * shade;
	// The pupil is the dark of the sky behind it, with a red warmth at its edge.
	col = mix(col, vec3(0.0), slit * 0.92);
	col += vec3(0.5, 0.05, 0.02) * smoothstep(0.6, 1.0, slit) * (1.0 - smoothstep(0.98, 1.0, slit)) * pupil;
	// Limb darkening.
	col *= mix(1.0, 0.7, pow(r, 3.0));
	return col;
}

void sky() {
	float up = clamp(EYEDIR.y, 0.0, 1.0);
	vec3 col = mix(horizon, zenith, pow(up, 0.5));
	vec3 md = normalize(moon_dir);
	float d = dot(EYEDIR, md);
	float disc = smoothstep(cos(moon_size), cos(moon_size * 0.95), d);
	float halo = pow(max(d, 0.0), 900.0) * 0.5 + pow(max(d, 0.0), 80.0) * 0.07 + pow(max(d, 0.0), 8.0) * 0.02;
	// Coordinates on the disc: x along the horizon, y up.
	vec3 right = normalize(cross(md, vec3(0.0, 1.0, 0.0)));
	vec3 top = cross(right, md);
	vec3 off = EYEDIR - md * d;
	vec2 m = vec2(dot(off, right), dot(off, top)) / sin(moon_size);
	if (disc > 0.0) {
		col = mix(col, moon_face(m) * 1.6, disc);
	}
	col += moon_color * halo;
	// Ragged cloud, drifting over the moon too.
	vec2 cuv = EYEDIR.xz / max(EYEDIR.y + 0.15, 0.05) * 0.18;
	float cn = texture(clouds, cuv).r;
	float c = smoothstep(0.45, 0.8, cn) * smoothstep(-0.02, 0.15, EYEDIR.y);
	col = mix(col, horizon * 0.7, c * 0.75);
	// Lightning: the clouds lit from inside, brightest low down and at
	// their thick hearts.
	if (flash > 0.0) {
		float glow = (0.35 + smoothstep(0.3, 0.85, cn) * 1.4) * (1.0 - up * 0.6);
		col += flash_color * flash * glow;
	}
	COLOR = col;
}
