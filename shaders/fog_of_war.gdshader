shader_type canvas_item;

uniform vec4 fog_color : source_color = vec4(0.02, 0.01, 0.04, 1.0);
uniform sampler2D fog_map : hint_default_black;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

void fragment() {
	float fog_mask = texture(fog_map, UV).r;
	if (fog_mask < 0.005) {
		COLOR = vec4(0.0);
	} else {
		vec4 terrain = texture(screen_texture, SCREEN_UV);
		COLOR.rgb = mix(terrain.rgb, fog_color.rgb, fog_mask);
		COLOR.a = 1.0;
	}
}
