extends "room.gd"
## A room under the open sky. It joins the group "outdoors", and the atmosphere asks every room of the group how
## open the air is where the camera stands.

const REACH := 1.5 ## Metres on each side of a door plane over which the light changes.
const DOOR_WIDTH := 2.4 ## Metres. Outside the garden only this strip in front of a door counts: next to it is a wall.

func _ready() -> void:
	super()
	add_to_group("outdoors")

## 1 in the garden, 0 in the rooms, and in the doorway the share in between: half at the door plane.
func openness_at(point: Vector3) -> float:
	var local := to_local(point)
	var depth := entrance.position.z - absf(local.z) ## Metres inside the garden, counted from the nearer door plane. Negative: outside.
	if depth < 0.0 and absf(local.x) > DOOR_WIDTH / 2.0:
		return 0.0 # beside the door, behind the wall
	return clampf(0.5 + depth / (2.0 * REACH), 0.0, 1.0)
