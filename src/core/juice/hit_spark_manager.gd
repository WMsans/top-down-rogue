extends Node

const SPARK_COUNT_MIN: int = 6
const SPARK_COUNT_MAX: int = 8
const SPARK_SPEED_MIN: float = 80.0
const SPARK_SPEED_MAX: float = 160.0
const SPARK_LIFETIME: float = 0.15
const SPARK_CONE_HALF_ANGLE: float = PI / 6.0
const SPARK_SIZE: Vector2 = Vector2(2, 2)
const SPARK_COLOR: Color = Color(1.0, 1.0, 0.85, 1.0)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func spawn(point: Vector2, dir: Vector2) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var base_angle: float = dir.angle() if dir.length_squared() > 0.0001 else 0.0
	var count: int = randi_range(SPARK_COUNT_MIN, SPARK_COUNT_MAX)
	for i in count:
		var spark := ColorRect.new()
		spark.color = SPARK_COLOR
		spark.size = SPARK_SIZE
		spark.pivot_offset = SPARK_SIZE / 2.0
		spark.position = point - SPARK_SIZE / 2.0
		spark.z_index = 100
		spark.z_as_relative = false
		scene_root.add_child(spark)
		var angle := base_angle + randf_range(-SPARK_CONE_HALF_ANGLE, SPARK_CONE_HALF_ANGLE)
		var speed := randf_range(SPARK_SPEED_MIN, SPARK_SPEED_MAX)
		var velocity := Vector2(cos(angle), sin(angle)) * speed
		var target_pos := spark.position + velocity * SPARK_LIFETIME
		var tween := spark.create_tween()
		tween.set_parallel(true)
		tween.tween_property(spark, "position", target_pos, SPARK_LIFETIME)
		tween.tween_property(spark, "modulate:a", 0.0, SPARK_LIFETIME)
		tween.chain().tween_callback(spark.queue_free)
