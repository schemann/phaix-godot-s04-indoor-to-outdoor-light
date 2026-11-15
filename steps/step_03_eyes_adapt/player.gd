extends CharacterBody3D

@export var walk_speed := 5.0
@export var slow_speed := 2.0 ## Holding the walk key.
@export var turn_speed := 10.0 ## How fast the body turns to where it is going.
@export var blend_speed := 12.0 ## How fast the blend position follows the real speed, in metres per second, per second.
@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.002 ## Radians per pixel.
@export var stick_look_speed := 3.0 ## Radians per second.
@export_range(0.0, 90.0) var max_pitch := 89.0 ## Degrees.

var frozen := false ## The run is over: no input, the player stands where it is.

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var blend_position := 0.0 ## What the blend space sees. It follows the speed, so the legs never snap.

@onready var head: Node3D = $Head
@onready var body: Node3D = $Body
@onready var animation_tree: AnimationTree = $Body/AnimationTree

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for mesh: MeshInstance3D in body.find_children("*", "MeshInstance3D"):
		mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED # the body moves, and the distance field of SDFGI cannot follow a moving mesh

func _unhandled_input(event: InputEvent) -> void:
	if frozen:
		return
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("capture_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_view(event.relative * mouse_sensitivity)

func _physics_process(delta: float) -> void:
	if frozen: # no input, but a player still in the air comes down
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		animate(delta)
		return

	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	rotate_view(look * stick_look_speed * delta)

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	# get_vector returns (x: left/right, y: forward/back); the basis turns it into
	# the direction the player is facing.
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := transform.basis * Vector3(input.x, 0.0, input.y)
	var speed := slow_speed if Input.is_action_pressed("walk") else walk_speed
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	move_and_slide()
	animate(delta)

## The speed goes into the blend space. A moving body turns to where it is going.
func animate(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	blend_position = move_toward(blend_position, speed, blend_speed * delta)
	animation_tree.set("parameters/Move/blend_position", blend_position)
	if speed > 0.1:
		var heading := atan2(velocity.x, velocity.z) # the figure was built facing +Z
		body.global_rotation.y = lerp_angle(body.global_rotation.y, heading, turn_speed * delta)

## Yaw turns the whole body (so "forward" follows the view), pitch only tilts the head.
## amount is (yaw, pitch) in radians, positive = right / down.
func rotate_view(amount: Vector2) -> void:
	rotation.y -= amount.x
	var limit := deg_to_rad(max_pitch)
	head.rotation.x = clampf(head.rotation.x - amount.y, -limit, limit)

## Stops the player where it stands and gives the mouse back, or takes it again.
func set_frozen(value: bool) -> void:
	if frozen == value:
		return
	frozen = value
	velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if frozen else Input.MOUSE_MODE_CAPTURED
