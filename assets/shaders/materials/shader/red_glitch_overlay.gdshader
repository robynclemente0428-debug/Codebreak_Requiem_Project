// Red glitch OVERLAY (Godot 4.x spatial shader) - put it in a MeshInstance3D's
// "Material Overlay" slot. The model's own material and texture stay visible underneath;
// this pass only ADDS light on top:
//   - a red fresnel rim that flickers
//   - scrolling scanlines
//   - bursts where horizontal slices of the model tear sideways and flash red/magenta
//     (the overlay copy is displaced, so the torn slice looks like a red ghost of the body)
//   - occasional blocky "corruption" squares
// Everything is additive and unshaded, so it reads in dark dungeons and never darkens the model.

shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;

group_uniforms Colors;
uniform vec4 glitch_color : source_color = vec4(1.0, 0.08, 0.12, 1.0);    // main red
uniform vec4 accent_color : source_color = vec4(1.0, 0.0, 0.55, 1.0);     // magenta on torn slices
uniform float strength : hint_range(0.0, 4.0) = 1.0;                       // master brightness

group_uniforms Rim;
uniform float rim_power : hint_range(0.5, 8.0) = 2.5;
uniform float rim_strength : hint_range(0.0, 4.0) = 1.2;

group_uniforms Timing;
uniform float glitch_speed : hint_range(1.0, 60.0) = 12.0;   // pattern re-rolls per second
uniform float burst_chance : hint_range(0.0, 1.0) = 0.3;     // share of steps that are bursts
uniform float idle_glitch : hint_range(0.0, 1.0) = 0.12;     // faint glitching between bursts

group_uniforms Slices;
uniform float slice_count : hint_range(2.0, 80.0) = 18.0;     // slices along the model's height
uniform float slice_shift : hint_range(0.0, 1.0) = 0.18;      // sideways tear, model units
uniform float slice_chance : hint_range(0.0, 1.0) = 0.3;
uniform float slice_glow : hint_range(0.0, 6.0) = 2.5;

group_uniforms Scanlines_And_Blocks;
uniform float scan_density : hint_range(5.0, 300.0) = 60.0;
uniform float scan_strength : hint_range(0.0, 2.0) = 0.35;
uniform float scan_speed : hint_range(-10.0, 10.0) = 2.0;
uniform float block_size : hint_range(0.02, 1.0) = 0.18;      // corruption squares, model units
uniform float block_chance : hint_range(0.0, 1.0) = 0.06;

varying vec3 v_pos;
varying float v_active;
varying float v_side;
varying float v_burst;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	float t = floor(TIME * glitch_speed);
	float burst = step(1.0 - burst_chance, hash11(t * 1.37 + 7.0));
	float amt = max(burst, idle_glitch);

	float slice = floor(VERTEX.y * slice_count);
	float pick = hash11(slice * 3.1 + t * 1.7);
	float side = hash11(slice * 5.3 + t * 2.9) * 2.0 - 1.0;
	float active = step(1.0 - slice_chance, pick) * amt;

	VERTEX.x += side * slice_shift * active;
	VERTEX += NORMAL * 0.004;                 // sit just above the surface, avoids z-fighting

	v_pos = VERTEX;
	v_active = active;
	v_side = side;
	v_burst = amt;
}

void fragment() {
	float t = floor(TIME * glitch_speed);

	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float flicker = 0.75 + 0.25 * hash11(t * 0.71 + 3.0);
	vec3 col = glitch_color.rgb * fres * rim_strength * flicker;

	float scan = 0.5 + 0.5 * sin((v_pos.y * scan_density + TIME * scan_speed * 6.0) * 6.2831853);
	col += glitch_color.rgb * smoothstep(0.85, 1.0, scan) * scan_strength * (0.4 + 0.6 * v_burst);

	vec3 torn = mix(glitch_color.rgb, accent_color.rgb, step(0.0, v_side));
	col += torn * slice_glow * v_active;

	vec3 cell = floor(v_pos / block_size);
	float blk = step(1.0 - block_chance * v_burst, hash31(cell + vec3(t * 0.37)));
	col += accent_color.rgb * blk * 1.5;

	ALBEDO = col * strength;
}
