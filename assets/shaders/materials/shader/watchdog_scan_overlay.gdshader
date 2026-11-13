// Watchdog scan OVERLAY (Godot 4.x spatial shader) - the Watchdog's "Material Overlay" slot
// (WatchdogLook). It ADDS light on top of the gunmetal override, and reads nothing like the
// Loop Hound's red glitch:
//   - a cold cyan-white fresnel rim
//   - one bright scan band sweeping up the body, like a monitor checking it
//   - fine horizontal register lines inside the rim
//   - `beat`: a flash each time a hit lands (WatchdogLock pets it)
//   - `alarm`: 0 calm .. 1 about to reset; the colour runs to red and the rim pulses faster
// Additive and unshaded, so it never darkens the model.

shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform vec4 scan_color : source_color = vec4(0.45, 0.95, 1.0, 1.0);
uniform vec4 alarm_color : source_color = vec4(1.0, 0.22, 0.18, 1.0);
uniform float alarm : hint_range(0.0, 1.0) = 0.0;
uniform float beat : hint_range(0.0, 1.0) = 0.0;
uniform float rim_power = 2.4;
uniform float rim_strength = 1.1;
uniform float band_speed = 0.7;
uniform float band_width = 0.06;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	// one band sweeping upwards every 1/band_speed seconds
	float phase = fract(world_pos.y * 0.55 - TIME * band_speed);
	float band = smoothstep(band_width, 0.0, abs(phase - 0.5));
	// thin register lines, only where the rim is
	float lines = step(0.55, fract(world_pos.y * 24.0)) * 0.35 * rim;
	// faster pulse as the alarm rises
	float pulse = 0.85 + 0.15 * sin(TIME * mix(3.0, 16.0, alarm));
	vec3 col = mix(scan_color.rgb, alarm_color.rgb, alarm);
	float a = rim * rim_strength * pulse * (1.0 + beat * 1.6) + band * 0.55 + lines;
	ALBEDO = col * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
