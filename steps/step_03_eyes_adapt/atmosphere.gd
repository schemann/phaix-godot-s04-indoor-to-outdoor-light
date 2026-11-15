extends WorldEnvironment
## The light of the whole game is one Environment: Godot allows one WorldEnvironment per scene. This node holds two moods
## of it, inside and outside (two Environment resources, tuned in the inspector), and moves the live Environment between
## them by how far the camera is from the rooms and into the open air.

## The numbers that differ between the moods. A mode (the background, the source of the ambient light, the tonemap) cannot
## be half of another, so it is the same in both and is not in this list.
const BLENDED: Array[StringName] = [
	&"ambient_light_energy", &"ambient_light_sky_contribution",
	&"fog_light_color", &"fog_density", &"volumetric_fog_density",
]

@export var inside: Environment ## The mood of the rooms.
@export var outside: Environment ## The mood of the garden.
@export var sun_indirect_inside := 0.0 ## The Indirect Energy of the sun in the rooms: none, or its bounce light leaks through the walls into the room next to the garden.
@export var sun_indirect_outside := 0.5 ## In the garden: half, so the shadows keep their colour.

var openness := 0.0 ## 0 is inside, 1 is outside, in between while the camera is in a doorway.

func _ready() -> void:
	environment = inside.duplicate() # the live copy: the two moods stay as they were tuned
	apply(0.0)

## The camera decides, every frame, from where it is. Nothing is remembered, so a restart, a room that goes away or
## a walk back through the door cannot leave the light behind.
func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var value := 0.0
	for room in get_tree().get_nodes_in_group("outdoors"):
		value = maxf(value, room.openness_at(camera.global_position))
	apply(value)

## Every frame, so that a garden that was just built gets its numbers too.
func apply(value: float) -> void:
	openness = value
	for property in BLENDED:
		environment.set(property, lerp(inside.get(property), outside.get(property), openness))
	var sun_share := smoothstep(0.5, 1.0, openness) ## The global illumination follows a light late, so the bounce light of the sun is gone at the door plane: 0 up to there, 1 from 1.5 m into the garden.
	for room in get_tree().get_nodes_in_group("outdoors"):
		(room.get_node("Sun") as DirectionalLight3D).light_indirect_energy = lerpf(sun_indirect_inside, sun_indirect_outside, sun_share)
