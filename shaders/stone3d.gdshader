// Wet stone for the 3D stage, mapped in world space (triplanar), so the
// generated level geometry needs no UVs. Faces looking up get the top set
// (cobbles), everything else the wall set (ashlar; brick and slate in the
// city). Each colour map carries its height in alpha. The rain does the
// rest: darker, glossy stone; water standing in the joints and filling the
// low parts of anything flat, rings spreading where the drops land in it;
// thin sheets of water running down walls, catching the lamps. A slow
// variation over the whole city breaks up the tiling.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D wall_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wall_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wall_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D top_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D top_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D top_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// Soft tileable noise (red): puddles, running water, grime.
uniform sampler2D wet_noise : hint_default_black, filter_linear_mipmap, repeat_enable;

// Metres of world per texture repeat.
uniform float tile_m = 2.0;
uniform vec3 tint : source_color = vec3(1.0);
// 0 dry .. 1 soaked.
uniform float wetness : hint_range(0.0, 1.0) = 0.85;
// How much of the flat tops stands in puddles.
uniform float puddles : hint_range(0.0, 1.0) = 0.45;
uniform float bump = 1.0;
// Rain rings in the puddles: how strongly they bend the reflections, and
// how big a patch each ring has to itself (m).
uniform float ripple_strength = 0.35;
uniform float ripple_cell = 0.3;

varying vec3 wpos;
varying vec3 wnrm;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// The slope of the water's surface at p (in ring cells) from the rings
// around it: each cell has a drop landing at its own moment, and its ring
// widens and flattens out until the next.
vec2 ripples(vec2 p, float t) {
	vec2 g = floor(p);
	vec2 slope = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = g + vec2(float(i), float(j));
			vec2 h = hash2(c);
			float phase = fract(t * (0.7 + h.x * 0.6) + h.y);
			vec2 d = p - (c + 0.15 + h * 0.7);
			float r = length(d);
			float x = (r - phase * 1.1) * 9.0;
			// One crest and trough, fading as it spreads.
			float wave = cos(x * 3.1416) * exp(-x * x * 0.5);
			float amp = (1.0 - phase) * (1.0 - phase) * smoothstep(1.2, 0.2, r);
			slope += d / max(r, 1e-3) * wave * amp;
		}
	}
	return slope;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 blend = pow(abs(n), vec3(6.0));
	blend /= (blend.x + blend.y + blend.z);
	float sx = n.x >= 0.0 ? 1.0 : -1.0;
	float sz = n.z >= 0.0 ? 1.0 : -1.0;
	// Image "up" is world up on the sides; on tops the image runs along x
	// and toward you.
	vec2 uv_x = vec2(-wpos.z * sx, -wpos.y) / tile_m;
	vec2 uv_y = vec2(wpos.x, wpos.z) / tile_m;
	vec2 uv_z = vec2(wpos.x * sz, -wpos.y) / tile_m;
	bool up = n.y > 0.0;

	vec4 alb_x = texture(wall_albedo, uv_x);
	vec4 alb_z = texture(wall_albedo, uv_z);
	vec4 alb_y = up ? texture(top_albedo, uv_y) : texture(wall_albedo, uv_y);
	vec3 albedo = alb_x.rgb * blend.x + alb_y.rgb * blend.y + alb_z.rgb * blend.z;
	float height = alb_x.a * blend.x + alb_y.a * blend.y + alb_z.a * blend.z;

	float r_x = texture(wall_rough, uv_x).r;
	float r_z = texture(wall_rough, uv_z).r;
	float r_y = up ? texture(top_rough, uv_y).r : texture(wall_rough, uv_y).r;
	float rough = r_x * blend.x + r_y * blend.y + r_z * blend.z;

	// Tangent-space normals per projection, blended in world space
	// ("whiteout" blend), then into view space.
	// (z rebuilt from x and y: compressed normal maps keep only those.)
	vec3 t_x = vec3(texture(wall_normal, uv_x).xy * 2.0 - 1.0, 0.0);
	vec3 t_z = vec3(texture(wall_normal, uv_z).xy * 2.0 - 1.0, 0.0);
	vec3 t_y = vec3((up ? texture(top_normal, uv_y).xy : texture(wall_normal, uv_y).xy) * 2.0 - 1.0, 0.0);
	t_x.z = sqrt(max(0.0, 1.0 - dot(t_x.xy, t_x.xy)));
	t_y.z = sqrt(max(0.0, 1.0 - dot(t_y.xy, t_y.xy)));
	t_z.z = sqrt(max(0.0, 1.0 - dot(t_z.xy, t_z.xy)));
	t_x.xy *= bump;
	t_y.xy *= bump;
	t_z.xy *= bump;
	// Side faces: texture x runs along -z*sx, texture up is +y.
	vec3 w_x = vec3(abs(t_x.z) * n.x, t_x.y + n.y, -t_x.x * sx + n.z);
	// Tops: texture x along +x, texture up is -z.
	vec3 w_y = vec3(t_y.x + n.x, abs(t_y.z) * n.y, -t_y.y + n.z);
	// Fronts: texture x along +x*sz, texture up is +y.
	vec3 w_z = vec3(t_z.x * sz + n.x, t_z.y + n.y, abs(t_z.z) * n.z);
	vec3 wn = normalize(w_x * blend.x + w_y * blend.y + w_z * blend.z);

	// Water on anything facing up: always in the joints, and where the
	// ground dips (the noise), filling from the lowest parts up.
	float flatness = smoothstep(0.75, 0.95, n.y);
	float noise_top = texture(wet_noise, wpos.xz * 0.23).r;
	float level = clamp((noise_top - (1.0 - puddles)) * 6.0, 0.0, 1.0);
	float pool = smoothstep(level - 0.08, level, 1.0 - height) * step(0.01, level);
	float joints = smoothstep(0.34, 0.22, height) * wetness;
	float puddle = max(pool, joints) * flatness;
	// Running water down the walls: thin streaks that slide downward.
	float across = texture(wet_noise, vec2(wpos.x * 1.7 + wpos.z * 1.7, 0.37)).r;
	float flow = texture(wet_noise, vec2(wpos.x * 3.1 + wpos.z * 3.1, wpos.y * 0.35 + TIME * 0.18)).r;
	float sheet = smoothstep(0.62, 0.8, across) * smoothstep(0.45, 0.7, flow) * (1.0 - abs(n.y));

	float wet = wetness * (0.65 + 0.35 * texture(wet_noise, wpos.xy * 0.11 + wpos.zz * 0.11).r);
	// Over the whole city, some walls dirtier, some cleaner.
	float macro = texture(wet_noise, wpos.xy * 0.021 + wpos.zx * 0.017).r;
	albedo *= tint * (0.8 + 0.4 * macro);
	rough *= 0.9 + 0.2 * macro;
	albedo *= mix(1.0, 0.68, wet);              // wet stone darkens
	albedo = mix(albedo, albedo * 0.45, puddle);
	rough = mix(rough, rough * 0.35, wet);
	// Not quite mirrors: rain pocks the puddles, so reflections blur a little.
	rough = mix(rough, 0.09, max(puddle, sheet * 0.8));
	// Standing water is flat but for the rings; running water smooths the
	// bumps a little.
	wn = normalize(mix(wn, n, max(puddle, sheet * 0.5)));
	if (puddle > 0.01) {
		vec2 rip = ripples(wpos.xz / ripple_cell, TIME) + ripples(wpos.xz / ripple_cell * 1.37 + 7.3, TIME * 1.13) * 0.7;
		wn = normalize(wn + vec3(rip.x, 0.0, rip.y) * ripple_strength * puddle);
	}

	ALBEDO = albedo;
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	SPECULAR = 0.5;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
