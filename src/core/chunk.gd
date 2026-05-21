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

var light_pack_uniform_sets: Array[RID] = [RID(), RID()]
# Two persistent uniform sets — one per write-buffer parity, binding rd_texture + collider_output_buffer.
var collider_uniform_sets: Array[RID] = [RID(), RID()]
var chunk_lights  # ChunkLights (Node2D)

var hazard_cells: PackedInt32Array = PackedInt32Array()

var rd_flag_texture: RID = RID()

func _init() -> void:
	hazard_cells.resize(16)
	hazard_cells.fill(0)

func create_flag_texture(rd: RenderingDevice, size: int) -> void:
	var tf := RDTextureFormat.new()
	tf.width = size
	tf.height = size
	tf.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var zero := PackedByteArray()
	zero.resize(size * size)
	zero.fill(0)
	rd_flag_texture = rd.texture_create(tf, RDTextureView.new(), [zero])
