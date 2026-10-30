shader_type spatial;
render_mode unshaded;

uniform vec4 color_dark : source_color = vec4(0.45, 0.02, 0.0, 1.0);
uniform vec4 color_mid  : source_color = vec4(1.0, 0.3, 0.0, 1.0);
uniform vec4 color_hot  : source_color = vec4(1.0, 0.85, 0.3, 1.0);
uniform float speed = 0.8;
uniform float displace = 0.07;
uniform float emission_strength = 2.5;

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

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	lpos = VERTEX;
	float n = fbm(VERTEX * 2.5 + vec3(0.0, -TIME * speed, 0.0));
	VERTEX += NORMAL * (n - 0.5) * displace * 2.0;
}

void fragment() {
	float n = fbm(lpos * 4.0 + vec3(0.0, -TIME * speed * 1.5, 0.0));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float heat = clamp(n * 1.4 + fres * 0.5 - 0.15, 0.0, 1.0);

	vec3 c = mix(color_dark.rgb, color_mid.rgb, smoothstep(0.0, 0.5, heat));
	c = mix(c, color_hot.rgb, smoothstep(0.5, 1.0, heat));
	ALBEDO = c * emission_strength;
}
