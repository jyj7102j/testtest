## Plays every shop type in shop_types.json for many days with a scripted player,
## so a new shop type is covered as soon as it is added to the data.
extends "res://tests/test_suite.gd"

const ShopBot := preload("res://tests/helpers/shop_bot.gd")
const DAYS := 40
const SEEDS := [1, 2, 3]


func test_every_shop_type_plays_without_breaking_invariants() -> void:
	var data := GameData.new()
	assert_true(data.shop_type_ids().size() >= 3, "convenience, trader and food stall exist")
	for type_id in data.shop_type_ids():
		for rng_seed in SEEDS:
			_play(data, type_id, rng_seed)


func test_every_shop_type_references_valid_data() -> void:
	var data := GameData.new()
	for type_id in data.shop_type_ids():
		var def: Dictionary = data.shop_types[type_id]
		for key in ["name", "start_money", "goal_money", "daily_rent", "base_traffic",
				"storage_capacity", "customer_types", "items"]:
			assert_true(def.has(key), "%s has %s" % [type_id, key])
		for customer_id in def["customer_types"]:
			assert_true(data.customer_types.has(customer_id), "%s: customer %s exists" % [type_id, customer_id])
		for upgrade_id in def.get("upgrades", []):
			assert_true(data.upgrades.has(upgrade_id), "%s: upgrade %s exists" % [type_id, upgrade_id])
		for item_id in def["items"]:
			var item: Dictionary = def["items"][item_id]
			assert_true(float(item["base_price"]) > 0.0, "%s.%s has a price" % [type_id, item_id])
			for ingredient in item.get("recipe", {}):
				assert_true(def["items"].has(ingredient), "%s.%s: ingredient %s exists" % [type_id, item_id, ingredient])
		if def.get("travel", false):
			assert_true(def.get("cities", {}).size() >= 2, "%s: travel needs 2+ cities" % type_id)


func _play(data, type_id: String, rng_seed: int) -> void:
	var sim := ShopSim.new(data, type_id, rng_seed)
	var label := "%s seed %d" % [type_id, rng_seed]
	var total_sold := 0
	for i in DAYS:
		if sim.phase == ShopSim.Phase.OVER:
			break
		ShopBot.prepare_day(sim)
		ShopBot.pick_city(sim)
		assert_true(sim.inventory.total_qty() <= sim.storage_capacity(), "%s: storage respected" % label)
		var report := sim.run_auto_day()
		total_sold += int(report["sold"])
		assert_true(not is_nan(sim.money) and not is_inf(sim.money), "%s: money is a number" % label)
		assert_between(sim.reputation, 0.0, 100.0, "%s: reputation" % label)
		assert_true(sim.pending_haggle.is_empty(), "%s: no haggle left open" % label)
		assert_true(int(report["sold"]) >= 0 and float(report["revenue"]) >= 0.0, "%s: report sane" % label)
	assert_true(total_sold > 0, "%s: sold something" % label)
	assert_true(sim.day > 1, "%s: days advanced" % label)
