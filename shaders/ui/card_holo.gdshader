shader_type canvas_item;

uniform float tilt_x = 0.0;
uniform float tilt_y = 0.0;
uniform float holo_time = 0.0;
uniform float holo_intensity = 0.0;
uniform float border_width : hint_range(0.0, 0.2) = 0.06;
uniform vec2 card_size = vec2(160.0, 220.0);

void vertex() {
	vec2 center = card_size * 0.5;
	vec2 centered = VERTEX - center;

	// 3D rotation around X axis (tilts top/bottom)
	float cos_x = cos(tilt_x);
	float sin_x = sin(tilt_x);
	// R_x: y' = y*cos_x - z*sin_x, z' = y*sin_x + z*cos_x
	float y1 = centered.y * cos_x;
	float z1 = centered.y * sin_x;
	float x1 = centered.x;

	// 3D rotation around Y axis (tilts left/right)
	float cos_y = cos(tilt_y);
	float sin_y = sin(tilt_y);
	// R_y: x'' = x1*cos_y + z1*sin_y, z'' = -x1*sin_y + z1*cos_y
	float x2 = x1 * cos_y + z1 * sin_y;
	float z2 = -x1 * sin_y + z1 * cos_y;
	float y2 = y1;

	// Perspective projection
	float perspective_distance = 2.0 * card_size.x;
	float scale = perspective_distance / (perspective_distance + z2);

	VERTEX = center + vec2(x2 * scale, y2 * scale);
}

vec3 rainbow(float t) {
	// 1D HSL-like rainbow lookup
	t = fract(t);
	vec3 a = vec3(1.0, 0.0, 0.0);
	vec3 b = vec3(1.0, 1.0, 0.0);
	vec3 c = vec3(0.0, 1.0, 0.0);
	vec3 d = vec3(0.0, 1.0, 1.0);
	vec3 e = vec3(0.0, 0.0, 1.0);
	vec3 f = vec3(1.0, 0.0, 1.0);

	if (t < 0.1667)       return mix(a, b, t / 0.1667);
	else if (t < 0.3333)  return mix(b, c, (t - 0.1667) / 0.1667);
	else if (t < 0.5)     return mix(c, d, (t - 0.3333) / 0.1667);
	else if (t < 0.6667)  return mix(d, e, (t - 0.5) / 0.1667);
	else if (t < 0.8333)  return mix(e, f, (t - 0.6667) / 0.1667);
	else                  return mix(f, a, (t - 0.8333) / 0.1667);
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);

	// Border mask: distance to nearest edge
	float edge_dist = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float border_mask = 1.0 - smoothstep(0.0, border_width, edge_dist);

	// Holographic rainbow sweep — direction follows tilt angle
	float tilt_angle = atan(tilt_y, tilt_x);
	float sweep_pos = UV.x * cos(tilt_angle) + UV.y * sin(tilt_angle) + holo_time;
	vec3 holo_color = rainbow(sweep_pos);

	// Metallic specular highlight on border — tracks tilt direction
	float hl_angle = tilt_angle + 3.14159 * 0.5;
	float border_angle = atan(UV.y - 0.5, UV.x - 0.5);
	float angle_diff = abs(border_angle - hl_angle);
	if (angle_diff > 3.14159) { angle_diff = 6.28318 - angle_diff; }
	float highlight = pow(1.0 - smoothstep(0.0, 0.4, angle_diff), 4.0);

	// Inner dim — darken card center so border pops
	float inner_dim = mix(1.0, 0.88, (1.0 - border_mask) * holo_intensity);

	// Composite
	vec3 holo_overlay = mix(holo_color, vec3(1.0), highlight * 0.6) * border_mask * holo_intensity * 0.7;
	vec3 result = base.rgb * inner_dim + holo_overlay;
	COLOR = vec4(result, base.a);
}
