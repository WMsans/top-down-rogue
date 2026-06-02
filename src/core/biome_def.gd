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
@export var boss_compositions: Array[Resource] = []   # ArenaComposition list, replaces boss_templates
@export var secret_ring_thickness: int = 3            # secret system unchanged
@export var tint: Color = Color.WHITE
@export var ui_accent: Color = Color(0.85, 0.46, 0.26, 1)  # default = caves orange
@export var floor_texture: Texture2D = null
@export var decor_defs: Array[DecorDef] = []
@export var decor_chance: float = 0.02
@export var cave_spawn_rate: float = 1.0
@export var enemy_pool: Array[PackedScene] = []
@export var elite_chance: float = 0.15
@export var boss_scene: PackedScene = null
@export var fixed_anchors: Dictionary = {}  # Vector2i sector -> RoomTemplate
