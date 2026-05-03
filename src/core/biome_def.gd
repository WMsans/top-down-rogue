class_name BiomeDef
extends Resource

@export var display_name: String = ""
@export var cave_noise_scale: float = 0.008
@export var cave_threshold: float = 0.42
@export var ridge_weight: float = 0.3
@export var ridge_scale: float = 0.012
@export var octaves: int = 5
@export var background_material: int = 2  # STONE
@export var pool_materials: Array[PoolDef] = []
@export var room_templates: Array[RoomTemplate] = []
@export var boss_templates: Array[RoomTemplate] = []
@export var secret_ring_thickness: int = 3
@export var tint: Color = Color.WHITE
@export var cave_spawn_rate: float = 1.0
