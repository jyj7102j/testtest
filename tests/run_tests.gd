## Minimal headless test runner (no addon needed).
## Run: godot --headless --path . -s res://tests/run_tests.gd
## Exits 0 when every test passes, 1 otherwise.
extends SceneTree

const TEST_DIRS := ["res://tests/unit", "res://tests/integration"]


func _initialize() -> void:
	var passed := 0
	var failed := 0
	for dir_path in TEST_DIRS:
		for file in DirAccess.get_files_at(dir_path):
			if not file.ends_with("_test.gd"):
				continue
			var path: String = dir_path.path_join(file)
			var script: GDScript = load(path)
			if script == null:
				printerr("FAIL  %s: could not load" % path)
				failed += 1
				continue
			for method in script.get_script_method_list():
				var name: String = method["name"]
				if not name.begins_with("test_"):
					continue
				var suite = script.new()
				suite.call(name)
				if suite.failures.is_empty():
					passed += 1
					print("ok    %s::%s" % [file, name])
				else:
					failed += 1
					printerr("FAIL  %s::%s" % [file, name])
					for message in suite.failures:
						printerr("        - %s" % message)
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
