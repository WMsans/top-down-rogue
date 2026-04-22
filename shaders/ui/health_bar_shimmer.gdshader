shader_type canvas_item;

uniform float shimmer_speed : hint_range(0.1, 5.0) = 0.5;
uniform float shimmer_width : hint_range(0.02, 0.3) = 0.08;
uniform float shimmer_brightness : hint_range(0.0, 1.0) = 0.4;

void fragment() {
	float t = fract(TIME * shimmer_speed);
	float shimmer_pos = t;

	float dist = abs(UV.x - shimmer_pos);
	if (dist > 0.5) {
		dist = 1.0 - dist;
	}

	float shimmer = smoothstep(shimmer_width, 0.0, dist);
	float gradient = mix(0.8, 1.0, UV.x);
	vec3 base_color = mix(vec3(0.8, 0.2, 0.2), vec3(1.0, 0.42, 0.208), UV.x);
	vec3 shimmer_color = base_color + vec3(shimmer * shimmer_brightness);

	COLOR = vec4(shimmer_color * gradient, COLOR.a * texture(TEXTURE, UV).a);
}