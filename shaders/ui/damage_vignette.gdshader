shader_type canvas_item;

uniform float intensity : hint_range(0.0, 2.0) = 0.0;
uniform vec4 vignette_color : source_color = vec4(0.8, 0.05, 0.0, 1.0);
uniform float radius : hint_range(0.1, 1.5) = 0.55;

void fragment() {
	vec2 uv = UV;
	float dist = distance(uv, vec2(0.5));
	float vignette = smoothstep(radius, 0.70, dist);
	COLOR = vec4(vignette_color.rgb, vignette * intensity * vignette_color.a);
}
