shader_type canvas_item;

uniform float radius : hint_range(0.0, 1.0) = 0.0;
uniform float thickness : hint_range(0.0, 0.5) = 0.08;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform vec4 ring_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float d = length(centered) * 2.0;
	float ring = smoothstep(thickness, 0.0, abs(d - radius));
	COLOR = vec4(ring_color.rgb, ring * alpha * ring_color.a);
}
