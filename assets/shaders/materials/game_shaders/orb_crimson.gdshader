shader_type spatial;
render_mode unshaded;
// Blood orb: slick dark-red surface, glowing veins that flare with a double heartbeat.

uniform vec4 color_dark  : source_color = vec4(0.10, 0.0, 0.015, 1.0);
uniform vec4 color_blood : source_color = vec4(0.65, 0.02, 0.05, 1.0);
uniform vec4 color_glow  : source_color = vec4(1.0, 0.25, 0.18, 1.0);
uniform float beat_speed = 4.0;
uniform float intensity = 1.6;

varying vec3 lpos;

float orb_hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float orb_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(orb_hash(i + vec3(0,0,0)), orb_hash(i + vec3(1,0,0)), f.x),
			mix(orb_hash(i + vec3(0,1,0)), orb_hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(orb_hash(i + vec3(0,0,1)), orb_hash(i + vec3(1,0,1)), f.x),
			mix(orb_hash(i + vec3(0,1,1)), orb_hash(i + vec3(1,1,1)), f.x), f.y),
		f.z);
}

float orb_fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * orb_noise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}

float orb_fresnel(vec3 n, vec3 v, float p) {
	return pow(1.0 - clamp(dot(n, v), 0.0, 1.0), p);
}

float orb_beat(float t) {
	float a = pow(max(sin(t), 0.0), 8.0);
	float b = 0.6 * pow(max(sin(t - 1.1), 0.0), 8.0);
	return clamp(a + b, 0.0, 1.0);
}

void vertex() {
	lpos = VERTEX;
	float b = orb_beat(TIME * beat_speed);
	float n = orb_fbm(VERTEX * 2.5 + vec3(0.0, TIME * 0.2, 0.0));
	VERTEX += NORMAL * (0.025 * b + (n - 0.5) * 0.03);
}

void fragment() {
	float b = orb_beat(TIME * beat_speed);
	float n = orb_fbm(lpos * 3.5 + vec3(0.0, TIME * 0.15, 0.0));
	float n2 = orb_fbm(lpos * 7.0 - vec3(TIME * 0.1, 0.0, 0.0) + 5.0);
	float vein = 1.0 - smoothstep(0.0, 0.07, abs(n - 0.5));
	float vein2 = 1.0 - smoothstep(0.0, 0.05, abs(n2 - 0.5));

	vec3 c = mix(color_dark.rgb, color_blood.rgb, smoothstep(0.2, 0.8, n));
	c += color_glow.rgb * (vein + vein2 * 0.6) * (0.4 + 1.6 * b);
	c += color_blood.rgb * orb_fresnel(NORMAL, VIEW, 3.0) * 1.2;

	vec3 L = normalize(vec3(-0.4, 0.8, 0.6));
	vec3 H = normalize(L + VIEW);
	c += vec3(1.0, 0.7, 0.7) * pow(max(dot(NORMAL, H), 0.0), 90.0);

	ALBEDO = c * intensity;
}
