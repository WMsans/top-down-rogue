shader_type canvas_item;

uniform vec2 pommel_uv = vec2(0.861, 0.861);
uniform vec2 blade_dir = vec2(-0.707, -0.707);
uniform float tip_darken : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	tex.rgb *= COLOR.rgb;
	tex.a *= COLOR.a;
	vec2 to_pixel = UV - pommel_uv;
	float along_blade = dot(to_pixel, blade_dir);
	float t = smoothstep(0.0, 1.18, along_blade);
	vec3 darkened = mix(tex.rgb, tex.rgb * 0.05, t * tip_darken);
	COLOR = vec4(darkened, tex.a);
}
