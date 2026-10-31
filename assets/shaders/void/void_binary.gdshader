shader_type spatial;
// The void behind Act I: black space with a faint nebula, a few stars, and two layers of
// falling binary (pixel-art 0s and 1s that flip now and then). Drawn on the quad VoidBackdrop
// keeps at the far end of the camera, so everything here is in screen pixels: the digits stay
// crisp at the game's low resolution whatever the zoom. `scroll` is set by VoidBackdrop from the
// camera's movement, so the void drifts a little as you walk, like something very far away.
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 void_color : source_color = vec4(0.006, 0.0, 0.02, 1.0);
uniform vec4 nebula_a : source_color = vec4(0.08, 0.12, 0.55, 1.0);   // deep blue
uniform vec4 nebula_b : source_color = vec4(0.45, 0.10, 0.80, 1.0);   // violet
uniform float nebula_strength = 0.35;
uniform vec4 digit_color : source_color = vec4(0.45, 0.25, 1.0, 1.0);
uniform float digit_strength = 0.9;
uniform float digit_density = 0.10;     // share of cells with a digit in them (near layer)
uniform float drift_speed = 6.0;        // pixels per second, downward (near layer)
uniform float flip_rate = 0.4;          // how often a digit may change, per second
uniform float star_density = 0.004;
uniform vec2 scroll = vec2(0.0);        // set by VoidBackdrop

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

// 3x5 bitmaps, read top row first:  0 = 111 101 101 101 111   1 = 010 110 010 010 111
float glyph(int digit, ivec2 g) {
	int bits = digit == 0 ? 31599 : 11415;
	int idx = (4 - g.y) * 3 + (2 - g.x);
	return float((bits >> idx) & 1);
}

// One layer of falling digits. px = size of one glyph pixel in screen pixels.
float digits(vec2 p, float px, float speed, float density, float t) {
	p.y -= t * speed;
	float cell = px * 7.0;                          // 3x5 glyph with a margin, in a square cell
	vec2 id = floor(p / cell);
	vec2 f = p - id * cell;
	float h = hash(id);
	if (h > density) {
		return 0.0;
	}
	ivec2 g = ivec2(floor(f / px)) - ivec2(2, 1);
	if (g.x < 0 || g.x > 2 || g.y < 0 || g.y > 4) {
		return 0.0;
	}
	int d = int(step(0.5, hash(id + floor(t * flip_rate + h * 10.0))));
	float pulse = 0.4 + 0.6 * (0.5 + 0.5 * sin(t * 1.7 + h * 40.0));
	return glyph(d, g) * pulse;
}

void fragment() {
	vec2 p = FRAGCOORD.xy + scroll;
	float t = TIME;
	vec3 col = void_color.rgb;

	float n = fbm(p * 0.006 + vec2(t * 0.01, 0.0));
	float hue = fbm(p * 0.004 + 11.0);
	col += mix(nebula_a.rgb, nebula_b.rgb, hue) * smoothstep(0.45, 0.85, n) * nebula_strength;

	float s = hash(floor(p / 2.0) + 3.7);
	if (s < star_density) {
		col += vec3(0.85, 0.8, 1.0) * (0.5 + 0.5 * sin(t * 2.0 + s * 600.0));
	}

	// Far layer first (small, slow, dim), then the near one (bigger, brighter)
	col += digit_color.rgb * digits(p + 300.0, 1.0, drift_speed * 0.25, digit_density * 0.7, t) * digit_strength * 0.35;
	col += digit_color.rgb * digits(p, 2.0, drift_speed, digit_density, t) * digit_strength;

	ALBEDO = col;
}
