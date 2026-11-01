shader_type spatial;
// The void the convoy barge travels through: two tiling layers scrolling at different
// speeds (parallax), with a gentle twinkle. Put it on a large flat plane under and around
// the ship. Unshaded, so scene lighting doesn't touch it.
//
// `travel` is how far the ship has gone. ConvoyVoid (convoy_void.gd) adds speed x delta to
// it every frame, so changing the speed (a warp jump, docking) never makes the pattern jump.
//
// screen_space: for a town's backdrop (GameArea.backdrop, drawn by VoidBackdrop on a quad that
// fills the view) instead of a plane. The pattern is then measured in screen heights, so stars
// stay round on a wide screen, and `scroll` (set by VoidBackdrop, in pixels) lets the void drift
// a little as you walk. ConvoyMotion drives `travel` there.
render_mode unshaded, cull_disabled;

uniform sampler2D far_tex : source_color, repeat_enable, filter_nearest;
uniform sampler2D near_tex : source_color, repeat_enable, filter_nearest;
uniform float travel = 0.0;
uniform vec2 direction = vec2(-1.0, 0.0);      // which way the void flows (opposite the ship's heading)
uniform float far_tiling = 3.0;                // repeats across the plane
uniform float near_tiling = 2.0;
uniform float far_rate = 0.25;                 // far layer moves slower: depth
uniform float near_rate = 1.0;
uniform float twinkle = 0.3;                   // 0 = steady stars
uniform float stretch = 0.0;                   // 0..1: smear the near layer along the flow (warp)
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool screen_space = false;
uniform vec2 view_px = vec2(640.0, 360.0);     // set by VoidBackdrop
uniform vec2 scroll = vec2(0.0);               // set by VoidBackdrop, in pixels

void fragment() {
	vec2 flow = normalize(direction);
	vec2 uv = UV;
	if (screen_space) {
		uv = (UV * view_px + scroll) / view_px.y;
	}
	vec3 far = texture(far_tex, uv * far_tiling + flow * travel * far_rate).rgb;

	vec2 near_uv = uv * near_tiling + flow * travel * near_rate;
	vec4 near = texture(near_tex, near_uv);
	// Warp: a few samples back along the flow turn stars into streaks
	if (stretch > 0.001) {
		for (int i = 1; i <= 6; i++) {
			vec4 s = texture(near_tex, near_uv - flow * stretch * 0.02 * float(i));
			near = max(near, s * (1.0 - float(i) / 7.0));
		}
	}
	float tw = 1.0 - twinkle + twinkle * sin(TIME * 2.7 + dot(uv, vec2(53.0, 91.0)));
	ALBEDO = (far + near.rgb * near.a * tw) * tint.rgb;
}
