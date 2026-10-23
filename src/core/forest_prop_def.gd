class_name ForestPropDef
extends Resource

# Shared definition for breakable forest props (ForestProp runtime). `kind`
# selects the impact material, `role`/`family` drive biome placement.
@export var texture: Texture2D
@export var kind: String = "tree"  # "tree" | "rock"
@export var role: String = "any"  # "bright" | "dark" | "odd" | "any"
@export var family: String = ""
@export var trunk_radius: float = 6.0
@export var hp: float = 10.0
@export var tint: Color = Color(0.7, 0.7, 0.75, 1)
@export var weight: float = 1.0

var _base_inset_cache: int = -1


func impact_material() -> int:
	return MaterialRegistry.MAT_STONE if kind == "rock" else MaterialRegistry.MAT_WOOD


# Fully transparent rows at the bottom of `texture`; the prop anchors its trunk
# base at the origin, so those rows are subtracted from the sprite offset.
# Computed once from the image and cached on the def.
func base_inset() -> int:
	if _base_inset_cache >= 0:
		return _base_inset_cache
	var rows := 0
	if texture != null:
		var img := texture.get_image()
		if img != null:
			var width := img.get_width()
			for y in range(img.get_height() - 1, -1, -1):
				var row_transparent := true
				for x in range(width):
					if img.get_pixel(x, y).a > 0.0:
						row_transparent = false
						break
				if not row_transparent:
					break
				rows += 1
	_base_inset_cache = rows
	return rows
