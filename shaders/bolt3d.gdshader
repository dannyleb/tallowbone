// A lightning bolt (scripts/storm.gd builds its ribbons): white-blue and
// brighter than anything, through the fog. Vertex colour alpha thins the
// branches toward their tips.
shader_type spatial;
render_mode unshaded, fog_disabled, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float intensity = 0.0;
uniform vec3 color : source_color = vec3(0.8, 0.86, 1.0);

varying float fade;

void vertex() {
	fade = COLOR.a;
}

void fragment() {
	// Bright core, softer edge across the ribbon.
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	ALBEDO = color * intensity * fade * (0.6 + 3.0 * pow(across, 3.0));
}
