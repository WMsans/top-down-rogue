class_name FeatureRoomSign
extends ArenaFeature

## Places a RoomSign at the room anchor (plus offset). Reuses the PickupContext
## proximity-popup pipeline so the player can read the room's risk/reward.

@export var title: String = ""
@export_multiline var body: String = ""
@export var offset: Vector2 = Vector2.ZERO


func apply(ctx) -> void:
	var sign := RoomSign.new()
	sign.title = title
	sign.body = body
	ctx.dispatcher.spawn_node(sign, ctx.anchor_world_pos + offset)
