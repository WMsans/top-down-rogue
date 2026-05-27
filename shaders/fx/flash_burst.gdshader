shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform float core_size : hint_range(0.0, 1.0) = 0.12;
uniform float halo_size : hint_range(0.0, 1.0) = 0.55;
uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 halo_color : source_color = vec4(1.0, 0.95, 0.7, 1.0);

void fragment() {
	vec2 c = (UV - vec2(0.5)) * 2.0;
	float d = length(c);
	float core = smoothstep(core_size, 0.0, d);
	float halo = smoothstep(halo_size, core_size, d);
	vec3 col = core_color.rgb * core + halo_color.rgb * halo;
	float a = clamp(core + halo * 0.7, 0.0, 1.0) * intensity;
	COLOR = vec4(col, a);
}
