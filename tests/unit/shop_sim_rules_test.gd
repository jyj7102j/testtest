extends "res://tests/test_suite.gd"


func _sim(shop_type: String = "convenience") -> ShopSim:
	return ShopSim.new(GameData.new(), shop_type, 777)


func test_buy_stock_limited_by_money() -> void:
	var sim := _sim()
	sim.money = 25.0
	var price := sim.get_buy_price("battery")
	var bought := sim.buy_stock("battery", 100)
	assert_eq(bought, int(25 / price), "only what money allows")
	assert_true(sim.money >= 0.0, "never goes negative from buying")


func test_buy_stock_limited_by_storage() -> void:
	var sim := _sim()
	sim.money = 1.0e6
	assert_eq(sim.buy_stock("ramen", 10000), sim.storage_capacity(), "only what fits")


func test_cannot_buy_recipe_items() -> void:
	var sim := _sim("food_stall")
	assert_eq(sim.buy_stock("tteokbokki", 5), 0, "recipes are made, not bought")


func test_recipe_availability_and_ingredient_use() -> void:
	var sim := _sim("food_stall")
	sim.buy_stock("rice_cake", 5)
	sim.buy_stock("sauce", 1)
	assert_eq(sim.available_qty("tteokbokki"), 1, "limited by sauce")
	sim.buy_stock("sauce", 5)
	assert_eq(sim.available_qty("tteokbokki"), 2, "then by rice cake (5 / 2)")
	sim._sell({"name": "t"}, "tteokbokki", 20, 2)
	assert_eq(sim.inventory.qty("rice_cake"), 1, "2 per dish consumed")
	assert_eq(sim.inventory.qty("sauce"), 4, "1 per dish consumed")


func test_ingredients_not_sellable() -> void:
	var sim := _sim("food_stall")
	assert_true(not sim.sellable_items().has("rice_cake"), "ingredient hidden from customers")
	assert_true(sim.sellable_items().has("tteokbokki"), "dish is sellable")


func test_upgrade_requirements_and_effects() -> void:
	var sim := _sim()
	sim.money = 1.0e6
	var base := sim.storage_capacity()
	assert_true(not sim.buy_upgrade("storage_2"), "needs storage_1 first")
	assert_true(sim.buy_upgrade("storage_1"), "storage_1 bought")
	assert_eq(sim.inventory.capacity, base + 40, "capacity raised")
	assert_true(sim.buy_upgrade("storage_2"), "now allowed")
	assert_true(not sim.buy_upgrade("storage_2"), "not twice")
	assert_true(not sim.buy_upgrade("wagon"), "not offered to a convenience store")


func test_travel_rules() -> void:
	var sim := _sim("trader")
	var start_money := sim.money
	var other: String = sim.market.city_ids()[1]
	assert_true(sim.travel(other), "first trip allowed")
	assert_eq(sim.money, start_money - sim.travel_cost(), "trip costs money")
	assert_true(not sim.travel(sim.market.city_ids()[2]), "only one trip per day")
	assert_true(not _sim().travel("harbor"), "convenience store cannot travel")


func test_haggle_counter_accept() -> void:
	var sim := _sim()
	sim.buy_stock("ramen", 5)
	sim.open_shop()
	var value := sim.market.reference_price("ramen", sim.city)
	var customer := {"name": "t", "max_markup": 1.4, "patience": 2}
	sim.pending_haggle = {"customer": customer, "item": "ramen", "price": 20,
			"value": value, "qty": 2, "offer": 8}
	var money_before := sim.money
	assert_eq(sim.counter_offer(roundi(value * 1.3)), "accept", "fair counter accepted")
	assert_true(sim.pending_haggle.is_empty(), "haggle resolved")
	assert_eq(sim.inventory.qty("ramen"), 3, "2 sold")
	assert_eq(sim.money, money_before + roundi(value * 1.3) * 2, "paid the counter price")


func test_haggle_reject_hurts_reputation() -> void:
	var sim := _sim()
	sim.open_shop()
	sim.pending_haggle = {"customer": {"name": "t"}, "item": "ramen", "price": 20,
			"value": 10.0, "qty": 1, "offer": 8}
	var rep := sim.reputation
	sim.reject_offer()
	assert_true(sim.reputation < rep, "walkout lowers reputation")


func test_close_day_charges_rent_and_advances() -> void:
	var sim := _sim()
	var money := sim.money
	var report := sim.close_day()
	assert_eq(report["rent"], sim.daily_cost(), "rent in report")
	assert_eq(sim.money, money - sim.daily_cost(), "rent paid")
	assert_eq(sim.day, 2, "next day")
	assert_eq(sim.phase, ShopSim.Phase.PREP, "back to prep")


func test_win_and_bankrupt() -> void:
	var sim := _sim()
	sim.money = float(sim.def["goal_money"]) + sim.daily_cost()
	assert_true(sim.close_day()["won"], "goal reached")
	assert_eq(sim.phase, ShopSim.Phase.OVER, "game over after win")
	var broke := _sim()
	broke.money = 0.0
	assert_true(broke.close_day()["bankrupt"], "rent with no money and no stock")
