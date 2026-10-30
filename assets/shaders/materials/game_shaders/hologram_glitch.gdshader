shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

// ---------- Look ----------
group_uniforms look;
uniform vec4 holo_color : source_color = vec4(0.1, 0.55, 1.0, 1.0);
uniform vec4 glitch_tint : source_color = vec4(0.6, 1.0, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 5.0) = 1.6;
uniform float base_alpha : hint_range(0.0, 1.0) = 0.25;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float tex_mix : hint_range(0.0, 1.0) = 0.0;

// ---------- Fresnel rim ----------
group_uniforms rim;
uniform float fresnel_power : hint_range(0.1, 8.0) = 2.5;
uniform float fresnel_strength : hint_range(0.0, 3.0) = 1.2;

// ---------- Scanlines ----------
group_uniforms scanlines;
uniform float scan_density : hint_range(1.0, 200.0) = 60.0;
uniform float scan_speed : hint_range(-10.0, 10.0) = 1.5;
uniform float scan_strength : hint_range(0.0, 1.0) = 0.5;
uniform float sweep_speed : hint_range(0.0, 5.0) = 0.6;   // bright band travelling upward
uniform float sweep_width : hint_range(0.01, 1.0) = 0.15;
uniform float sweep_strength : hint_range(0.0, 3.0) = 1.0;
uniform float height_min = -1.0;  // local-space Y range of your mesh (for the sweep)
uniform float height_max = 1.0;

// ---------- Glitch ----------
group_uniforms glitch;
uniform float glitch_strength : hint_range(0.0, 1.0) = 0.12;  // max horizontal shift
uniform float glitch_chance : hint_range(0.0, 1.0) = 0.15;    // chance a band shifts
uniform float glitch_speed : hint_range(0.0, 30.0) = 8.0;     // steps per second
uniform float band_density : hint_range(1.0, 50.0) = 12.0;    // bands per unit of height
uniform float burst_chance : hint_range(0.0, 1.0) = 0.25;     // chance of a global burst per step

// ---------- Flicker ----------
group_uniforms flicker;
uniform float flicker_speed : hint_range(0.0, 60.0) = 18.0;
uniform float flicker_amount : hint_range(0.0, 1.0) = 0.25;

varying vec3 v_world_pos;
varying float v_glitch;
varying float v_height01;

float hash11(float n) {
	return fract(sin(n * 127.1) * 43758.5453123);
}

void vertex() {
	float step_t = floor(TIME * glitch_speed);

	// Glitches only happen in bursts, so the effect comes and goes
	float burst = step(1.0 - burst_chance, hash11(step_t * 7.31));

	float band = floor(VERTEX.y * band_density);
	float r = hash11(band * 1.7 + step_t * 13.7);
	float active_band = step(1.0 - glitch_chance, r) * burst;

	float shift = (hash11(band * 3.1 + step_t * 5.3) - 0.5) * 2.0 * glitch_strength * active_band;
	VERTEX.x += shift;

	v_glitch = active_band;
	v_height01 = clamp((VERTEX.y - height_min) / max(height_max - height_min, 0.0001), 0.0, 1.0);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Fresnel rim
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - ndv, fresnel_power) * fresnel_strength;

	// Scanlines (world-space so they stay put while the mesh animates)
	float scan = 0.5 + 0.5 * sin(v_world_pos.y * scan_density - TIME * scan_speed);
	scan = mix(1.0, scan, scan_strength);

	// Bright sweep travelling up the mesh
	float sweep_pos = fract(TIME * sweep_speed);
	float d = abs(v_height01 - sweep_pos);
	float sweep = smoothstep(sweep_width, 0.0, d) * sweep_strength;

	// Flicker
	float flick = 1.0 - flicker_amount * hash11(floor(TIME * flicker_speed));

	// Optional texture
	vec3 tex = texture(albedo_tex, UV).rgb;
	vec3 base = mix(holo_color.rgb, holo_color.rgb * tex, tex_mix);

	// Combine
	vec3 col = base * (base_alpha + scan * 0.5);
	col += holo_color.rgb * fresnel;
	col += holo_color.rgb * sweep;
	col = mix(col, glitch_tint.rgb * (0.6 + fresnel), v_glitch * 0.6);

	ALBEDO = col * intensity * flick;
	ALPHA = clamp(base_alpha + fresnel + sweep + v_glitch * 0.3, 0.0, 1.0) * flick * scan;
}
