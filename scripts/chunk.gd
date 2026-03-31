class_name Chunk
extends RefCounted

var coord: Vector2i
var rd_texture: RID
var texture_2d_rd: Texture2DRD
var mesh_instance: MeshInstance2D
var sim_uniform_set: RID
var static_body: StaticBody2D
var collision_dirty: bool = true
