extends SceneTree
## Makes the two animations the pack does not have, from the three it has, and saves them as an animation library.
##   godot --headless --path . -s res://steps/step_03_eyes_adapt/make_animations.gd
## Walk is Run with a smaller swing, played slower. Fall is the pose of Jump with the arms up and a small flutter.

const IDLE: AnimationLibrary = preload("res://character/Animations/idle.fbx")
const RUN: AnimationLibrary = preload("res://character/Animations/run.fbx")
const JUMP: AnimationLibrary = preload("res://character/Animations/jump.fbx")
const MODEL: PackedScene = preload("res://character/Model/characterMedium.fbx")
const OUTPUT := "res://steps/step_03_eyes_adapt/made.tres"

const WALK_SWING := 0.6 ## How much of Run's swing Walk keeps.
const WALK_SLOWER := 1.5 ## One Walk cycle takes this many times as long as one Run cycle.
const FALL_SECONDS := 0.4 ## How long one flutter of the arms takes.
const JUMP_TIME := 0.25 ## The moment of Jump that Fall holds.
const ARMS_UP := [0.55, 0.75] ## How far the arms go from Jump's pose towards the T-pose: the two ends of the flutter.
const ARM_BONES: Array[String] = ["LeftArm", "RightArm"]

var skeleton: Skeleton3D

func _initialize() -> void:
	var model := MODEL.instantiate()
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	var library := AnimationLibrary.new()
	library.add_animation("Walk", make_walk(RUN.get_animation("Root|Run"), IDLE.get_animation("Root|Idle")))
	library.add_animation("Fall", make_fall(JUMP.get_animation("Root|Jump")))
	model.free()
	var error := ResourceSaver.save(library, OUTPUT)
	for animation_name in library.get_animation_list():
		var animation := library.get_animation(animation_name)
		print("%s: %.2f s, %d tracks, loop %d" % [animation_name, animation.length, animation.get_track_count(), animation.loop_mode])
	print("saved %s" % OUTPUT if error == OK else "could not save %s" % OUTPUT)
	quit(error)

## Every bone of Run goes back towards its pose in Idle, so the same steps get smaller. Then the clock runs slower.
func make_walk(run: Animation, idle: Animation) -> Animation:
	var walk := run.duplicate(true) as Animation
	walk.length = run.length * WALK_SLOWER
	walk.loop_mode = Animation.LOOP_LINEAR
	for track in walk.get_track_count():
		var count := walk.track_get_key_count(track)
		var rotates := walk.track_get_type(track) == Animation.TYPE_ROTATION_3D
		var calm := calm_rotation(idle, walk.track_get_path(track)) if rotates else Quaternion.IDENTITY
		for key in range(count - 1, -1, -1): # last key first: a key that moves later never passes the next one
			if rotates:
				var pose: Quaternion = walk.track_get_key_value(track, key)
				walk.track_set_key_value(track, key, calm.slerp(pose, WALK_SWING))
			walk.track_set_key_time(track, key, walk.track_get_key_time(track, key) * WALK_SLOWER)
	walk.resource_name = "Walk"
	return walk

## The pose of a bone when the character stands still: its rotation in Idle, or its rest pose if Idle does not move it.
func calm_rotation(idle: Animation, path: NodePath) -> Quaternion:
	var track := idle.find_track(path, Animation.TYPE_ROTATION_3D)
	if track >= 0:
		return idle.track_get_key_value(track, 0)
	return rest_rotation(path)

## The rotation a bone has in the T-pose. A track's path ends in the bone's name: "Root/Skeleton3D:Spine".
func rest_rotation(path: NodePath) -> Quaternion:
	var bone := skeleton.find_bone(path.get_concatenated_subnames())
	return skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()

## One moment of Jump, held: every track keeps one value, and the arms flutter between two heights.
func make_fall(jump: Animation) -> Animation:
	var fall := Animation.new()
	fall.length = FALL_SECONDS
	fall.loop_mode = Animation.LOOP_PINGPONG
	for track in jump.get_track_count():
		var path := jump.track_get_path(track)
		var type := jump.track_get_type(track)
		if type == Animation.TYPE_POSITION_3D:
			var copy := fall.add_track(type)
			fall.track_set_path(copy, path)
			fall.track_insert_key(copy, 0.0, jump.position_track_interpolate(track, JUMP_TIME))
		elif type == Animation.TYPE_ROTATION_3D:
			var copy := fall.add_track(type)
			fall.track_set_path(copy, path)
			var pose := jump.rotation_track_interpolate(track, JUMP_TIME)
			if path.get_concatenated_subnames() in ARM_BONES:
				fall.track_insert_key(copy, 0.0, pose.slerp(rest_rotation(path), ARMS_UP[0]))
				fall.track_insert_key(copy, FALL_SECONDS, pose.slerp(rest_rotation(path), ARMS_UP[1]))
			else:
				fall.track_insert_key(copy, 0.0, pose)
	return fall
