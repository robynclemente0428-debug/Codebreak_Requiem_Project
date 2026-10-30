shader_type spatial;

group_uniforms main;
uniform float intensity : hint_range(0.0, 1.0) = 0.7;
uniform vec4 glitch_color : source_color = vec4(1.0, 0.08, 0.08, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.55;

group_uniforms timing;
uniform float glitch_speed : hint_range(1.0, 30.0) = 10.0;
uniform float glitch_frequency : hint_range(0.0, 1.0) = 0.4;

group_uniforms displacement;
uniform float slice_count : hint_range(4.0, 80.0) = 24.0;
uniform float slice_shift : hint_range(0.0, 0.2) = 0.03;   // in world units (meters), not UV

group_uniforms surface;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);

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

float get_burst() {
	float t = floor(TIME * glitch_speed);
	return step(1.0 - glitch_frequency, hash11(t * 1.37)) * intensity;
}

void vertex() {
	float t = floor(TIME * glitch_speed);
	float burst = get_burst();
	float slice = floor(UV.y * slice_count);
	float slice_active = step(0.72, hash21(vec2(slice, t))) * burst;
	float shift = (hash21(vec2(slice, t + 17.0)) - 0.5) * 2.0 * slice_shift * slice_active;
	VERTEX.x += shift;
}

void fragment() {
	float burst = get_burst();
	vec4 tex = texture(albedo_tex, UV) * albedo_color;
	float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));

	// Red tint
	vec3 tinted = tex.rgb * vec3(1.0, 0.45, 0.45) + glitch_color.rgb * lum * 0.6;
	vec3 col = mix(tex.rgb, tinted, tint_strength * intensity);

	// Scanlines
	float scan = sin(UV.y * 220.0 + TIME * 6.0) * 0.5 + 0.5;
	col *= 1.0 - scan * 0.25 * intensity * burst;

	ALBEDO = col;
	EMISSION = glitch_color.rgb * burst * 0.2;
	ROUGHNESS = 0.8;
}