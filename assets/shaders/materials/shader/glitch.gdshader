// Glitch effect for character models (Godot 4.x, spatial shader)
// Features: bursty slice displacement, vertex jitter, RGB channel split,
// scanlines, glitch-colored emission on displaced slices, blocky dissolve.
// Apply as a material override / surface material on your character mesh.

shader_type spatial;
render_mode cull_disabled;

group_uniforms Surface;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

group_uniforms Glitch_Timing;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;       // master strength (animate this from code for hit/spawn effects)
uniform float glitch_speed : hint_range(1.0, 60.0) = 14.0;  // how fast the pattern re-rolls (steps per second)
uniform float burst_chance : hint_range(0.0, 1.0) = 0.25;   // chance each step is a glitch burst
uniform float constant_glitch : hint_range(0.0, 1.0) = 0.05; // low-level glitch between bursts

group_uniforms Glitch_Geometry;
uniform float slice_count : hint_range(2.0, 80.0) = 24.0;      // horizontal slices along model Y
uniform float slice_displacement : hint_range(0.0, 1.0) = 0.15; // max sideways shift (model units)
uniform float slice_active_chance : hint_range(0.0, 1.0) = 0.35;
uniform float vertex_jitter : hint_range(0.0, 0.2) = 0.02;     // random push along normals

group_uniforms Glitch_Color;
uniform float rgb_split : hint_range(0.0, 0.1) = 0.02;         // UV offset per channel
uniform vec4 glitch_color_a : source_color = vec4(0.0, 1.0, 0.9, 1.0);
uniform vec4 glitch_color_b : source_color = vec4(1.0, 0.0, 0.6, 1.0);
uniform float glitch_emission : hint_range(0.0, 8.0) = 2.0;

group_uniforms Scanlines_And_Dissolve;
uniform float scanline_density : hint_range(10.0, 400.0) = 120.0;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.25;
uniform float scanline_scroll : hint_range(-10.0, 10.0) = 1.5;
uniform float dissolve_blocks : hint_range(2.0, 64.0) = 16.0;
uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.12;   // fraction of UV blocks dropped during bursts

varying float v_local_y;
varying float v_slice_active;
varying float v_slice_rand;
varying float v_burst;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// 0..1 strength for the current time step: a burst or a faint idle glitch.
float glitch_amount(float t_step) {
	float burst = step(1.0 - burst_chance, hash11(t_step * 1.37 + 7.0));
	return clamp(max(burst, constant_glitch), 0.0, 1.0) * intensity;
}

void vertex() {
	float t_step = floor(TIME * glitch_speed);
	float amt = glitch_amount(t_step);

	float slice = floor(VERTEX.y * slice_count);
	float r_active = hash11(slice * 3.1 + t_step * 1.7);
	float r_offset = hash11(slice * 5.3 + t_step * 2.9) * 2.0 - 1.0;

	float active = step(1.0 - slice_active_chance, r_active) * amt;

	// Slice shift (model space X)
	VERTEX.x += r_offset * slice_displacement * active;

	// Random per-vertex push along the normal
	float j = hash21(VERTEX.xy * 91.7 + t_step) - 0.5;
	VERTEX += NORMAL * j * vertex_jitter * amt;

	v_local_y = VERTEX.y;
	v_slice_active = active;
	v_slice_rand = r_offset;
	v_burst = amt;
}

void fragment() {
	float t_step = floor(TIME * glitch_speed);

	// RGB split: sample each channel with a different horizontal UV offset.
	float split = rgb_split * v_burst * (0.5 + abs(v_slice_rand)) * (1.0 + v_slice_active);
	vec2 off = vec2(split, 0.0);
	vec3 col;
	col.r = texture(albedo_texture, UV + off).r;
	col.g = texture(albedo_texture, UV).g;
	col.b = texture(albedo_texture, UV - off).b;
	col *= albedo_color.rgb;

	// Scanlines (scroll along model Y)
	float scan = sin((v_local_y * scanline_density + TIME * scanline_scroll * scanline_density * 0.1) * 6.2831853);
	scan = smoothstep(-0.2, 1.0, scan);
	col *= 1.0 - scanline_strength * (1.0 - scan) * (0.4 + 0.6 * v_burst);

	// Blocky dissolve in UV space during bursts
	vec2 block = floor(UV * dissolve_blocks);
	float block_rand = hash21(block + t_step * 0.37);
	if (block_rand < dissolve_amount * v_burst) {
		discard;
	}

	// Glitch-colored emission on displaced slices
	vec3 glitch_col = mix(glitch_color_a.rgb, glitch_color_b.rgb, step(0.0, v_slice_rand));
	vec3 emit = glitch_col * glitch_emission * v_slice_active;

	// Tint the surface toward the glitch color on active slices
	col = mix(col, col * glitch_col, v_slice_active * 0.5);

	ALBEDO = col;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = emit;
}
