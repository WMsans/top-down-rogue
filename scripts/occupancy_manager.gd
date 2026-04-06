class_name OccupancyManager
extends Node

var rd: RenderingDevice
var registered_bodies: Array[RigidBody2D] = []

func _ready() -> void:
    rd = RenderingServer.get_rendering_device()

func register_rigidbody(body: RigidBody2D) -> void:
    if body not in registered_bodies:
        registered_bodies.append(body)

func unregister_rigidbody(body: RigidBody2D) -> void:
    registered_bodies.erase(body)

func update_occupancy(chunks: Dictionary, chunk_size: int) -> void:
    var occupancy_by_chunk: Dictionary = {}
    
    for coord in chunks:
        var data := PackedByteArray()
        data.resize(chunk_size * chunk_size)
        data.fill(0)
        occupancy_by_chunk[coord] = data
    
    for body in registered_bodies:
        if not is_instance_valid(body):
            continue
        _rasterize_body(body, occupancy_by_chunk, chunk_size)
    
    for coord in chunks:
        var chunk: Chunk = chunks[coord]
        if chunk.occupancy_texture.is_valid():
            rd.texture_update(chunk.occupancy_texture, 0, occupancy_by_chunk[coord])

func _rasterize_body(body: RigidBody2D, occupancy_by_chunk: Dictionary, chunk_size: int) -> void:
    var global_pos := body.global_position
    var collision_shapes := body.find_children("", "CollisionShape2D", false)
    
    for shape_node in collision_shapes:
        var shape: CollisionShape2D = shape_node
        if not shape.shape:
            continue
        
        var shape_global_pos := shape.global_position
        var shape_rot := shape.global_rotation
        
        if shape.shape is RectangleShape2D:
            var rect := shape.shape as RectangleShape2D
            var half_size := rect.size / 2.0
            _rasterize_rect(
                shape_global_pos, half_size, shape_rot,
                occupancy_by_chunk, chunk_size
            )
        elif shape.shape is CircleShape2D:
            var circle := shape.shape as CircleShape2D
            _rasterize_circle(
                shape_global_pos, circle.radius,
                occupancy_by_chunk, chunk_size
            )

func _rasterize_rect(
    center: Vector2, half_size: Vector2, rotation: float,
    occupancy_by_chunk: Dictionary, chunk_size: int
) -> void:
    var cos_rot := cos(rotation)
    var sin_rot := sin(rotation)
    
    var min_x := int(floor(center.x - half_size.x - half_size.y))
    var max_x := int(ceil(center.x + half_size.x + half_size.y))
    var min_y := int(floor(center.y - half_size.y - half_size.x))
    var max_y := int(ceil(center.y + half_size.y + half_size.x))
    
    for px in range(min_x, max_x + 1):
        for py in range(min_y, max_y + 1):
            var local_x := float(px) - center.x
            var local_y := float(py) - center.y
            var rot_x := local_x * cos_rot + local_y * sin_rot
            var rot_y := -local_x * sin_rot + local_y * cos_rot
            
            if abs(rot_x) <= half_size.x and abs(rot_y) <= half_size.y:
                var chunk_coord := Vector2i(
                    floori(float(px) / chunk_size),
                    floori(float(py) / chunk_size)
                )
                if occupancy_by_chunk.has(chunk_coord):
                    var local_x_chunk := posmod(px, chunk_size)
                    var local_y_chunk := posmod(py, chunk_size)
                    var idx := local_y_chunk * chunk_size + local_x_chunk
                    occupancy_by_chunk[chunk_coord][idx] = 255

func _rasterize_circle(
    center: Vector2, radius: float,
    occupancy_by_chunk: Dictionary, chunk_size: int
) -> void:
    var radius_int := int(ceil(radius))
    var radius_sq := radius * radius
    
    for px in range(int(center.x) - radius_int, int(center.x) + radius_int + 1):
        for py in range(int(center.y) - radius_int, int(center.y) + radius_int + 1):
            var dx := float(px) - center.x
            var dy := float(py) - center.y
            if dx * dx + dy * dy <= radius_sq:
                var chunk_coord := Vector2i(
                    floori(float(px) / chunk_size),
                    floori(float(py) / chunk_size)
                )
                if occupancy_by_chunk.has(chunk_coord):
                    var local_x := posmod(px, chunk_size)
                    var local_y := posmod(py, chunk_size)
                    var idx := local_y * chunk_size + local_x
                    occupancy_by_chunk[chunk_coord][idx] = 255