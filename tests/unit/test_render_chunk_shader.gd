extends GdUnitTestSuite

const SHADER_PATH := "res://shaders/visual/render_chunk.gdshader"

func _uniform_names() -> Array:
	var shader := load(SHADER_PATH) as Shader
	assert_that(shader).is_not_null()
	var names: Array = []
	for u in shader.get_shader_uniform_list():
		names.append(String(u.get("name", "")))
	return names

func _has_uniform(names: Array, target: String) -> bool:
	for n in names:
		if String(n).ends_with(target):
			return true
	return false

func test_shader_exposes_ao_strength_uniform() -> void:
	assert_bool(_has_uniform(_uniform_names(), "ao_strength")).is_true()

func test_shader_exposes_ao_reach_uniform() -> void:
	assert_bool(_has_uniform(_uniform_names(), "ao_reach")).is_true()
