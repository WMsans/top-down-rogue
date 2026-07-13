shader_type canvas_item;
// Saltmire FX — freeze. Desaturates and tints the sprite icy blue.
// `amount` 0 (normal) -> 1 (fully frozen).

uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform vec4 ice_color : source_color = vec4(0.6, 0.85, 1.0, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float g = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	vec3 icy = vec3(g) * ice_color.rgb;
	tex.rgb = mix(tex.rgb, icy, amount);
	COLOR = tex * COLOR;
}
