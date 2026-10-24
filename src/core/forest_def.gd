class_name ForestDef
extends Resource

## Placement tuning for ForestPlanner: which props and flora exist in a biome
## and how thickly they populate a chunk. Pure data; spawning happens in
## FloorChunk.

@export var tree_defs: Array[ForestPropDef] = []
@export var rock_defs: Array[ForestPropDef] = []
## Glowing plants clustered at prop bases and in the clearing between patches.
@export var root_flora: Array[DecorDef] = []
## Small non-glowing rocks laid against walls.
@export var edge_rocks: Array[DecorDef] = []
## Lone fill scattered over ground outside forest patches.
@export var sprinkle_flora: Array[DecorDef] = []

@export var patch_frequency: float = 0.003
@export var patch_threshold: float = 0.2

@export var secondary_groups: int = 2
@export var rock_attempts: int = 3
@export var edge_rock_count: int = 4
@export var flora_per_tree: int = 4
@export var sprinkle_chance: float = 0.012
