class_name MinSizeApplier
extends Node

## Attach to a Button to apply min-size constants from the theme.
## Buttons read theme variations but Godot has no built-in min-size theme
## property, so we apply them at runtime from theme constants.

const UILayout = preload("res://src/ui/ui_layout.gd")

func _ready() -> void:
	var btn := get_parent() as Button
	if btn == null:
		queue_free()
		return
	await btn.ready
	var t := btn.get_theme() if btn.get_theme() != null else UiTheme.get_theme()
	var min_h := t.get_constant("button_min_height_marker", "Button") \
		if t.has_constant("button_min_height_marker", "Button") else 0
	var min_w := 0
	var variation := str(btn.theme_type_variation)
	if variation == "CompactButton":
		min_w = t.get_constant("compact_min_width_marker", "CompactButton") \
			if t.has_constant("compact_min_width_marker", "CompactButton") else 0
	elif variation == "IconButton":
		min_w = UILayout.BUTTON_ICON_SIZE
		min_h = UILayout.BUTTON_ICON_SIZE
	if min_h > 0 or min_w > 0:
		btn.custom_minimum_size = Vector2(max(min_w, btn.custom_minimum_size.x),
		                                  max(min_h, btn.custom_minimum_size.y))
	queue_free()
