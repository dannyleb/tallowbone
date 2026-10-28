// The night over the Canal District: near black overhead, a cold haze at
// the horizon, ragged cloud, and the moon where the moonlight comes from
// (the first directional light).
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.006, 0.008, 0.016);
uniform vec3 horizon : source_color = vec3(0.05, 0.065, 0.09);
uniform vec3 moon_color : source_color = vec3(0.92, 0.93, 1.0);
// Angular radius of the moon, radians.
uniform float moon_size = 0.045;
uniform sampler2D clouds : hint_default_black, filter_linear_mipmap, repeat_enable;

void sky() {
	float up = clamp(EYEDIR.y, 0.0, 1.0);
	vec3 col = mix(horizon, zenith, pow(up, 0.5));
	if (LIGHT0_ENABLED) {
		float d = dot(EYEDIR, LIGHT0_DIRECTION);
		float disc = smoothstep(cos(moon_size), cos(moon_size * 0.92), d);
		float halo = pow(max(d, 0.0), 900.0) * 0.6 + pow(max(d, 0.0), 60.0) * 0.08 + pow(max(d, 0.0), 6.0) * 0.02;
		// A few darker maria on the disc.
		vec2 m = (EYEDIR - LIGHT0_DIRECTION * d).xy / moon_size;
		float maria = smoothstep(0.35, 0.1, length(m - vec2(-0.25, 0.2))) * 0.25 + smoothstep(0.3, 0.05, length(m - vec2(0.3, -0.15))) * 0.2;
		col += moon_color * (disc * (4.0 - maria * 6.0) + halo);
	}
	// Ragged cloud. (No TIME here: a sky that changes every frame makes the
	// renderer rebuild its reflections every frame.)
	vec2 cuv = EYEDIR.xz / max(EYEDIR.y + 0.15, 0.05) * 0.18;
	float c = smoothstep(0.45, 0.8, texture(clouds, cuv).r) * smoothstep(-0.02, 0.15, EYEDIR.y);
	col = mix(col, horizon * 0.7, c * 0.75);
	COLOR = col;
}
