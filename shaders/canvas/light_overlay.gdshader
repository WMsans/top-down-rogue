shader_type canvas_item;
render_mode blend_add, unshaded;

global uniform sampler2D light_grid_tex : filter_linear, repeat_disable;
global uniform vec4 light_grid_world_rect;
global uniform float light_intensity_k;
global uniform vec3 light_ambient;

void fragment() {
	// Convert SCREEN_UV -> world-space pixel.
	vec2 screen_px = SCREEN_UV / SCREEN_PIXEL_SIZE;
	vec2 world_px = (inverse(CANVAS_MATRIX) * vec4(screen_px, 0.0, 1.0)).xy;

	vec2 rel = world_px - light_grid_world_rect.xy;
	vec2 grid_uv = rel / light_grid_world_rect.zw;

	vec3 lit = light_ambient;
	if (all(greaterThanEqual(grid_uv, vec2(0.0))) && all(lessThan(grid_uv, vec2(1.0)))) {
		lit += texture(light_grid_tex, grid_uv).rgb * light_intensity_k;
	}
	COLOR = vec4(lit, 1.0);
}
