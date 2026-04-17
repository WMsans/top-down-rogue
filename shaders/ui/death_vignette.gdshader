shader_type canvas_item;

uniform float pulse_speed : hint_range(0.1, 5.0) = 0.67;
uniform float vignette_intensity : hint_range(0.0, 2.0) = 1.2;
uniform vec4 vignette_color : source_color = vec4(0.5, 0.0, 0.0, 1.0);

void fragment() {
	vec2 uv = UV;
	float dist = distance(uv, vec2(0.5));
	float vignette = smoothstep(0.3, 0.9, dist);

	float pulse = 0.5 + 0.5 * sin(TIME * pulse_speed * 6.283);
	float red_mix = vignette * vignette_intensity * (0.6 + 0.4 * pulse);

	vec4 base = texture(TEXTURE, UV);
	vec3 final_color = mix(base.rgb, vignette_color.rgb, red_mix);
	COLOR = vec4(final_color, base.a * vignette);
}