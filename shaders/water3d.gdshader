// Canal water for the 3D stage: near black, mirror-smooth, rippled by two
// drifting normal maps and pocked by rain. Reflections come from the
// renderer (screen-space reflections and the sky), so lamps and the moon
// show in it.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 color : source_color = vec3(0.012, 0.03, 0.032);
uniform sampler2D ripples : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float scale = 0.35;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (abs(NORMAL.y) > 0.5 ? wpos.xz : wpos.xy) * scale;
	vec3 a = texture(ripples, uv + vec2(TIME * 0.031, TIME * 0.017)).xyz;
	vec3 b = texture(ripples, uv * 1.9 + vec2(-TIME * 0.023, TIME * 0.041)).xyz;
	vec3 c = texture(ripples, uv * 5.3 + vec2(TIME * 0.11, -TIME * 0.09)).xyz;
	NORMAL_MAP = normalize((a + b + c * 0.6) * 2.0 - 2.6) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.35;
	ALBEDO = color;
	ROUGHNESS = 0.03;
	SPECULAR = 0.6;
}
