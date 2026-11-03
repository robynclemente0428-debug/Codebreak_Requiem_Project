shader_type spatial;
// An enemy glitching out of existence (GlitchDeath). Replaces the model's materials for its
// last second: keeps its texture and colour, then jitters it in horizontal slices, snaps it to
// a coarsening voxel grid, flickers cyan / magenta and eats it away in world-space blocks.
// `glitch` (0..1, per enemy) drives it all.
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_nearest, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec4 glitch_a : source_color = vec4(0.0, 0.9, 1.0, 1.0);
uniform vec4 glitch_b : source_color = vec4(1.0, 0.15, 0.75, 1.0);
uniform float block_size = 0.14;          // metres: the size of the blocks it breaks into
instance uniform float glitch = 0.0;

varying vec3 world_pos;
varying float band_hit;
varying float base_y;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float tick = floor(TIME * 18.0);
	// Horizontal slices jump sideways, a different few every tick
	float band = floor(w.y * 7.0);
	band_hit = step(1.0 - glitch * 0.75, hash(vec3(band, tick, 3.7)));
	vec2 shove = vec2(hash(vec3(band, tick, 9.1)) - 0.5, hash(vec3(band, tick, 1.3)) - 0.5);
	w.xz += shove * band_hit * (0.15 + 0.45 * glitch);
	// Snapped to a grid that coarsens as it goes: the model pixelates
	float snap = mix(0.0001, block_size * 0.8, smoothstep(0.15, 0.9, glitch));
	w = floor(w / snap + 0.5) * snap;
	world_pos = w;
	base_y = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).y;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
}

void fragment() {
	float g = glitch;
	vec3 cell = floor(world_pos / block_size);
	float tick = floor(TIME * 18.0);
	// Blocks go in a random order, the top a little sooner
	float height_bias = clamp((world_pos.y - base_y) * 0.15, 0.0, 0.2);
	float order = hash(cell) * 0.8 + 0.2 - height_bias;
	float cut = g * 1.3 - 0.15;
	if (order < cut) {
		discard;
	}
	vec4 tex = texture(albedo_tex, UV) * albedo_color;
	// Whole blocks blink in the two glitch colours
	float blink = step(1.0 - g * 0.6, hash(cell + vec3(tick)));
	vec3 tint = mix(glitch_a.rgb, glitch_b.rgb, step(0.5, hash(cell * 1.7 + vec3(tick * 0.5))));
	vec3 col = mix(tex.rgb, tint, clamp(blink + band_hit * 0.6, 0.0, 1.0) * min(g * 2.0, 1.0));
	// Scanlines, and a bright rim on the blocks about to go
	float scan = step(0.82, fract(world_pos.y * 22.0 - TIME * 6.0)) * g;
	float edge = (1.0 - smoothstep(0.0, 0.12, order - cut)) * step(0.05, g);
	ALBEDO = col;
	EMISSION = tint * (edge * 3.0 + scan * 1.2 + blink * 0.8 * g);
	ROUGHNESS = 0.8;
}
