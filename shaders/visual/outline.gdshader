shader_type canvas_item;

uniform float outline_width : hint_range(0.0, 10.0) = 0.0;
uniform Color outline_color : source_color = Color(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 base_color = texture(TEXTURE, UV);

	if (outline_width > 0.0) {
		vec2 pixel_size = TEXTURE_PIXEL_SIZE * outline_width;
		float max_alpha = 0.0;

		max_alpha = max(max_alpha, texture(TEXTURE, UV + vec2(pixel_size.x, 0.0)).a);
		max_alpha = max(max_alpha, texture(TEXTURE, UV - vec2(pixel_size.x, 0.0)).a);
		max_alpha = max(max_alpha, texture(TEXTURE, UV + vec2(0.0, pixel_size.y)).a);
		max_alpha = max(max_alpha, texture(TEXTURE, UV - vec2(0.0, pixel_size.y)).a);
		max_alpha = max(max_alpha, texture(TEXTURE, UV + vec2(pixel_size.x, pixel_size.y) * 0.7071).a);
		max_alpha = max(max_alpha, texture(TEXTURE, UV - vec2(pixel_size.x, pixel_size.y) * 0.7071).a);
		max_alpha = max(max_alpha, texture(TEXTURE, UV + vec2(pixel_size.x, -pixel_size.y) * 0.7071).a);
		max_alpha = max(max_alpha, texture(TEXTURE, UV - vec2(pixel_size.x, -pixel_size.y) * 0.7071).a);

		vec4 outline = vec4(outline_color.rgb, max_alpha * outline_color.a) * (1.0 - base_color.a);
		COLOR = base_color + outline;
	} else {
		COLOR = base_color;
	}
}