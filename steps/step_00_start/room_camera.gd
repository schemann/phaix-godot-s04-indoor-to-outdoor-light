extends Camera3D
## Press V: a second camera, high up in the doorway of the room the player is in. It looks at the player once
## and stays still. V again gives the view back. It has the default cull mask, so it sees the body.

const HEIGHT := 2.6 ## Metres above the floor, over the door.
const INSIDE := 0.5 ## Metres inside the room, clear of the wall.

@export var level: Node3D

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("toggle_view"):
		return
	if current:
		level.player.get_node("Head/Camera3D").make_current() # the player's own camera has the view again
		return
	var entrance: Marker3D = level.rooms[level.current].entrance
	global_position = entrance.global_transform * Vector3(0.0, HEIGHT, -INSIDE)
	look_at(level.player.global_position + Vector3.UP)
	make_current()
