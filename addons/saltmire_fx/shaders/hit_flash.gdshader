shader_type canvas_item;
// Saltmire FX — hit flash. Blends the sprite toward a solid color (white by default).
// `amount` 0 (normal) -> 1 (full flash). Respects the sprite's alpha silhouette.

uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	tex.rgb = mix(tex.rgb, flash_color.rgb, amount * tex.a);
	COLOR = tex * COLOR;
}
