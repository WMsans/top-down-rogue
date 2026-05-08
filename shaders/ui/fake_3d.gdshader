shader_type canvas_item;

uniform vec2 rect_size = vec2(160.0, 220.0);
uniform float fov : hint_range(1, 179) = 90.0;
uniform bool cull_back = true;
uniform float y_rot : hint_range(-360.0, 360.0) = 0.0;
uniform float x_rot : hint_range(-360.0, 360.0) = 0.0;
uniform float inset : hint_range(0, 1) = 0.0;

uniform float shine_intensity : hint_range(0.0, 4.0) = 1.0;
uniform vec4 shine_color : source_color = vec4(1.0, 0.95, 0.75, 1.0);
uniform float rim_strength : hint_range(0.0, 4.0) = 1.0;
uniform vec4 rim_color : source_color = vec4(1.0, 0.55, 0.25, 1.0);
uniform float selected : hint_range(0.0, 1.0) = 0.0;
uniform vec4 selected_color : source_color = vec4(1.0, 0.85, 0.15, 1.0);

varying flat vec2 o;
varying vec3 p;

void vertex(){
	float sin_b = sin(y_rot / 180.0 * PI);
	float cos_b = cos(y_rot / 180.0 * PI);
	float sin_c = sin(x_rot / 180.0 * PI);
	float cos_c = cos(x_rot / 180.0 * PI);

	mat3 inv_rot_mat;
	inv_rot_mat[0][0] = cos_b;
	inv_rot_mat[0][1] = 0.0;
	inv_rot_mat[0][2] = -sin_b;
	inv_rot_mat[1][0] = sin_b * sin_c;
	inv_rot_mat[1][1] = cos_c;
	inv_rot_mat[1][2] = cos_b * sin_c;
	inv_rot_mat[2][0] = sin_b * cos_c;
	inv_rot_mat[2][1] = -sin_c;
	inv_rot_mat[2][2] = cos_b * cos_c;

	float t = tan(fov / 360.0 * PI);
	p = inv_rot_mat * vec3((UV - 0.5), 0.5 / t);
	float v = (0.5 / t) + 0.5;
	p.xy *= v * inv_rot_mat[2].z;
	o = v * inv_rot_mat[2].xy;

	VERTEX += (UV - 0.5) * rect_size * t * (1.0 - inset);
}

void fragment(){
	if (cull_back && p.z <= 0.0) discard;
	vec2 uv = (p.xy / p.z).xy - o;
	vec2 cuv = uv;
	float mask = step(max(abs(cuv.x), abs(cuv.y)), 0.5);
	vec4 tex_col = texture(TEXTURE, cuv + 0.5);

	float tilt_x = clamp(y_rot / 30.0, -1.0, 1.0);
	float tilt_y = clamp(-x_rot / 30.0, -1.0, 1.0);
	float tilt_amount = clamp(length(vec2(tilt_x, tilt_y)), 0.0, 1.5);

	vec2 sheen_axis = normalize(vec2(0.7071, 0.7071));
	float band = dot(cuv, sheen_axis);
	float center = (tilt_x - tilt_y) * 0.35;
	float sheen = smoothstep(0.18, 0.0, abs(band - center));
	sheen *= tilt_amount * shine_intensity;

	float edge = max(abs(cuv.x), abs(cuv.y));
	float rim = smoothstep(0.40, 0.50, edge);
	float rim_glow = rim * (0.25 + tilt_amount * 0.9) * rim_strength;

	vec3 col = tex_col.rgb;
	col += shine_color.rgb * sheen * tex_col.a;
	col = mix(col, rim_color.rgb, rim_glow * 0.55 * tex_col.a);

	float select_rim = smoothstep(0.36, 0.50, edge);
	col = mix(col, selected_color.rgb, select_rim * selected * tex_col.a);

	float out_alpha = tex_col.a + select_rim * selected * 0.6 * mask;
	out_alpha = clamp(out_alpha, 0.0, 1.0);

	COLOR = vec4(col, out_alpha);
	COLOR.a *= mask;
}
