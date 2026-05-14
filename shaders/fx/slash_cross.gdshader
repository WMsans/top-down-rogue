shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform float thickness : hint_range(0.0, 0.2) = 0.025;
uniform vec4 streak_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec2 c = (UV - vec2(0.5)) * 2.0;
	float h = smoothstep(thickness, 0.0, abs(c.y)) * smoothstep(1.0, 0.05, abs(c.x));
	float v = smoothstep(thickness, 0.0, abs(c.x)) * smoothstep(1.0, 0.05, abs(c.y));
	float s = max(h, v);
	COLOR = vec4(streak_color.rgb, s * intensity * streak_color.a);
}
