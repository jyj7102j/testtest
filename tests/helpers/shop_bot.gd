## A simple scripted player used by integration tests and tools/balance_report.gd
## to play any shop type. It stocks for expected demand instead of spending
## everything, so it approximates a careful (not optimal) human player.
extends RefCounted

## Days of demand to keep on hand for goods that spoil / never spoil.
const PERISHABLE_DAYS := 1.0
const DURABLE_DAYS := 2.5
## Average units a customer wants (customer_types buy_qty midpoints are ~1-2).
const UNITS_PER_CUSTOMER := 1.6


## Buys upgrades it can comfortably afford, then restocks toward expected demand.
static func prepare_day(sim) -> void:
	for upgrade_id in sim.available_upgrades():
		var cost := float(sim._data.upgrades[upgrade_id]["cost"])
		if sim.upgrade_block_reason(upgrade_id) == "" and cost * 2.5 < sim.money:
			sim.buy_upgrade(upgrade_id)
	if sim.can_travel():
		_stock_for_trade(sim)
		return
	var need := _expected_units(sim)
	for item_id in sim.buyable_items():
		var shelf_life := int(sim.def["items"][item_id].get("shelf_life", 0))
		var days := PERISHABLE_DAYS if shelf_life > 0 else DURABLE_DAYS
		var target := ceili(float(need.get(item_id, 0.0)) * days)
		var missing: int = target - sim.inventory.qty(item_id)
		if missing > 0:
			sim.buy_stock(item_id, missing)


## Travels to the city where the held stock is worth the most (trader only).
static func pick_city(sim) -> void:
	if not sim.can_travel() or sim.inventory.total_qty() == 0:
		return
	var best_city: String = sim.city
	var best_value := -1.0
	for city_id in sim.market.city_ids():
		var value := 0.0
		for item_id in sim.sellable_items():
			value += sim.inventory.qty(item_id) * sim.market.reference_price(item_id, city_id)
		if city_id != sim.city:
			value -= sim.travel_cost()
		if value > best_value:
			best_value = value
			best_city = city_id
	if best_city != sim.city:
		sim.travel(best_city)


## Expected units of each buyable item used per day, from traffic and demand
## weights; dish demand is converted into ingredient demand through recipes.
static func _expected_units(sim) -> Dictionary:
	var weights := {}
	var total := 0.0
	for item_id in sim.sellable_items():
		weights[item_id] = float(sim.def["items"][item_id].get("demand", 1.0))
		total += weights[item_id]
	var customers: float = float(sim.def["base_traffic"]) * (1.0 + sim.effect("traffic_mult"))
	var need := {}
	for item_id in weights:
		var units: float = customers * UNITS_PER_CUSTOMER * weights[item_id] / maxf(total, 0.001)
		if sim.is_recipe(item_id):
			var recipe: Dictionary = sim.def["items"][item_id]["recipe"]
			for ingredient in recipe:
				need[ingredient] = float(need.get(ingredient, 0.0)) + units * int(recipe[ingredient])
		else:
			need[item_id] = float(need.get(item_id, 0.0)) + units
	return need


## Trader: when the hold is empty, fill it with the goods whose best price in
## another city most exceeds today's buy price here.
static func _stock_for_trade(sim) -> void:
	if sim.inventory.total_qty() > 0:
		return
	var best_item := ""
	var best_ratio := 1.15
	for item_id in sim.buyable_items():
		var here: int = sim.get_buy_price(item_id)
		for city_id in sim.market.city_ids():
			var ratio: float = sim.market.reference_price(item_id, city_id) / here
			if city_id != sim.city and ratio > best_ratio:
				best_ratio = ratio
				best_item = item_id
	if best_item != "":
		var budget: float = sim.money * 0.8 - sim.travel_cost() - sim.daily_cost()
		sim.buy_stock(best_item, int(maxf(budget, 0.0) / sim.get_buy_price(best_item)))
