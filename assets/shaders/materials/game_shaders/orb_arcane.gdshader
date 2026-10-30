shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform vec4 color_a : source_color = vec4(0.1, 0.4, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(0.6, 1.0, 1.0, 1.0);
uniform float rim_power = 2.5;
uniform float band_scale = 9.0;
uniform float band_strength = 0.6;
uniform float speed = 1.0;
uniform float intensity = 2.0;
uniform float base_alpha = 0.15;

varying vec3 lpos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i + vec3(0,0,0)), hash(i + vec3(1,0,0)), f.x),
			mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
			mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y),
		f.z);
}

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float n = noise(lpos * 3.0 + vec3(0.0, TIME * speed * 0.5, 0.0));
	float bands = 0.5 + 0.5 * sin(lpos.y * band_scale + n * 6.0 - TIME * speed * 3.0);
	bands = pow(bands, 3.0) * band_strength;

	vec3 c = mix(color_a.rgb, color_b.rgb, clamp(bands + fres * 0.5, 0.0, 1.0));
	ALBEDO = c * intensity;
	ALPHA = clamp(fres + bands + base_alpha, 0.0, 1.0);
}
