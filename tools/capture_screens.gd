## Launches the real UI, drives it through each screen and saves screenshots to
## production/qa/evidence/. Needs a display (e.g. xvfb-run); not headless.
## Run: godot --path . --resolution 1280x720 -s res://tools/capture_screens.gd
extends SceneTree

const MAIN_SCENE := "res://src/ui/main.tscn"
const OUT_DIR := "res://production/qa/evidence"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var main: Control = load(MAIN_SCENE).instantiate()
	root.add_child(main)
	await _frames(5)
	await _shot("01_title")

	for type_id in main._data.shop_type_ids():
		main._start_game(type_id)
		var sim = main._sim
		await _frames(3)
		await _shot("02_%s_prep" % type_id)

		for item_id in sim.buyable_items():
			sim.buy_stock(item_id, 8)
		if sim.can_travel():
			sim.travel(sim.market.city_ids()[1])
		main._refresh()
		main._on_open()
		main._timer.stop()
		# Serve customers until the first haggle (or 12 customers) so the panel shows.
		for i in 12:
			if not sim.has_next_customer():
				break
			sim.next_customer()
			if not sim.pending_haggle.is_empty():
				break
		main._refresh()
		await _frames(3)
		await _shot("03_%s_open" % type_id)

		sim.run_auto_day()
		await _frames(3)
		await _shot("04_%s_day_closed" % type_id)
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(OUT_DIR.path_join("ui_%s.png" % name))
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
