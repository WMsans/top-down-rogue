shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec2 axis = vec2(1.0, 0.0);

void fragment() {
	vec2 offset = axis * strength * 0.012;
	float r = texture(screen_tex, SCREEN_UV - offset).r;
	float g = texture(screen_tex, SCREEN_UV).g;
	float b = texture(screen_tex, SCREEN_UV + offset).b;
	COLOR = vec4(r, g, b, strength);
}
