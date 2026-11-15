extends SceneTree
## Headless tests for the special s04 (indoor to outdoor light). From the repository root:
##   godot --headless --path godot/s04-indoor-to-outdoor-light -s res://tests/run_tests.gd
## Prints PASS or FAIL per test and exits with 0 only if every test passed.
## `-- --only=text` runs the tests whose name contains the text (for example `-- --only=garden`).
##
## Saves: every level the tests load gets its own temporary save file (OS temp dir), so a test run never reads or
## writes the real best_times.json.

const Autopilot := preload("res://tools/autopilot.gd")

const STEPS: Array[String] = [
	"step_00_start",
	"step_01_garden",
	"step_02_two_moods",
	"step_03_eyes_adapt",
]
const FINAL_STEP := "step_03_eyes_adapt"

## What each step changes against the one before (file names under the step folder, props/ included; .uid files do not count).
const CHANGES: Dictionary[String, Dictionary] = {
	"step_01_garden": {changed = ["level.gd", "room_chain.gd"], added = ["room_garden.tscn"]},
	"step_02_two_moods": {changed = ["main.tscn", "room_garden.tscn"], added = ["atmosphere.gd", "garden.gd", "inside.tres", "outside.tres", "sky.tres"]},
	"step_03_eyes_adapt": {changed = ["inside.tres", "main.tscn", "outside.tres", "room_garden.tscn"], added = []},
}

## The actions of tutorial 08 (this special adds no key).
const ACTIONS: Array[String] = [
	"move_forward", "move_back", "move_left", "move_right", "jump", "walk", "look_left", "look_right", "look_up", "look_down",
	"toggle_debug", "regenerate", "next_seed", "edit_seed", "copy_seed", "capture_mouse",
	"toggle_view", "toggle_gizmos", "toggle_watch", "step_generation",
]

const STATE_FINISHED := 2 ## Level.State
const SPEED_UP := 4 ## The full run goes this many times faster than real time.
const PLAN_SEEDS := 200 ## Seeds 1..200 for the comparisons between steps.
const GOAL_ROOM := 20
const RUN_SEED := 42 ## The seed of the full run: its rooms 2 and 14 are gardens (tools/scan_gardens.gd).
const SUN_ENERGY := 3.0 ## Step 3: the sun of a garden and the sky of both moods, in the units of the engine (the docs: outdoor lights are above 1.0).
const SKY_ENERGY := 3.0
const MIN_SENSITIVITY := 320.0 ## Step 3: the lowest ISO the eyes may adapt to, so that the rooms keep the look of tutorial 08.
const WALL_TOP := 3.0 ## Metres: the walls of a room end here, a garden has nothing above.
const EYE_HEIGHT := 1.6

## The numbers of the Environment that change between the two moods (atmosphere.gd), by name, and the values at each end.
const BLENDED: Dictionary[StringName, Array] = {
	&"ambient_light_energy": [0.02, 1.0],
	&"ambient_light_sky_contribution": [0.0, 1.0],
	&"fog_density": [0.03, 0.003],
	&"volumetric_fog_density": [0.07, 0.01],
}

## The Indirect Energy of the sun (atmosphere.gd, one more number that changes between the two moods, on the sun of the garden instead of the Environment):
## none in the rooms, or its bounce light leaks through the walls into the room next to the garden (review point 2 of 2026-11-11), half in the garden.
const SUN_INDIRECT: Array[float] = [0.0, 0.5]

## Counts the errors the engine logs. A test that hits a script error stops at that line and the engine hands back an
## empty array, which reads as a pass: `_report` charges the count to the test that ran.
class ScriptErrorCounter extends Logger:
	var count := 0
	var _lock := Mutex.new() ## The engine calls a logger from any thread.

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_lock.lock()
		count += 1
		_lock.unlock()

## Calls its callback once per physics tick, before the player's own tick.
class Driver extends Node:
	signal finished
	var tick: Callable

	func _physics_process(_delta: float) -> void:
		if tick.is_valid() and tick.call():
			tick = Callable()
			finished.emit()

var _passed := 0
var _failed := 0
var _skipped := 0
var _script_errors := ScriptErrorCounter.new() ## Registered with the engine's logger for the whole run.
var _script_errors_reported := 0 ## How many script errors the tests reported so far have been charged with.
var _save_dir := ""
var _save_counter := 0

func _initialize() -> void:
	OS.add_logger(_script_errors)
	await process_frame
	var started := Time.get_ticks_msec()
	_save_dir = OS.get_temp_dir().path_join("phaix-godot-s04-tests-%d" % OS.get_process_id()) # one folder per run: two runs at the same time must not wipe each other's save files
	_wipe_save_dir()

	await _run("code rules: no class_name, no global random, no wall clock, input only through named actions", test_code_rules)
	await _run("steps: each step changes only what its concept needs, everything else is copied forward", test_copy_forward)
	await _run("step_00_start: the final state of tutorial 08, file for file (only the folder names differ)", test_step_zero_is_tutorial_08)
	await _run("project: the actions of tutorial 08, the main scene is the final step", test_project_settings)
	await _run("plans: gardens move no room, lock, key or lamp of seeds 1-%d, they take a straight room, never room 0, never two within three rooms" % PLAN_SEEDS, test_gardens_in_the_plans)
	for step in _steps_from("step_01_garden"):
		await _run("%s garden scene: a straight room without a ceiling, the same doors, markers and box, one sun with shadows that does not light the fog" % step, test_garden_scene.bind(step))
	for step in _steps_from("step_01_garden"):
		await _run("%s environment: the inside mood is the look of tutorial 08, the outside mood changes only what the narration names" % step, test_environment.bind(step))
	for step in _steps_from("step_02_two_moods"):
		await _run("%s openness: 1 in the garden, 0 in the rooms, half at a door plane, from the camera's place alone" % step, test_openness.bind(step))
		await _run("%s blend: one live environment, six numbers between the two moods (five of the Environment, the Indirect Energy of the sun), the saved moods never change" % step, test_blend.bind(step))
	for step in STEPS:
		await _run("%s eyes: auto exposure and the energies of sun and sky are the ones the narration names, and only in step 3" % step, test_eyes.bind(step))
	await _run("full run: seed %d, goal room %d: the autopilot walks through the gardens, the openness follows the camera, at most one sun at once" % [RUN_SEED, GOAL_ROOM], test_full_run)
	for step in STEPS:
		await _run("%s: main scene runs 30 frames" % step, test_scene_runs.bind(step))

	_wipe_save_dir()
	OS.remove_logger(_script_errors)
	print("\n%d passed, %d failed, %d skipped in %.1f s" % [_passed, _failed, _skipped, (Time.get_ticks_msec() - started) / 1000.0])
	quit(1 if _failed > 0 else 0)

#region Source rules

func test_code_rules() -> Array[String]:
	var failures: Array[String] = []
	var global_random := RegEx.create_from_string("(^|[^.\\w])(randi|randf|randi_range|randf_range|randomize|pick_random)\\(")
	var wall_clock := RegEx.create_from_string("(Time\\.get_|OS\\.get_ticks|OS\\.get_unix|OS\\.delay)")
	var scripts := _files_in("res://steps", ".gd")
	_expect(failures, scripts.size() >= 100, "found only %d scripts under steps" % scripts.size())
	for path in scripts:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var line := lines[i].strip_edges()
			if line.begins_with("#"):
				continue
			var where := "%s:%d" % [path.trim_prefix("res://"), i + 1]
			_expect(failures, not line.begins_with("class_name"), "%s: class_name" % where)
			_expect(failures, global_random.search(line) == null, "%s: global random call" % where)
			_expect(failures, wall_clock.search(line) == null, "%s: reads the wall clock" % where)
			_expect(failures, not line.contains("Input.is_key_pressed") and not line.contains("Input.is_physical_key_pressed"), "%s: reads a key directly" % where)
			_expect(failures, not line.contains("event is InputEventKey") and not line.contains("event is InputEventJoypad"), "%s: reads a key or button event directly" % where)
	return failures

## Every file of a folder and its sub folders that ends with the suffix.
func _files_in(dir_path: String, suffix: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	for sub in dir.get_directories():
		found.append_array(_files_in(dir_path.path_join(sub), suffix))
	for file in dir.get_files():
		if file.ends_with(suffix):
			found.append(dir_path.path_join(file))
	return found

func test_copy_forward() -> Array[String]:
	var failures: Array[String] = []
	for i in range(1, STEPS.size()):
		var before := STEPS[i - 1]
		var after := STEPS[i]
		var before_files := _step_files(before)
		var after_files := _step_files(after)
		var changed: Array[String] = []
		var added: Array[String] = []
		for file in before_files:
			if not after_files.has(file):
				failures.append("%s lost %s" % [after, file])
			elif _step_text(before, file) != _step_text(after, file):
				changed.append(file)
		for file in after_files:
			if not before_files.has(file):
				added.append(file)
		changed.sort()
		added.sort()
		var expected: Dictionary = CHANGES[after]
		var expected_changed: Array = expected.changed.duplicate()
		var expected_added: Array = expected.added.duplicate()
		expected_changed.sort()
		expected_added.sort()
		_expect(failures, changed == expected_changed, "%s changes %s, expected %s" % [after, changed, expected_changed])
		_expect(failures, added == expected_added, "%s adds %s, expected %s" % [after, added, expected_added])
	# Step 3 is numbers on top of step 2: its two moods change in one line each, its main scene by the camera attributes, the garden by the sun's energy.
	var two := "step_02_two_moods"
	var three := FINAL_STEP
	_expect(failures, _lines_added(two, three, "inside.tres") == ["background_energy_multiplier = 3.0"], "step 3 changes more of inside.tres than the energy of the sky: %s" % [_lines_added(two, three, "inside.tres")])
	_expect(failures, _lines_added(two, three, "outside.tres") == ["background_energy_multiplier = 3.0"], "step 3 changes more of outside.tres than the energy of the sky: %s" % [_lines_added(two, three, "outside.tres")])
	_expect(failures, _lines_added(two, three, "room_garden.tscn") == ["light_energy = 3.0"], "step 3 changes more of room_garden.tscn than the energy of the sun: %s" % [_lines_added(two, three, "room_garden.tscn")])
	var main_added := _lines_added(two, three, "main.tscn")
	_expect(failures, main_added == ["[sub_resource type=\"CameraAttributesPractical\" id=\"CameraAttributesPractical_eyes\"]", "auto_exposure_enabled = true", "auto_exposure_min_sensitivity = 320.0", "camera_attributes = SubResource(\"CameraAttributesPractical_eyes\")"], "step 3 changes more of main.tscn than the camera attributes: %s" % [main_added])
	_expect(failures, _lines_removed(two, three, "main.tscn").is_empty(), "step 3 removes lines of main.tscn: %s" % [_lines_removed(two, three, "main.tscn")])
	return failures

func _step_files(step: String) -> Array[String]:
	var files: Array[String] = []
	for file in DirAccess.get_files_at("res://steps/" + step):
		if not file.ends_with(".uid"):
			files.append(file)
	if DirAccess.dir_exists_absolute("res://steps/%s/props" % step):
		for file in DirAccess.get_files_at("res://steps/%s/props" % step):
			if not file.ends_with(".uid"):
				files.append("props/" + file)
	return files

## The file's text with the step folder name blanked out, so copies compare equal.
func _step_text(step: String, file: String) -> String:
	return FileAccess.get_file_as_string("res://steps/%s/%s" % [step, file]).replace(step, "STEP")

## The lines of a file in `after` that its copy in `before` does not have (without empty lines and the header line "[gd_...", which counts its resources), in order.
func _lines_added(before: String, after: String, file: String) -> Array[String]:
	return _lines_not_in(_step_text(after, file), _step_text(before, file))

func _lines_removed(before: String, after: String, file: String) -> Array[String]:
	return _lines_not_in(_step_text(before, file), _step_text(after, file))

func _lines_not_in(text: String, other: String) -> Array[String]:
	var known := other.split("\n")
	var lines: Array[String] = []
	for line in text.split("\n"):
		if not line.strip_edges().is_empty() and not line.begins_with("[gd_") and not known.has(line):
			lines.append(line)
	return lines

## The folder of tutorial 08, which sits next to this project in the repository. Empty if it is not there.
func _tutorial_08() -> String:
	var folder := ProjectSettings.globalize_path("res://").path_join("../08-light-and-atmosphere").simplify_path()
	return folder if DirAccess.dir_exists_absolute(folder) else ""

## Step 0 is the last step of tutorial 08, copied. When that tutorial is not next to this project the test skips.
func test_step_zero_is_tutorial_08() -> Array[String]:
	var failures: Array[String] = []
	var tutorial := _tutorial_08()
	var original := tutorial.path_join("steps/step_05_global_illumination")
	if tutorial.is_empty() or not DirAccess.dir_exists_absolute(original):
		_skip("step_00_start equals the last step of tutorial 08", "tutorial 08 is not next to this project")
		return failures
	var original_files: Array[String] = []
	for file in DirAccess.get_files_at(original):
		if not file.ends_with(".uid"):
			original_files.append(file)
	for file in DirAccess.get_files_at(original.path_join("props")):
		if not file.ends_with(".uid"):
			original_files.append("props/" + file)
	_expect(failures, original_files.size() > 40, "found only %d files in the last step of tutorial 08" % original_files.size())
	for file in original_files:
		if not FileAccess.file_exists("res://steps/step_00_start/" + file):
			failures.append("step_00_start has no %s" % file)
			continue
		var theirs := _without_step_names(FileAccess.get_file_as_string(original.path_join(file))).replace("godot/08-light-and-atmosphere", "godot/PROJECT")
		var ours := _without_step_names(FileAccess.get_file_as_string("res://steps/step_00_start/" + file)).replace("godot/s04-indoor-to-outdoor-light", "godot/PROJECT")
		_expect(failures, theirs == ours, "%s differs from the last step of tutorial 08" % file)
	_expect(failures, original_files.size() == _step_files("step_00_start").size(), "step_00_start has %d files, the last step of tutorial 08 has %d" % [_step_files("step_00_start").size(), original_files.size()])
	return failures

## The files of tutorial 08 point at one of its step folders, the copies here at the start folder.
func _without_step_names(text: String) -> String:
	return RegEx.create_from_string("step_\\d\\d_[a-z_]+").sub(text, "STEP", true)

func test_project_settings() -> Array[String]:
	var failures: Array[String] = []
	for action in ACTIONS:
		_expect(failures, ProjectSettings.has_setting("input/" + action), "no %s action" % action)
	_expect(failures, ProjectSettings.get_setting("layer_names/3d_render/layer_3") == "Body", "render layer 3 is not named Body")
	_expect(failures, ProjectSettings.get_setting("application/run/main_scene") == "res://steps/%s/main.tscn" % FINAL_STEP, "the main scene is not the final step")
	_expect(failures, ProjectSettings.get_setting("application/config/custom_user_dir_name") == "phaix-godot-s04", "the user folder is not phaix-godot-s04")
	var tutorial := _tutorial_08()
	if tutorial.is_empty():
		_skip("project: the Input Map is the one of tutorial 08", "tutorial 08 is not next to this project")
		return failures
	var theirs := _input_section(tutorial.path_join("project.godot"))
	var ours := _input_section(ProjectSettings.globalize_path("res://project.godot"))
	_expect(failures, theirs.length() > 1000, "found no [input] section in the project.godot of tutorial 08")
	_expect(failures, theirs == ours, "the [input] section of project.godot is not the one of tutorial 08: this special adds no key")
	return failures

## Everything from the line "[input]" to the end of a project.godot.
func _input_section(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	var start := text.find("\n[input]")
	return text.substr(start) if start >= 0 else ""

#endregion

#region Chains (pure data, no scene)

func _chain_script(step: String) -> GDScript:
	return load("res://steps/%s/room_chain.gd" % step) as GDScript

## What the chain script's constant of that name is (an enum value of Type, or NO_PROP).
func _constant(chain_script: GDScript, type_name: String) -> int:
	return (chain_script.get_script_constant_map()["Type"] as Dictionary)[type_name]

## All plans of a chain up to and including its goal room (at most `limit` plans).
func _plans_to_goal(chain_script: GDScript, chain_seed: int, limit := 400) -> Array:
	var chain: RefCounted = chain_script.new(chain_seed, GOAL_ROOM, 0.4)
	var goal := _constant(chain_script, "GOAL")
	while chain.plans.size() < limit:
		var plan: Object = chain.next_plan()
		if plan.type == goal:
			break
	return chain.plans

## Every step plans the run of step 0 for every seed, with the gardens as the only difference: a garden takes a straight room and its props.
func test_gardens_in_the_plans() -> Array[String]:
	var failures: Array[String] = []
	var scripts: Array[GDScript] = []
	for step in STEPS:
		scripts.append(_chain_script(step))
	var straight := _constant(scripts[0], "STRAIGHT")
	var no_prop: int = scripts[0].get_script_constant_map()["NO_PROP"]
	var gardens := 0
	var straights := 0
	for chain_seed in range(1, PLAN_SEEDS + 1):
		if chain_seed % 20 == 0:
			await process_frame
		var runs: Array[Array] = []
		for script in scripts:
			runs.append(_plans_to_goal(script, chain_seed))
		var base := runs[0]
		var garden_run := runs[1]
		_expect(failures, base.size() == garden_run.size(), "seed %d: %d rooms in step 0, %d in step 1" % [chain_seed, base.size(), garden_run.size()])
		for i in range(2, runs.size()):
			_expect(failures, runs[i].size() == garden_run.size(), "seed %d: %s plans %d rooms, step 1 plans %d" % [chain_seed, STEPS[i], runs[i].size(), garden_run.size()])
			for k in mini(runs[i].size(), garden_run.size()):
				_expect(failures, runs[i][k].garden == garden_run[k].garden, "seed %d room %d: %s decides the garden another way than step 1" % [chain_seed, k, STEPS[i]])
		var last_garden := -10
		for k in mini(base.size(), garden_run.size()):
			var a: Object = base[k]
			var b: Object = garden_run[k]
			if a.type == straight:
				straights += 1
			var same: bool = a.type == b.type and a.transform == b.transform and a.bounds == b.bounds and a.locked == b.locked and a.key_spot == b.key_spot and a.lamp == b.lamp
			_expect(failures, same, "seed %d room %d: the garden moved the room, its lock, its key or its lamp" % [chain_seed, k])
			if not b.garden:
				_expect(failures, a.props == b.props, "seed %d room %d: a room that is no garden has other props" % [chain_seed, k])
				continue
			gardens += 1
			_expect(failures, b.type == straight, "seed %d room %d: a garden that is no straight room" % [chain_seed, k])
			_expect(failures, k != 0, "seed %d: room 0 is a garden" % chain_seed)
			_expect(failures, k - last_garden >= 3, "seed %d: gardens in rooms %d and %d stand at the same time" % [chain_seed, last_garden, k])
			_expect(failures, b.props.all(func(prop: int) -> bool: return prop == no_prop), "seed %d room %d: a garden holds props" % [chain_seed, k])
			last_garden = k
		if failures.size() > 8:
			return failures
	_expect(failures, gardens >= 150 and gardens <= 400, "%d gardens in %d seeds: far from the 40 %% chance a straight room has, less what the gap takes" % [gardens, PLAN_SEEDS])
	_expect(failures, straights > gardens, "%d gardens among %d straight rooms" % [gardens, straights])
	return failures

#endregion

#region The garden scene (steps 1 to 3)

func test_garden_scene(step: String) -> Array[String]:
	var failures: Array[String] = []
	var garden := (load("res://steps/%s/room_garden.tscn" % step) as PackedScene).instantiate()
	var straight := (load("res://steps/%s/room_straight.tscn" % step) as PackedScene).instantiate()
	_expect(failures, not garden.has_node("Ceiling"), "the garden has a ceiling")
	for child in garden.get_node("Shell").get_children():
		var csg := child as CSGBox3D
		if csg != null and csg.operation == CSGShape3D.OPERATION_UNION:
			var top := csg.position.y + csg.size.y / 2.0
			_expect(failures, top <= WALL_TOP + 0.05, "%s reaches %.2f m, the walls end at %.1f" % [csg.name, top, WALL_TOP])
	for marker: String in ["Entrance", "Exit"]:
		_expect(failures, (garden.get_node(marker) as Marker3D).transform == (straight.get_node(marker) as Marker3D).transform, "the %s of the garden is not the one of a straight room" % marker)
	var garden_box := garden.get_node("Inside/CollisionShape3D") as CollisionShape3D
	var straight_box := straight.get_node("Inside/CollisionShape3D") as CollisionShape3D
	_expect(failures, garden_box.transform == straight_box.transform and (garden_box.shape as BoxShape3D).size == (straight_box.shape as BoxShape3D).size, "the box of the garden is not the one of a straight room")
	var garden_keys := garden.get_node("KeySpots").get_children()
	var straight_keys := straight.get_node("KeySpots").get_children()
	_expect(failures, garden_keys.size() == straight_keys.size(), "the garden has %d key spots, a straight room %d" % [garden_keys.size(), straight_keys.size()])
	for i in mini(garden_keys.size(), straight_keys.size()):
		_expect(failures, (garden_keys[i] as Marker3D).transform == (straight_keys[i] as Marker3D).transform, "key spot %d of the garden is not the one of a straight room" % i)
	_expect(failures, garden.get_node("LampSpots").get_child_count() == 0, "the garden has lamp spots: its light is the sun")
	_expect(failures, garden.get_node("PropSpots").get_child_count() == 0, "the garden has prop spots: it holds no furniture")
	_expect(failures, garden.has_node("Shell/WallEntrance/Opening") and garden.has_node("Shell/WallFar/Doorway"), "the garden has no cut-out in its entrance or far wall")
	var suns := garden.find_children("*", "DirectionalLight3D", true, false)
	_expect(failures, suns.size() == 1, "%d suns in the garden, expected 1" % suns.size())
	if suns.size() == 1:
		var sun := suns[0] as DirectionalLight3D
		_expect(failures, sun.shadow_enabled, "the sun casts no shadows")
		_expect(failures, is_zero_approx(sun.light_volumetric_fog_energy), "the sun lights the volumetric fog (%s): it would haze every room in reach" % sun.light_volumetric_fog_energy)
		_expect(failures, sun.directional_shadow_max_distance >= 30.0, "shadow distance %s m: the walls and the trees would lose their shadows" % sun.directional_shadow_max_distance)
		_expect(failures, (-sun.transform.basis.z).y < -0.3, "the sun's light runs %s: it does not come from above" % (-sun.transform.basis.z))
	for scene_name: String in ["room_straight", "room_long", "room_wide", "room_vault", "room_turn_left", "room_turn_right", "room_goal"]:
		var room := (load("res://steps/%s/%s.tscn" % [step, scene_name]) as PackedScene).instantiate()
		_expect(failures, room.find_children("*", "DirectionalLight3D", true, false).is_empty(), "%s has a sun: only the garden has one" % scene_name)
		room.free()
	var script_path := (garden.get_script() as Script).resource_path
	_expect(failures, script_path.ends_with("/garden.gd") == (step != "step_01_garden"), "the garden's script is %s in %s" % [script_path, step])
	garden.free()
	straight.free()
	return failures

#endregion

#region The environment (steps 1 to 3)

## The world environment of a step's main scene, and the two moods: step 1 has one environment inside main.tscn (the one of tutorial 08), steps 2 and 3 two files.
func test_environment(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main_path := "res://steps/%s/main.tscn" % step
	var main := (load(main_path) as PackedScene).instantiate()
	var worlds := main.find_children("*", "WorldEnvironment", true, false)
	_expect(failures, worlds.size() == 1, "%d WorldEnvironment nodes in main.tscn, expected 1" % worlds.size())
	if worlds.size() != 1:
		main.free()
		return failures
	var world := worlds[0] as WorldEnvironment
	for path in _files_in("res://steps/" + step, ".tscn"):
		_expect(failures, path == main_path or not FileAccess.get_file_as_string(path).contains("type=\"WorldEnvironment\""), "%s has a WorldEnvironment of its own" % path)
	for cam: Node in main.find_children("*", "Camera3D", true, false):
		_expect(failures, (cam as Camera3D).environment == null, "camera %s has an environment of its own: it would hide the world environment" % cam.name)
	var inside: Environment
	if step == "step_01_garden":
		inside = world.environment # tutorial 08's, unchanged: no sky, a near black background, the flat blue grey ambient light
		_expect(failures, inside.background_mode == Environment.BG_COLOR and inside.sky == null, "step 1 shows a sky: the world is the one of tutorial 08")
		_expect(failures, inside.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR, "step 1 has another ambient source than a colour")
	else:
		inside = load("res://steps/%s/inside.tres" % step) as Environment
		var outside := load("res://steps/%s/outside.tres" % step) as Environment
		_expect(failures, world.get_script() != null and (world.get_script() as Script).resource_path.ends_with("/atmosphere.gd"), "the WorldEnvironment has no atmosphere script")
		_expect(failures, world.get("inside") == inside and world.get("outside") == outside, "the atmosphere does not point at inside.tres and outside.tres")
		_expect(failures, inside.background_mode == Environment.BG_SKY and outside.background_mode == Environment.BG_SKY and inside.sky == outside.sky and inside.sky != null, "the two moods do not share one sky")
		_expect(failures, inside.ambient_light_source == Environment.AMBIENT_SOURCE_SKY and outside.ambient_light_source == Environment.AMBIENT_SOURCE_SKY, "the ambient light of a mood does not come from the sky, so its share could not change")
		_expect(failures, is_equal_approx(inside.ambient_light_sky_contribution, 0.0) and is_equal_approx(outside.ambient_light_sky_contribution, 1.0), "the sky's share of the ambient light is %s inside and %s outside, expected 0 and 1" % [inside.ambient_light_sky_contribution, outside.ambient_light_sky_contribution])
		_expect(failures, is_equal_approx(inside.ambient_light_energy, 0.02) and is_equal_approx(outside.ambient_light_energy, 1.0), "ambient energy is %s inside and %s outside, expected 0.02 and 1" % [inside.ambient_light_energy, outside.ambient_light_energy])
		_expect(failures, is_equal_approx(outside.fog_density, 0.003) and is_equal_approx(outside.volumetric_fog_density, 0.01), "outside fog is %s and %s, expected 0.003 and 0.01" % [outside.fog_density, outside.volumetric_fog_density])
		_expect(failures, outside.fog_light_color.b > outside.fog_light_color.r and outside.fog_light_color.get_luminance() > 0.5, "the fog of the outside mood %s is no light blue" % outside.fog_light_color)
		for property: String in ["tonemap_mode", "glow_enabled", "glow_strength", "sdfgi_enabled", "sdfgi_cascades", "sdfgi_use_occlusion", "sdfgi_read_sky_light", "fog_enabled", "volumetric_fog_enabled", "volumetric_fog_length", "fog_sky_affect"]:
			_expect(failures, inside.get(property) == outside.get(property), "%s differs between the moods: it is a switch, and switches do not blend" % property)
	# The inside mood is tutorial 08's look: the numbers its narration named.
	_expect(failures, is_equal_approx(inside.ambient_light_energy, 0.02), "ambient energy %s, expected 0.02" % inside.ambient_light_energy)
	_expect(failures, inside.ambient_light_color.b > inside.ambient_light_color.r and inside.ambient_light_color.b > inside.ambient_light_color.g, "the ambient colour %s is not bluish" % inside.ambient_light_color)
	_expect(failures, inside.tonemap_mode == Environment.TONE_MAPPER_FILMIC, "tone mapper is %d, expected filmic" % inside.tonemap_mode)
	_expect(failures, inside.fog_enabled and is_equal_approx(inside.fog_density, 0.03), "fog density is %s, expected 0.03" % inside.fog_density)
	_expect(failures, inside.volumetric_fog_enabled and is_equal_approx(inside.volumetric_fog_density, 0.07) and is_equal_approx(inside.volumetric_fog_length, 30.0), "volumetric fog is %s over %s m, expected 0.07 over 30" % [inside.volumetric_fog_density, inside.volumetric_fog_length])
	_expect(failures, inside.glow_enabled and is_equal_approx(inside.glow_strength, 2.0), "glow strength is %s, expected 2.0" % inside.glow_strength)
	_expect(failures, inside.sdfgi_enabled and inside.sdfgi_use_occlusion and not inside.sdfgi_read_sky_light and inside.sdfgi_cascades == 2, "SDFGI is not the one of tutorial 08")
	if step != "step_01_garden":
		_expect(failures, is_zero_approx(inside.fog_sky_affect), "fog_sky_affect is %s: the fog would swallow the sky" % inside.fog_sky_affect)
	main.free()
	var player := (load("res://steps/%s/player.tscn" % step) as PackedScene).instantiate()
	for cam: Node in player.find_children("*", "Camera3D", true, false):
		_expect(failures, (cam as Camera3D).environment == null, "the player's camera has an environment of its own")
	player.free()
	return failures

#endregion

#region Openness and blend (steps 2 and 3)

## One garden in the tree at a place and a heading of its own: the openness of a point depends on nothing but the point.
func test_openness(step: String) -> Array[String]:
	var failures: Array[String] = []
	var garden := (load("res://steps/%s/room_garden.tscn" % step) as PackedScene).instantiate() as Node3D
	garden.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(12.0, 0.0, -30.0))
	root.add_child(garden)
	await process_frame
	_expect(failures, garden.is_in_group("outdoors"), "the garden is not in the group outdoors")
	# Local points: where, and the openness there. 0.5 at a door plane, 1.5 m on each side to the ends.
	var points: Array[Array] = [
		[Vector3(0.0, EYE_HEIGHT, 0.0), 1.0], # the middle of the garden
		[Vector3(3.0, EYE_HEIGHT, 4.0), 0.5 + 1.0 / 3.0], # near the wall, still inside
		[Vector3(0.0, EYE_HEIGHT, 3.5), 1.0], # 1.5 m in from the entrance plane: fully open
		[Vector3(0.0, EYE_HEIGHT, 4.25), 0.75],
		[Vector3(0.0, EYE_HEIGHT, 5.0), 0.5], # in the entrance plane
		[Vector3(0.0, EYE_HEIGHT, -5.0), 0.5], # in the exit plane
		[Vector3(0.0, EYE_HEIGHT, 6.0), 0.5 - 1.0 / 3.0], # one metre in front of the entrance, in the room before
		[Vector3(0.0, EYE_HEIGHT, 6.5), 0.0], # 1.5 m: fully closed
		[Vector3(1.0, EYE_HEIGHT, 5.5), 0.5 - 0.5 / 3.0], # still in the strip of the doorway
		[Vector3(3.0, EYE_HEIGHT, 5.5), 0.0], # next to the doorway: that is a wall, and behind it a room
		[Vector3(0.0, EYE_HEIGHT, -6.0), 0.5 - 1.0 / 3.0],
		[Vector3(-3.0, EYE_HEIGHT, -5.5), 0.0],
	]
	var forward: Array[float] = []
	for entry in points:
		var world := garden.to_global(entry[0] as Vector3)
		var value: float = garden.call("openness_at", world)
		forward.append(value)
		_expect(failures, is_equal_approx(value, entry[1] as float), "openness at %s is %.3f, expected %.3f" % [entry[0], value, entry[1]])
	var backward: Array[float] = []
	for i in range(points.size() - 1, -1, -1):
		backward.append(garden.call("openness_at", garden.to_global((points[i] as Array)[0] as Vector3)) as float)
	backward.reverse()
	_expect(failures, forward == backward, "the openness of a point depends on the points asked before it")
	root.remove_child(garden)
	garden.free()
	await process_frame
	return failures

func test_blend(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, false)
	var world := main.get_node("WorldEnvironment") as WorldEnvironment
	world.set_process(false) # no camera moves the mood in this test: the numbers are set by hand
	var inside := world.get("inside") as Environment
	var outside := world.get("outside") as Environment
	var live := world.environment
	_expect(failures, live != inside and live != outside, "the live environment is a saved mood: blending would write into the file")
	_expect(failures, is_equal_approx(world.get("openness"), 0.0), "the atmosphere starts at openness %s, expected 0" % world.get("openness"))
	for amount: float in [0.0, 0.25, 0.5, 1.0, 0.1, 0.0]:
		world.call("apply", amount)
		for property: StringName in BLENDED:
			var ends: Array = BLENDED[property]
			var expected := lerpf(ends[0] as float, ends[1] as float, amount)
			_expect(failures, is_equal_approx(live.get(property) as float, expected), "%s at openness %s is %s, expected %s" % [property, amount, live.get(property), expected])
		var expected_fog := (inside.fog_light_color as Color).lerp(outside.fog_light_color as Color, amount)
		_expect(failures, live.fog_light_color.is_equal_approx(expected_fog), "the fog colour at openness %s is %s, expected %s" % [amount, live.fog_light_color, expected_fog])
		_expect(failures, live.background_mode == inside.background_mode and live.ambient_light_source == inside.ambient_light_source and live.tonemap_mode == inside.tonemap_mode, "a switch changed at openness %s" % amount)
	for property: StringName in BLENDED:
		_expect(failures, is_equal_approx(inside.get(property) as float, (BLENDED[property] as Array)[0] as float), "inside.tres changed its %s" % property)
		_expect(failures, is_equal_approx(outside.get(property) as float, (BLENDED[property] as Array)[1] as float), "outside.tres changed its %s" % property)
	# The sixth number: the Indirect Energy of every sun of the group outdoors, also of a garden that was built after the last change of the openness.
	_expect(failures, is_equal_approx(world.get("sun_indirect_inside") as float, SUN_INDIRECT[0]) and is_equal_approx(world.get("sun_indirect_outside") as float, SUN_INDIRECT[1]), "the sun's Indirect Energy is %s inside and %s outside, expected %s and %s" % [world.get("sun_indirect_inside"), world.get("sun_indirect_outside"), SUN_INDIRECT[0], SUN_INDIRECT[1]])
	var garden := (load("res://steps/%s/room_garden.tscn" % step) as PackedScene).instantiate() as Node3D
	garden.transform = Transform3D(Basis.IDENTITY, Vector3(40.0, 0.0, -60.0))
	root.add_child(garden)
	await process_frame
	var sun := garden.get_node("Sun") as DirectionalLight3D
	_expect(failures, sun.light_indirect_energy == 1.0, "the sun of the scene file has Indirect Energy %s, expected the default 1.0: the number is the atmosphere's" % sun.light_indirect_energy)
	for amount: float in [0.0, 0.25, 0.5, 0.75, 1.0, 0.1, 0.0]:
		world.call("apply", amount)
		var expected_indirect := lerpf(SUN_INDIRECT[0], SUN_INDIRECT[1], smoothstep(0.5, 1.0, amount)) # zero up to the door plane, full from 1.5 m inside
		_expect(failures, is_equal_approx(sun.light_indirect_energy, expected_indirect), "the sun's Indirect Energy at openness %s is %s, expected %s" % [amount, sun.light_indirect_energy, expected_indirect])
	_expect(failures, sun.light_bake_mode == Light3D.BAKE_DYNAMIC, "the sun is not a dynamic light (%s): SDFGI would not follow a change of its Indirect Energy at run time" % sun.light_bake_mode)
	root.remove_child(garden)
	garden.free()
	await _unload(main)
	return failures

#endregion

#region Eyes (step 3)

func test_eyes(step: String) -> Array[String]:
	var failures: Array[String] = []
	var is_final := step == FINAL_STEP
	var main := (load("res://steps/%s/main.tscn" % step) as PackedScene).instantiate()
	var world := main.get_node("WorldEnvironment") as WorldEnvironment
	if is_final:
		var attributes := world.camera_attributes as CameraAttributesPractical
		_expect(failures, attributes != null, "step 3 has no CameraAttributesPractical")
		if attributes != null:
			_expect(failures, attributes.auto_exposure_enabled, "auto exposure is off")
			_expect(failures, is_equal_approx(attributes.auto_exposure_min_sensitivity, MIN_SENSITIVITY), "the lowest sensitivity is %s, expected %s" % [attributes.auto_exposure_min_sensitivity, MIN_SENSITIVITY])
			_expect(failures, is_equal_approx(attributes.auto_exposure_max_sensitivity, 800.0), "the highest sensitivity is %s, expected the default 800" % attributes.auto_exposure_max_sensitivity)
			_expect(failures, is_equal_approx(attributes.auto_exposure_scale, 0.4) and is_equal_approx(attributes.auto_exposure_speed, 0.5), "scale %s and speed %s, expected the defaults 0.4 and 0.5" % [attributes.auto_exposure_scale, attributes.auto_exposure_speed])
	else:
		_expect(failures, world.camera_attributes == null, "%s has camera attributes: eye adaptation is step 3" % step)
	for camera: Node in main.find_children("*", "Camera3D", true, false):
		_expect(failures, (camera as Camera3D).attributes == null, "camera %s has attributes of its own: they would hide the ones of the world" % camera.name)
	main.free()
	if step != "step_00_start":
		var garden := (load("res://steps/%s/room_garden.tscn" % step) as PackedScene).instantiate()
		var sun := garden.find_children("*", "DirectionalLight3D", true, false)[0] as DirectionalLight3D
		_expect(failures, is_equal_approx(sun.light_energy, SUN_ENERGY if is_final else 1.0), "the sun's energy is %s in %s" % [sun.light_energy, step])
		garden.free()
	if step in ["step_02_two_moods", FINAL_STEP]:
		for mood: String in ["inside", "outside"]:
			var environment := load("res://steps/%s/%s.tres" % [step, mood]) as Environment
			_expect(failures, is_equal_approx(environment.background_energy_multiplier, SKY_ENERGY if is_final else 1.0), "the sky's energy of %s is %s in %s" % [mood, environment.background_energy_multiplier, step])
	return failures

#endregion

#region Walking the real player

## Runs tick once per physics tick until it returns true. (With Engine.time_scale above 1
## several ticks happen per frame, and `await physics_frame` would only see one of them.)
func _drive(tick: Callable) -> void:
	var driver := Driver.new()
	driver.process_priority = -100
	driver.tick = tick
	root.add_child(driver)
	await driver.finished
	root.remove_child(driver)
	driver.queue_free()

func test_full_run() -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(FINAL_STEP, true, {"chain_seed": RUN_SEED})
	var level: Node3D = main.get_node("Level")
	var world := main.get_node("WorldEnvironment") as WorldEnvironment
	var pilot := Autopilot.new(level)
	var stats := {"garden_ticks": 0, "most_suns": 0, "peak": 0.0, "ticks": 0, "camera": 0, "gardens_seen": {}}
	_fast_forward(true)
	var budget := [60 * 60 * 5]
	await _drive(func() -> bool:
		pilot.physics_step()
		stats["ticks"] += 1
		if stats["ticks"] % 6 == 0:
			var suns := level.find_children("*", "DirectionalLight3D", true, false).size()
			stats["most_suns"] = maxi(stats["most_suns"], suns)
			stats["camera"] += 1 if root.get_camera_3d() != null else 0
			var plan: Object = level.chain.plans[level.current]
			if plan.garden:
				stats["garden_ticks"] += 1
				stats["gardens_seen"][plan.index] = true
			stats["peak"] = maxf(stats["peak"], world.get("openness") as float)
		budget[0] -= 1
		return level.state == STATE_FINISHED or budget[0] <= 0)
	pilot.release()
	_fast_forward(false)
	_expect(failures, level.state == STATE_FINISHED, "the run did not finish (room %d, %.1f s)" % [level.current, level.run_time])
	_expect(failures, level.current == GOAL_ROOM, "finished in room %d" % level.current)
	_expect(failures, (stats["gardens_seen"] as Dictionary).size() >= 2, "the walk stood in %s gardens, expected at least 2 (rooms 2 and 14 of seed %d)" % [(stats["gardens_seen"] as Dictionary).keys(), RUN_SEED])
	_expect(failures, stats["garden_ticks"] > 0, "the player never stood in a garden")
	_expect(failures, stats["camera"] > 0, "the viewport had no current camera: the atmosphere has nothing to follow")
	_expect(failures, stats["peak"] >= 0.99, "the openness peaked at %.2f, expected 1 in a garden" % stats["peak"])
	_expect(failures, is_zero_approx(world.get("openness")), "the openness is %.2f in the goal room, expected 0" % world.get("openness"))
	_expect(failures, stats["most_suns"] <= 1, "%d suns in the tree at once: two gardens stood together" % stats["most_suns"])
	print("        full run, seed %d: %.2f s of game time, gardens %s, peak openness %.2f, most suns at once %d" % [RUN_SEED, level.run_time, (stats["gardens_seen"] as Dictionary).keys(), stats["peak"], stats["most_suns"]])
	await _unload(main)
	return failures

func test_scene_runs(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, false)
	for i in 30:
		await process_frame
	_expect(failures, is_instance_valid(main) and main.is_inside_tree(), "scene left the tree")
	await _unload(main)
	return failures

#endregion

#region Harness

func _run(test_name: String, test: Callable) -> void:
	if not _selected(test_name):
		return
	await process_frame # the engine empties its message queue between tests: the chain tests build thousands of room scenes
	var failures: Array[String] = await test.call()
	_report(test_name, failures)

func _selected(test_name: String) -> bool:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only=") and not test_name.contains(argument.trim_prefix("--only=")):
			return false
	return true

func _steps_from(first: String) -> Array[String]:
	var result: Array[String] = []
	for step: String in STEPS.slice(STEPS.find(first)):
		result.append(step)
	return result

func _report(test_name: String, failures: Array[String]) -> void:
	var script_errors := _script_errors.count - _script_errors_reported
	_script_errors_reported = _script_errors.count
	if script_errors > 0: # the test stopped at the failing line and the engine returned an empty array, which would read as a pass
		failures.insert(0, "the test stopped with a script error: see the log")
	if failures.is_empty():
		_passed += 1
		print("PASS  ", test_name)
		return
	_failed += 1
	print("FAIL  ", test_name)
	for message: String in failures.slice(0, 8):
		print("        ", message)
	if failures.size() > 8:
		print("        ... and %d more" % (failures.size() - 8))

func _skip(test_name: String, reason: String) -> void:
	_skipped += 1
	print("SKIP  ", test_name)
	print("        ", reason)

func _expect(failures: Array[String], condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

## Instances a step's main scene. By default it waits until the CSG shapes have built their collision.
## props are set on the Level before it enters the tree (goal_room, seed_text, lock_chance ...; "chain_seed" is the
## text of the seed's digits).
## Every level gets a fresh temporary save file unless props bring one.
func _load_step(step: String, settle := true, props := {}) -> Node:
	var scene: PackedScene = load("res://steps/%s/main.tscn" % step)
	var main := scene.instantiate()
	var level := main.get_node("Level")
	if not props.has("save_path"):
		level.set("save_path", _fresh_save_path())
	for key: String in props:
		if key == "chain_seed":
			level.set("seed_text", str(props[key]))
		else:
			level.set(key, props[key])
	root.add_child(main)
	if settle:
		await _wait_physics(10)
	return main

func _unload(main: Node) -> void:
	for action: String in ["move_forward", "move_back", "move_left", "move_right", "look_left", "look_right", "look_up", "look_down", "jump", "walk"]:
		Input.action_release(action)
	root.remove_child(main)
	main.free()
	await process_frame

## A path in the temporary test folder that no file exists at.
func _fresh_save_path() -> String:
	_save_counter += 1
	DirAccess.make_dir_recursive_absolute(_save_dir)
	return _save_dir.path_join("best_times_%d.json" % _save_counter)

func _wipe_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(_save_dir):
		return
	for file in DirAccess.get_files_at(_save_dir):
		DirAccess.remove_absolute(_save_dir.path_join(file))
	DirAccess.remove_absolute(_save_dir)

## Runs the simulation faster than real time with the same 1/60 s steps: the engine ticks
## SPEED_UP times as often and hands out SPEED_UP times the delta of each (smaller) tick.
func _fast_forward(on: bool) -> void:
	Engine.physics_ticks_per_second = 60 * (SPEED_UP if on else 1)
	Engine.time_scale = float(SPEED_UP) if on else 1.0

func _wait_physics(frames: int) -> void:
	for i in frames:
		await physics_frame

#endregion
