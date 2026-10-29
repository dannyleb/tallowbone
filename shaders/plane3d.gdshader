// The gameplay plane in the 3D stage: everyone and everything on it (the
// Lamplighter, enemies, lamp posts, signs, finds, gates) is drawn in 2D
// into a transparent viewport, and this quad shows that drawing at z = 0.
// Each pixel's normal comes from how near it is to a silhouette edge (as in
// shaders/volume.gdshader), so the 3D lights wrap round the figures; the
// alpha cut-out lets them cast real shadows on the walls behind. Light
// from behind (the moon, a lamp further back) shows through near the
// edges, as it does through cloth and hair: a rim that keeps figures
// readable against the dark.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D plane : source_color, filter_linear;
// How round: higher bends the edges away from you more steeply.
uniform float bulge = 1.5;
// How far in from the edge the rounding reaches, in plane pixels.
uniform float reach = 9.0;
// Bumps from the drawing's own shading.
uniform float detail = 0.5;
// How much light from behind comes through at the edges.
uniform float rim = 0.9;
// And a faint cold edge of their own, as if the moon caught them, so
// figures still read where no light reaches.
uniform vec3 edge_glow : source_color = vec3(0.32, 0.38, 0.55);
uniform float edge_energy = 0.07;

#define alpha_at(uv) texture(plane, uv).a
#define lum_at(uv) dot(texture(plane, uv).rgb, vec3(0.299, 0.587, 0.114))

void fragment() {
	vec2 texel = 1.0 / vec2(textureSize(plane, 0));
	vec4 c = texture(plane, UV);
	// The viewport stores colour premultiplied by alpha.
	ALBEDO = c.rgb / max(c.a, 0.001);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(plane, 0));
	vec2 n = vec2(0.0);
	for (int i = 1; i <= 3; i++) {
		vec2 px = texel * reach * float(i) / 3.0;
		float w = 1.0 / float(i);
		n.x += (alpha_at(UV - vec2(px.x, 0.0)) - alpha_at(UV + vec2(px.x, 0.0))) * w;
		n.y += (alpha_at(UV + vec2(0.0, px.y)) - alpha_at(UV - vec2(0.0, px.y))) * w;
	}
	vec2 d = texel * 1.5;
	n.x += (lum_at(UV - vec2(d.x, 0.0)) - lum_at(UV + vec2(d.x, 0.0))) * detail;
	n.y += (lum_at(UV + vec2(0.0, d.y)) - lum_at(UV - vec2(0.0, d.y))) * detail;
	NORMAL_MAP = normalize(vec3(n * bulge, 1.0)) * 0.5 + 0.5;
	float edge = smoothstep(0.15, 0.9, length(n));
	BACKLIGHT = vec3(rim * edge);
	EMISSION = edge_glow * edge_energy * edge;
	// Darker parts (leather, a soaked coat, boots) are wetter and catch the
	// lamps; pale ones (skin, bone, cloth) less.
	float lum = dot(ALBEDO, vec3(0.299, 0.587, 0.114));
	ROUGHNESS = mix(0.38, 0.78, smoothstep(0.05, 0.45, lum));
	SPECULAR = 0.45;
}
