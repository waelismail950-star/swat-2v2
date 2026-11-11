class_name TestCase
extends Node3D
## Base class for headless tests. Any method named test_* is run by the runner;
## each runs on a fresh instance, and may `await`.

var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s (got %.3f, expected %.3f +/- %.3f)" % [message, actual, expected, tolerance])


## Advances the simulation by `seconds` of physics time.
func wait(seconds: float) -> void:
	for i in ceili(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame


## Walks `player` in a straight line to `target` (height ignored).
## Returns false if it does not arrive within `timeout` seconds.
func walk_to(player: Player, target: Vector3, timeout := 6.0) -> bool:
	for i in ceili(timeout * Engine.physics_ticks_per_second):
		var to := target - player.global_position
		to.y = 0.0
		if to.length() < 0.25:
			break
		player.input.yaw = atan2(-to.x, -to.z)
		player.input.move = Vector2(0, 1)
		await get_tree().physics_frame
	player.input.move = Vector2.ZERO
	var miss := target - player.global_position
	miss.y = 0.0
	return miss.length() < 0.25


## Turns `player` to look at `point` and lets the view update.
func look_at_point(player: Player, point: Vector3) -> void:
	var to := point - player.camera.global_position
	player.input.yaw = atan2(-to.x, -to.z)
	player.input.pitch = atan2(to.y, Vector2(to.x, to.z).length())
	await wait(0.05)


## True if nothing solid lies between the two points.
func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()
