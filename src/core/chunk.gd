class_name Chunk
extends RefCounted

var coord: Vector2i
var rd_texture: RID
var texture_2d_rd: Texture2DRD
var mesh_instance: MeshInstance2D
var wall_mesh_instance: MeshInstance2D
var sim_uniform_set: RID
var injection_buffer: RID
var static_body: StaticBody2D
var occluder_instances: Array[LightOccluder2D] = []

var light_output_buffer: RID
var light_pack_uniform_set: RID
var chunk_lights  # ChunkLights (Node2D)
