shader_type canvas_item;

uniform sampler2D chunk_data : filter_nearest;

void fragment() {
	vec4 data = texture(chunk_data, UV);
	int material = int(round(data.r * 255.0));
	float health = data.g;
	float temperature = data.b;

	if (material == 0) {
		// Air
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
	} else if (material == 1) {
		// Wood — tint toward red with temperature
		vec3 wood_color = vec3(0.55, 0.35, 0.17);
		vec3 hot_color = vec3(0.8, 0.2, 0.1);
		COLOR = vec4(mix(wood_color, hot_color, temperature), 1.0);
	} else if (material == 2) {
		// Fire — orange to red based on health
		vec3 fire_bright = vec3(1.0, 0.6, 0.1);
		vec3 fire_dim = vec3(0.8, 0.1, 0.0);
		COLOR = vec4(mix(fire_dim, fire_bright, health), 1.0);
	} else {
		COLOR = vec4(1.0, 0.0, 1.0, 1.0);
	}
}
