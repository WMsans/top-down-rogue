shader_type canvas_item;
// Saltmire FX — dissolve. Burns the sprite away (or back in) with a glowing edge.
// Driven by `progress` 0 (solid) -> 1 (gone). No texture dependency: value noise.

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float edge_width : hint_range(0.0, 0.3) = 0.06;
uniform vec4 edge_color : source_color = vec4(1.0, 0.6, 0.15, 1.0);
uniform float noise_scale = 22.0;

float _hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float _noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = _hash(i);
	float b = _hash(i + vec2(1.0, 0.0));
	float c = _hash(i + vec2(0.0, 1.0));
	float d = _hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float n = _noise(UV * noise_scale);
	if (n < progress) {
		discard;
	}
	if (n < progress + edge_width) {
		tex.rgb = edge_color.rgb;
	}
	COLOR = tex * COLOR;
}
