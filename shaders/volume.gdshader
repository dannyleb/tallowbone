// Shades a flat drawing as if it were round. Each pixel's normal comes from
// how close it is to the silhouette's edge (and a little from the drawing's
// own light and dark), so the scene's 2D lights wrap around it like a solid
// form: lit on the side facing a lamp, falling off toward the other.
// Works on the greybox figures and on illustrated sprites alike.
shader_type canvas_item;

// How round: higher bends the edges away from you more steeply.
uniform float bulge = 2.2;
// How far in from the edge the rounding reaches, in texture pixels.
uniform float reach = 7.0;
// Bumps from the drawing's own shading.
uniform float detail = 0.6;
// Wet sheen: specular strength.
uniform float gloss : hint_range(0.0, 1.0) = 0.25;

float alpha_at(vec2 uv) {
	return texture(TEXTURE, uv).a;
}

float lum_at(vec2 uv) {
	vec4 c = texture(TEXTURE, uv);
	return dot(c.rgb, vec3(0.299, 0.587, 0.114)) * c.a;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 n = vec2(0.0);
	// Edge distance sampled at three reaches, nearest weighted most.
	for (int i = 1; i <= 3; i++) {
		vec2 px = TEXTURE_PIXEL_SIZE * reach * float(i) / 3.0;
		float w = 1.0 / float(i);
		n.x += (alpha_at(UV - vec2(px.x, 0.0)) - alpha_at(UV + vec2(px.x, 0.0))) * w;
		n.y += (alpha_at(UV + vec2(0.0, px.y)) - alpha_at(UV - vec2(0.0, px.y))) * w;
	}
	vec2 d = TEXTURE_PIXEL_SIZE * 1.5;
	n.x += (lum_at(UV - vec2(d.x, 0.0)) - lum_at(UV + vec2(d.x, 0.0))) * detail;
	n.y += (lum_at(UV + vec2(0.0, d.y)) - lum_at(UV - vec2(0.0, d.y))) * detail;
	// Green up, like the tiles' normal maps.
	vec3 normal = normalize(vec3(n * bulge, 1.0));
	NORMAL_MAP = normal * 0.5 + 0.5;
	SPECULAR_SHININESS = vec4(vec3(gloss), gloss);
	COLOR = c * COLOR;
}
