shader_type canvas_item;
// Saltmire FX — outline. Adds a crisp border around the sprite's opaque pixels.
// 8-tap alpha dilation; `outline_width` in pixels.

uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_width : hint_range(0.0, 8.0) = 1.0;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	vec2 ts = TEXTURE_PIXEL_SIZE * outline_width;
	float a = 0.0;
	a = max(a, texture(TEXTURE, UV + vec2( ts.x, 0.0)).a);
	a = max(a, texture(TEXTURE, UV + vec2(-ts.x, 0.0)).a);
	a = max(a, texture(TEXTURE, UV + vec2(0.0,  ts.y)).a);
	a = max(a, texture(TEXTURE, UV + vec2(0.0, -ts.y)).a);
	a = max(a, texture(TEXTURE, UV + vec2( ts.x,  ts.y)).a);
	a = max(a, texture(TEXTURE, UV + vec2(-ts.x,  ts.y)).a);
	a = max(a, texture(TEXTURE, UV + vec2( ts.x, -ts.y)).a);
	a = max(a, texture(TEXTURE, UV + vec2(-ts.x, -ts.y)).a);
	float outline = clamp(min(a, 1.0) - col.a, 0.0, 1.0);
	vec4 result = mix(col, outline_color, outline);
	COLOR = result * COLOR;
}
