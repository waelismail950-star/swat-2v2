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
