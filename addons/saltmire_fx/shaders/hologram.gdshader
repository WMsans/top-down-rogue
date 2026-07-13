shader_type canvas_item;
// Saltmire FX — hologram. Sci-fi tint with moving scanlines and a subtle flicker.
// `amount` 0 (normal) -> 1 (full holo). Animated via TIME (needs no per-frame code).

uniform vec4 holo_color : source_color = vec4(0.4, 0.8, 1.0, 1.0);
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform float scan_density = 200.0;
uniform float scan_speed = 6.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float scan = sin((UV.y + TIME * 0.1) * scan_density) * 0.15 + 0.85;
	vec3 holo = holo_color.rgb * scan;
	tex.rgb = mix(tex.rgb, holo, amount);
	float flicker = 0.75 + 0.25 * sin(TIME * scan_speed);
	tex.a *= mix(1.0, flicker, amount);
	COLOR = tex * COLOR;
}
