class_name EnemyVfxShared
extends RefCounted


static func soft_dot_texture(size: int = 8) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = size
	tex.height = size
	return tex


static func fade_gradient(hot: Color, fade: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, hot)
	g.set_color(1, fade)
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex
