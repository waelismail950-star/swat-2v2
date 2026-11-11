extends TestCase
## Loads the real main scene, so a script error anywhere in the game fails the suite.


func test_main_scene_runs() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await wait(0.5)
	check(main.is_inside_tree(), "main scene is running")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
