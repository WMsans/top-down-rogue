shader_type canvas_item;

uniform bool glow_enabled = false;
uniform vec4 glow_color : source_color = vec4(1.0, 0.42, 0.208, 1.0);
uniform float glow_width : hint_range(0.0, 0.1) = 0.02;
uniform float glow_intensity : hint_range(0.0, 1.0) = 0.6;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	if (!glow_enabled) {
		COLOR = base;
		return;
	}

	float edge_dist = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float glow = smoothstep(glow_width, 0.0, edge_dist);
	vec3 result = mix(base.rgb, glow_color.rgb, glow * glow_intensity);
	COLOR = vec4(result, base.a);
}