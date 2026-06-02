class_name DecorDef
extends Resource

## One decoration variant for a biome's floor scatter.
## A glowing decoration carries its own PointLight2D config; set
## emits_light = false for an ordinary (non-glowing) decoration.

@export var texture: Texture2D
@export var weight: float = 1.0                              ## relative pick weight within a biome
@export var emits_light: bool = true
@export var light_color: Color = Color(0.5, 0.9, 1.0, 1.0)   ## soft cyan/teal
@export var light_energy: float = 1.0
@export var light_radius: float = 56.0                       ## px; maps to PointLight2D.texture_scale
@export var flicker_amplitude: float = 0.08                  ## 0 = steady glow
