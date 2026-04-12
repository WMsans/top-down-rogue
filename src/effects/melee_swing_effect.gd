class_name MeleeSwingEffect
extends Node2D

const DURATION: float = 0.25
const ARC_POINTS: int = 12
const ARC_RADIUS: float = 40.0
const HALF_ARC: float = PI / 4.0

@onready var line: Line2D = $Line2D

var _elapsed: float = 0.0


func _ready() -> void:
    _elapsed = 0.0
    _build_arc()


func _build_arc() -> void:
    var points: PackedVector2Array = []
    for i in range(ARC_POINTS + 1):
        var angle := -HALF_ARC + (HALF_ARC * 2.0) * float(i) / float(ARC_POINTS)
        var point := Vector2(cos(angle), sin(angle)) * ARC_RADIUS
        points.append(point)
    line.points = points


func _process(delta: float) -> void:
    _elapsed += delta
    var t := _elapsed / DURATION
    
    if t >= 1.0:
        queue_free()
        return
    
    var scale_val := 0.8 + t * 0.4
    scale = Vector2(scale_val, scale_val)
    modulate.a = 1.0 - t