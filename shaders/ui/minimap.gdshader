shader_type canvas_item;

uniform sampler2D terrain_tex : filter_nearest;
uniform sampler2D reveal_tex : filter_linear;
uniform vec2 player_world;     // player world position (px)
uniform vec2 view_extent;      // half-window size in world px
uniform vec2 world_origin;     // world px at image (0,0) == (-half,-half)
uniform vec2 world_size;       // world px spanned by the full image

uniform vec4 wall_color : source_color = vec4(0.45, 0.40, 0.32, 1.0);
uniform vec4 floor_color : source_color = vec4(0.14, 0.12, 0.10, 1.0);
uniform vec4 fog_color : source_color = vec4(0.04, 0.03, 0.03, 1.0);

void fragment() {
	vec2 rel = (UV - vec2(0.5)) * 2.0;                 // -1..1 across widget
	vec2 world_pos = player_world + rel * view_extent;
	vec2 img_uv = (world_pos - world_origin) / world_size;
	vec3 col = fog_color.rgb;
	if (img_uv.x >= 0.0 && img_uv.x <= 1.0 && img_uv.y >= 0.0 && img_uv.y <= 1.0) {
		float reveal = texture(reveal_tex, img_uv).r;
		float wall = texture(terrain_tex, img_uv).r;
		float vis = smoothstep(0.35, 0.55, reveal);
		vec3 terrain = mix(floor_color.rgb, wall_color.rgb, wall);
		col = mix(fog_color.rgb, terrain, vis);
	}
	COLOR = vec4(col, 1.0);
}
