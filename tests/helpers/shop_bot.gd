## A simple scripted player used by integration tests to play any shop type.
extends RefCounted


## Spends up to `budget_share` of the money on stock, spread evenly over every
## buyable item, and buys an upgrade when it costs under a third of the money.
static func prepare_day(sim, budget_share: float = 0.6) -> void:
	for upgrade_id in sim.available_upgrades():
		var cost := float(sim._data.upgrades[upgrade_id]["cost"])
		if sim.upgrade_block_reason(upgrade_id) == "" and cost * 3.0 < sim.money:
			sim.buy_upgrade(upgrade_id)

	var items: Array = sim.buyable_items()
	if items.is_empty():
		return
	var budget_per_item: float = sim.money * budget_share / items.size()
	var space_per_item := int(sim.inventory.free_space() / items.size())
	for item_id in items:
		var price: int = sim.get_buy_price(item_id)
		var qty := mini(int(budget_per_item / price), space_per_item)
		if qty > 0:
			sim.buy_stock(item_id, qty)


## Travels to the city where the held stock is worth the most (trader only).
static func pick_city(sim) -> void:
	if not sim.can_travel():
		return
	var best_city: String = sim.city
	var best_value := -1.0
	for city_id in sim.market.city_ids():
		var value := 0.0
		for item_id in sim.sellable_items():
			value += sim.inventory.qty(item_id) * sim.market.reference_price(item_id, city_id)
		if value > best_value:
			best_value = value
			best_city = city_id
	if best_city != sim.city and best_value > 0.0:
		sim.travel(best_city)
