shader_type spatial;
// The Shoot bullet (ShootProjectile): one QuadMesh, stretched along the flight path and turned
// to face the camera round that line, so it reads the same from any angle. Bright head at the
// bullet, fading into a tail behind it. `tint` is per bullet (gold for players, red for enemies).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

instance uniform vec4 tint : source_color = vec4(1.0, 0.85, 0.4, 1.0);
uniform float width = 0.2;                // metres across
uniform float tail = 1.0;                 // metres from the head back to the tail's end

void vertex() {
	vec3 head = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 along = normalize((MODEL_MATRIX * vec4(0.0, 0.0, -1.0, 0.0)).xyz);   // flight direction
	vec3 to_camera = normalize(INV_VIEW_MATRIX[2].xyz);   // the camera's back: fine for ortho too
	vec3 side = cross(along, to_camera);
	side = length(side) < 0.001 ? vec3(1.0, 0.0, 0.0) : normalize(side);
	// The QuadMesh is 1 x 1: x across, y from tail (-0.5) to head (+0.5)
	vec3 world = head + side * VERTEX.x * width + along * (VERTEX.y - 0.5) * tail;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float across = abs(UV.x - 0.5) * 2.0;          // 0 in the middle, 1 at the edges
	float t = UV.y;                                // 0 at the head, 1 at the tail
	float core = 1.0 - smoothstep(0.0, 1.0, across);
	float fade = pow(1.0 - t, 1.6);
	float a = core * fade;
	vec3 col = mix(tint.rgb, vec3(1.0), pow(core, 5.0) * (1.0 - t));   // white-hot middle
	ALBEDO = col * a * 2.5;
	ALPHA = a;
}
