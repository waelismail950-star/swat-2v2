extends Node
## Runs every tests/test_*.gd and exits with the number of failed tests as the exit code.

const TEST_DIR := "res://tests/"


func _ready() -> void:
	var failed := 0
	var total := 0
	var files := Array(DirAccess.get_files_at(TEST_DIR)).filter(
			func(f: String) -> bool: return f.begins_with("test_") and f.ends_with(".gd") \
					and f != "test_case.gd" and f != "test_runner.gd")
	files.sort()
	for file: String in files:
		var script: GDScript = load(TEST_DIR + file)
		for method in script.get_script_method_list():
			var test_name: String = method.name
			if not test_name.begins_with("test_"):
				continue
			total += 1
			var case: TestCase = script.new()
			add_child(case)
			await case.call(test_name)
			if case.failures.is_empty():
				print("  ok    %s :: %s" % [file, test_name])
			else:
				failed += 1
				print("  FAIL  %s :: %s" % [file, test_name])
				for failure in case.failures:
					print("          - " + failure)
			case.queue_free()
			await get_tree().physics_frame
	print("\n%d/%d tests passed" % [total - failed, total])
	get_tree().quit(mini(failed, 1))
