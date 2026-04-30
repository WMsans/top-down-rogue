shader_type canvas_item;
render_mode blend_add, unshaded;

global uniform sampler2D light_grid_tex : filter_linear, repeat_disable;
global uniform vec4 light_grid_world_rect;
global uniform float light_intensity_k;
global uniform vec2 light_camera_origin;
global uniform vec2 light_camera_size;

const vec3 AMBIENT = vec3(0.05, 0.05, 0.05);
const float MAX_LIGHT = 2.0;

void fragment() {
	if (light_grid_world_rect.z <= 0.0 || light_grid_world_rect.w <= 0.0
			|| light_camera_size.x <= 0.0 || light_camera_size.y <= 0.0) {
		COLOR = vec4(AMBIENT, 1.0);
		return;
	}

	vec2 world_px = light_camera_origin + UV * light_camera_size;
	vec2 rel = world_px - light_grid_world_rect.xy;
	vec2 grid_uv = rel / light_grid_world_rect.zw;

	vec3 lit = AMBIENT;
	if (all(greaterThanEqual(grid_uv, vec2(0.0))) && all(lessThan(grid_uv, vec2(1.0)))) {
		vec3 sample = texture(light_grid_tex, grid_uv).rgb;
		// Clamp to prevent HDR runaway from glow * intensity stacking.
		sample = clamp(sample, vec3(0.0), vec3(MAX_LIGHT));
		lit += sample * light_intensity_k;
	}
	COLOR = vec4(lit, 1.0);
}
