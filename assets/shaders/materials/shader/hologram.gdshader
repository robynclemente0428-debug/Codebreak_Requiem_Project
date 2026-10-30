shader_type spatial;
// Hologram look for the Multicast copy: see-through cyan body with a bright rim,
// moving scanlines and a little flicker. `fade` takes it from 1 (solid) to 0 (gone).
render_mode unshaded, blend_add, cull_back, depth_draw_never;

uniform vec4 tint : source_color = vec4(0.0, 0.9, 1.0, 1.0);
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float body_alpha = 0.32;
uniform float rim_power = 2.2;
uniform float scan_density = 55.0;
uniform float scan_speed = 2.5;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float scan = 0.65 + 0.35 * sin(world_pos.y * scan_density - TIME * scan_speed * 6.2831);
	float flicker = 0.85 + 0.15 * hash(floor(TIME * 18.0));
	float glow = (body_alpha + rim * 1.7) * scan * flicker * fade;
	ALBEDO = tint.rgb * glow;
	ALPHA = clamp(glow, 0.0, 1.0);
}
