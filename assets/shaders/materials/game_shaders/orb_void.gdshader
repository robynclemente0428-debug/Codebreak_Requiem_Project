shader_type spatial;
render_mode unshaded;

uniform vec4 rim_color  : source_color = vec4(0.55, 0.1, 1.0, 1.0);
uniform vec4 vein_color : source_color = vec4(0.9, 0.5, 1.0, 1.0);
uniform float rim_power = 3.0;
uniform float vein_width = 0.06;
uniform float speed = 0.4;

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
}

void fragment() {
	float n = fbm(lpos * 5.0 + vec3(TIME * speed, TIME * speed * 0.5, 0.0));
	float vein = 1.0 - smoothstep(0.0, vein_width, abs(n - 0.5));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float pulse = 0.8 + 0.2 * sin(TIME * 3.0);

	vec3 c = vec3(0.01, 0.0, 0.03);
	c += rim_color.rgb * fres * 2.5;
	c += vein_color.rgb * vein * 3.0 * pulse;
	ALBEDO = c;
}
