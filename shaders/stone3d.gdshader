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

// A tangent-space normal from a two-channel map (z rebuilt: compressed
// normal maps keep only x and y), its bumps scaled.
vec3 unpack(vec2 xy) {
	vec3 t = vec3(xy * 2.0 - 1.0, 0.0);
	t.z = sqrt(max(0.0, 1.0 - dot(t.xy, t.xy)));
	t.xy *= bump;
	return t;
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
	// Gradients taken here, outside the branches below, so mipmapping stays
	// right where faces meet.
	vec2 dx_x = dFdx(uv_x);
	vec2 dy_x = dFdy(uv_x);
	vec2 dx_y = dFdx(uv_y);
	vec2 dy_y = dFdy(uv_y);
	vec2 dx_z = dFdx(uv_z);
	vec2 dy_z = dFdy(uv_z);
	bool up = n.y > 0.0;

	// Each projection only where it shows: on the level's square faces
	// that is one of the three, a third of the texture reads.
	vec3 albedo = vec3(0.0);
	float height = 0.0;
	float rough = 0.0;
	vec3 wsum = vec3(0.0);
	float used = 0.0;
	if (blend.x > 0.02) {
		vec4 a = textureGrad(wall_albedo, uv_x, dx_x, dy_x);
		vec3 t = unpack(textureGrad(wall_normal, uv_x, dx_x, dy_x).xy);
		albedo += a.rgb * blend.x;
		height += a.a * blend.x;
		rough += textureGrad(wall_rough, uv_x, dx_x, dy_x).r * blend.x;
		// Side faces: texture x runs along -z*sx, texture up is +y.
		wsum += vec3(abs(t.z) * n.x, t.y + n.y, -t.x * sx + n.z) * blend.x;
		used += blend.x;
	}
	if (blend.y > 0.02) {
		vec4 a = up ? textureGrad(top_albedo, uv_y, dx_y, dy_y) : textureGrad(wall_albedo, uv_y, dx_y, dy_y);
		vec3 t = unpack(up ? textureGrad(top_normal, uv_y, dx_y, dy_y).xy : textureGrad(wall_normal, uv_y, dx_y, dy_y).xy);
		albedo += a.rgb * blend.y;
		height += a.a * blend.y;
		rough += (up ? textureGrad(top_rough, uv_y, dx_y, dy_y).r : textureGrad(wall_rough, uv_y, dx_y, dy_y).r) * blend.y;
		// Tops: texture x along +x, texture up is -z.
		wsum += vec3(t.x + n.x, abs(t.z) * n.y, -t.y + n.z) * blend.y;
		used += blend.y;
	}
	if (blend.z > 0.02) {
		vec4 a = textureGrad(wall_albedo, uv_z, dx_z, dy_z);
		vec3 t = unpack(textureGrad(wall_normal, uv_z, dx_z, dy_z).xy);
		albedo += a.rgb * blend.z;
		height += a.a * blend.z;
		rough += textureGrad(wall_rough, uv_z, dx_z, dy_z).r * blend.z;
		// Fronts: texture x along +x*sz, texture up is +y.
		wsum += vec3(t.x * sz + n.x, t.y + n.y, abs(t.z) * n.z) * blend.z;
		used += blend.z;
	}
	albedo /= used;
	height /= used;
	rough /= used;
	vec3 wn = normalize(wsum);

	// Water on anything facing up: always in the joints, and where the
	// ground dips (the noise), filling from the lowest parts up.
	float flatness = smoothstep(0.75, 0.95, n.y);
	float pool = 0.0;
	float puddle = 0.0;
	if (flatness > 0.0) {
		float noise_top = texture(wet_noise, wpos.xz * 0.23).r;
		float level = clamp((noise_top - (1.0 - puddles)) * 6.0, 0.0, 1.0);
		pool = smoothstep(level - 0.08, level, 1.0 - height) * step(0.01, level) * flatness;
		float joints = smoothstep(0.34, 0.22, height) * wetness;
		puddle = max(pool, joints * flatness);
	}
	// Running water down the walls: thin streaks that slide downward.
	float sheet = 0.0;
	if (abs(n.y) < 0.6) {
		float across = texture(wet_noise, vec2(wpos.x * 1.7 + wpos.z * 1.7, 0.37)).r;
		float flow = texture(wet_noise, vec2(wpos.x * 3.1 + wpos.z * 3.1, wpos.y * 0.35 + TIME * 0.18)).r;
		sheet = smoothstep(0.62, 0.8, across) * smoothstep(0.45, 0.7, flow) * (1.0 - abs(n.y));
	}

	// How wet, and over the whole city some walls dirtier, some cleaner
	// (one noise read for both).
	vec2 slow = texture(wet_noise, wpos.xy * 0.021 + wpos.zx * 0.017).rg;
	float wet = wetness * (0.65 + 0.35 * slow.g);
	float macro = slow.r;
	albedo *= tint * (0.8 + 0.4 * macro);
	rough *= 0.9 + 0.2 * macro;
	albedo *= mix(1.0, 0.68, wet);              // wet stone darkens
	albedo = mix(albedo, albedo * 0.45, puddle);
	rough = mix(rough, rough * 0.35, wet);
	// Not quite mirrors: rain pocks the puddles, so reflections blur a little.
	rough = mix(rough, 0.09, max(puddle, sheet * 0.8));
	// Standing water is flat but for the rings (in the pools; the joints
	// are too narrow to see them); running water smooths the bumps a little.
	wn = normalize(mix(wn, n, max(puddle, sheet * 0.5)));
	if (pool > 0.01 && ripple_strength > 0.0) {
		vec2 rip = ripples(wpos.xz / ripple_cell, TIME) + ripples(wpos.xz / ripple_cell * 1.37 + 7.3, TIME * 1.13) * 0.7;
		wn = normalize(wn + vec3(rip.x, 0.0, rip.y) * ripple_strength * pool);
	}

	ALBEDO = albedo;
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	SPECULAR = 0.5;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
