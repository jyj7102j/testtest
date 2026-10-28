## Balance report: the scripted test player plays every shop type with several
## seeds and prints how each run ended.
## Run: godot --headless --path . -s res://tools/balance_report.gd
extends SceneTree

const GameData := preload("res://src/core/game_data.gd")
const ShopSim := preload("res://src/core/shop_sim.gd")
const ShopBot := preload("res://tests/helpers/shop_bot.gd")

const MAX_DAYS := 120
const SEEDS := [1, 2, 3, 4, 5, 6, 7, 8]


func _initialize() -> void:
	var data := GameData.new()
	for type_id in data.shop_type_ids():
		var wins := 0
		var bankrupt := 0
		var win_days: Array = []
		var day30_money: Array = []
		for rng_seed in SEEDS:
			var sim := ShopSim.new(data, type_id, rng_seed)
			while sim.phase != ShopSim.Phase.OVER and sim.day <= MAX_DAYS:
				ShopBot.prepare_day(sim)
				ShopBot.pick_city(sim)
				sim.run_auto_day()
				if sim.day == 31:
					day30_money.append(roundi(sim.money))
			if sim.is_won():
				wins += 1
				win_days.append(sim.day - 1)
			elif sim.is_bankrupt():
				bankrupt += 1
		print("%-11s 승리 %d/%d (일수 %s) · 파산 %d · 30일차 돈 %s · 목표 %d" % [type_id, wins,
				SEEDS.size(), str(win_days), bankrupt, str(day30_money), data.shop_types[type_id]["goal_money"]])
	quit()
