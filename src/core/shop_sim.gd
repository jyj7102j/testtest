## The whole game state for one run of one shop type, and the day loop:
## PREP (buy stock, set prices, upgrade, travel) → OPEN (serve customers one at a
## time, haggling when they ask) → close_day() (rent, spoilage, market moves).
##
## Example (what the tests do):
##     const GameData := preload("res://src/core/game_data.gd")
##     const ShopSim := preload("res://src/core/shop_sim.gd")
##     var sim := ShopSim.new(GameData.new(), "convenience", 42)
##     sim.buy_stock("ramen", 10)
##     var report := sim.run_auto_day()
extends RefCounted

const Inventory := preload("res://src/systems/inventory.gd")
const Market := preload("res://src/systems/market.gd")
const CustomerAI := preload("res://src/systems/customer_ai.gd")

enum Phase { PREP, OPEN, OVER }

## Every line the player should read (sales, events, warnings).
signal message_logged(text: String)
## Fires after close_day() with the report it returned.
signal day_closed(report: Dictionary)

var shop_type_id: String
## The shop type's entry from shop_types.json.
var def: Dictionary
var money: float
var day: int = 1
var reputation: float
var phase: Phase = Phase.PREP
var city: String
var inventory: Inventory
var market: Market
var owned_upgrades: Array = []
## Haggle waiting for the player's answer; empty when none.
## {"customer", "item", "price", "value", "qty", "offer"}
var pending_haggle: Dictionary = {}

var _data
var _rng := RandomNumberGenerator.new()
var _ai: CustomerAI
var _price_overrides: Dictionary = {}
var _queue: Array = []
var _traveled_today := false
var _today: Dictionary = {}


## `rng_seed` 0 picks a random seed; any other value makes the run reproducible.
func _init(data, p_shop_type_id: String, rng_seed: int = 0) -> void:
	_data = data
	shop_type_id = p_shop_type_id
	def = data.shop_types[p_shop_type_id]
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	money = float(def["start_money"])
	reputation = float(data.balance["reputation_start"])
	inventory = Inventory.new(int(def["storage_capacity"]))
	market = Market.new(def["items"], def.get("cities", {}), data.balance, _rng)
	city = market.city_ids()[0]
	_ai = CustomerAI.new(data.customer_types, def["customer_types"], data.balance, _rng)
	_reset_today()


# --- Items & prices -----------------------------------------------------------

## Every item id of this shop type, in data order.
func item_ids() -> Array:
	return def["items"].keys()


## Display name of an item.
func item_name(item_id: String) -> String:
	return String(def["items"][item_id]["name"])


## True when the item has a recipe and is made from other items instead of bought.
func is_recipe(item_id: String) -> bool:
	return def["items"][item_id].has("recipe")


## True when customers can buy the item (ingredients are not sellable).
func is_sellable(item_id: String) -> bool:
	return bool(def["items"][item_id].get("sellable", true))


## Items customers can buy.
func sellable_items() -> Array:
	return item_ids().filter(func(id): return is_sellable(id))


## Items the shop can buy wholesale.
func buyable_items() -> Array:
	return item_ids().filter(func(id): return not is_recipe(id))


## Wholesale price per unit here today.
func get_buy_price(item_id: String) -> int:
	return market.buy_price(item_id, city)


## Price the shop asks customers per unit: the player's override, or the fair value
## times the default markup.
func get_sell_price(item_id: String) -> int:
	if _price_overrides.has(item_id):
		return int(_price_overrides[item_id])
	return maxi(1, roundi(market.reference_price(item_id, city) * float(_data.balance["default_markup"])))


## Sets the asking price for an item (clamped to at least 1).
func set_sell_price(item_id: String, price: int) -> void:
	_price_overrides[item_id] = maxi(1, price)


## Drops every price override so prices follow the market again.
func reset_prices() -> void:
	_price_overrides.clear()


## Units ready to sell: stock held, or for a recipe how many can be made now.
func available_qty(item_id: String) -> int:
	if not is_recipe(item_id):
		return inventory.qty(item_id)
	var recipe: Dictionary = def["items"][item_id]["recipe"]
	var can_make := -1
	for ingredient in recipe:
		var n := int(inventory.qty(ingredient) / int(recipe[ingredient]))
		can_make = n if can_make < 0 else mini(can_make, n)
	return maxi(can_make, 0)


## Buys up to `qty` units, limited by money and storage. Returns units bought.
func buy_stock(item_id: String, qty: int) -> int:
	if phase != Phase.PREP or is_recipe(item_id) or qty <= 0:
		return 0
	var price := get_buy_price(item_id)
	var affordable := int(floor(money / price))
	var bought := inventory.add(item_id, mini(qty, affordable), float(price),
			int(def["items"][item_id].get("shelf_life", 0)))
	money -= bought * price
	if bought < qty:
		_log("%s %d개만 샀어요 (돈 또는 창고 부족)" % [item_name(item_id), bought])
	return bought


# --- Upgrades -----------------------------------------------------------------

## Sum of one effect over every owned upgrade.
func effect(key: String) -> float:
	var total := 0.0
	for upgrade_id in owned_upgrades:
		total += float(_data.upgrades[upgrade_id].get("effects", {}).get(key, 0.0))
	return total


## Upgrade ids this shop type offers that are not owned yet.
func available_upgrades() -> Array:
	return def.get("upgrades", []).filter(func(id): return not owned_upgrades.has(id))


## Why an upgrade cannot be bought, or "" when it can.
func upgrade_block_reason(upgrade_id: String) -> String:
	var up: Dictionary = _data.upgrades.get(upgrade_id, {})
	if up.is_empty() or not def.get("upgrades", []).has(upgrade_id):
		return "이 가게에서는 살 수 없어요"
	if owned_upgrades.has(upgrade_id):
		return "이미 있어요"
	if up.has("requires") and not owned_upgrades.has(up["requires"]):
		return "%s 먼저 필요해요" % _data.upgrades[up["requires"]]["name"]
	if money < float(up["cost"]):
		return "돈이 부족해요"
	if phase != Phase.PREP:
		return "영업 전에만 살 수 있어요"
	return ""


## Buys an upgrade. Returns false (and logs why) when it cannot.
func buy_upgrade(upgrade_id: String) -> bool:
	var reason := upgrade_block_reason(upgrade_id)
	if reason != "":
		_log(reason)
		return false
	var up: Dictionary = _data.upgrades[upgrade_id]
	money -= float(up["cost"])
	owned_upgrades.append(upgrade_id)
	inventory.capacity = storage_capacity()
	_log("업그레이드 완료: %s" % up["name"])
	return true


## Storage capacity including upgrades.
func storage_capacity() -> int:
	return int(def["storage_capacity"]) + int(effect("storage"))


## Rent charged at the end of each day, including staff wages.
func daily_cost() -> float:
	return float(def["daily_rent"]) + effect("extra_rent")


# --- Travel (shop types with "travel": true) -----------------------------------

## True when this shop type moves between cities.
func can_travel() -> bool:
	return bool(def.get("travel", false))


## Cost of one trip, after upgrades.
func travel_cost() -> int:
	return roundi(float(def.get("travel_cost", 0)) * maxf(0.1, 1.0 + effect("travel_cost_mult")))


## Moves to another city (once per day, before opening). Returns false when not allowed.
func travel(city_id: String) -> bool:
	if not can_travel() or phase != Phase.PREP or _traveled_today \
			or city_id == city or not market.city_ids().has(city_id):
		return false
	if money < travel_cost():
		_log("이동 비용이 부족해요")
		return false
	money -= travel_cost()
	city = city_id
	_traveled_today = true
	reset_prices()
	_log("%s(으)로 이동했어요 (-%d)" % [market.city_name(city_id), travel_cost()])
	return true


# --- Day loop -----------------------------------------------------------------

## Opens the shop: today's customers are generated and wait in a queue.
func open_shop() -> void:
	if phase != Phase.PREP:
		return
	phase = Phase.OPEN
	var balance: Dictionary = _data.balance
	var rep_factor := 1.0 + float(balance["reputation_traffic_weight"]) * (reputation - 50.0)
	var variance := float(balance["day_customer_variance"])
	var count := roundi(float(def["base_traffic"]) * rep_factor * (1.0 + effect("traffic_mult"))
			* market.traffic_mult() * _rng.randf_range(1.0 - variance, 1.0 + variance))

	var weights := {}
	for item_id in sellable_items():
		var w := float(def["items"][item_id].get("demand", 1.0)) * market.demand_mult(item_id)
		if available_qty(item_id) <= 0:
			w *= float(balance["unstocked_want_weight"])
		weights[item_id] = w
	_queue.clear()
	for i in maxi(count, 0):
		var c := _ai.make_customer(weights)
		if not c.is_empty():
			_queue.append(c)
	_today["customers"] = _queue.size()
	_log("영업 시작! 오늘 손님 %d명 예상" % _queue.size())


## True while customers are still waiting and no haggle is pending.
func has_next_customer() -> bool:
	return phase == Phase.OPEN and pending_haggle.is_empty() and not _queue.is_empty()


## Serves the next customer. Returns {"customer", "item", "result"} where result is
## "sold", "left", "stockout" or "haggle" (then pending_haggle waits for the player).
func next_customer() -> Dictionary:
	if not has_next_customer():
		return {}
	var c: Dictionary = _queue.pop_front()
	var item_id: String = c["want"]
	var result := {"customer": c, "item": item_id, "result": ""}
	var available := available_qty(item_id)
	if available <= 0:
		_change_reputation(float(_data.balance["reputation_on_stockout"]))
		_today["stockouts"] = int(_today["stockouts"]) + 1
		_log("%s: %s 없어요? 아쉽네요..." % [c["name"], item_name(item_id)])
		result["result"] = "stockout"
		return result

	var price := get_sell_price(item_id)
	var value := market.reference_price(item_id, city)
	var decision := _ai.decide(c, price, value, effect("max_markup_bonus"))
	var qty := mini(int(decision["qty"]), available)
	match decision["action"]:
		"buy":
			_sell(c, item_id, price, qty)
			result["result"] = "sold"
		"leave":
			_walkout(c, "%s: %s %d원? 너무 비싸요!" % [c["name"], item_name(item_id), price])
			result["result"] = "left"
		"haggle":
			pending_haggle = {"customer": c, "item": item_id, "price": price, "value": value,
					"qty": qty, "offer": int(decision["offer"])}
			_log("%s: %s %d개, 개당 %d원에 안 될까요? (정가 %d원)" % [c["name"],
					item_name(item_id), qty, decision["offer"], price])
			result["result"] = "haggle"
			if effect("auto_haggle") > 0.0:
				var sold_before := int(_today["sold"])
				_auto_haggle()
				result["result"] = "sold" if int(_today["sold"]) > sold_before else "left"
	return result


## Accepts the customer's offer in the pending haggle.
func accept_offer() -> void:
	if pending_haggle.is_empty():
		return
	var h := pending_haggle
	pending_haggle = {}
	_sell(h["customer"], h["item"], int(h["offer"]), int(h["qty"]))


## Answers the pending haggle with `price`. Returns "accept" (sold at `price`),
## "again" (customer still haggling) or "leave".
func counter_offer(price: int) -> String:
	if pending_haggle.is_empty():
		return ""
	var h := pending_haggle
	if price <= int(h["offer"]):
		accept_offer()
		return "accept"
	var answer := _ai.respond_counter(h["customer"], price, float(h["value"]), effect("max_markup_bonus"))
	match answer:
		"accept":
			pending_haggle = {}
			_sell(h["customer"], h["item"], price, int(h["qty"]))
		"leave":
			pending_haggle = {}
			_walkout(h["customer"], "%s: 됐어요, 다른 데 갈게요." % h["customer"]["name"])
		_:
			_log("%s: 음... %d원은 좀 비싸요." % [h["customer"]["name"], price])
	return answer


## Turns down the pending haggle; the customer leaves.
func reject_offer() -> void:
	if pending_haggle.is_empty():
		return
	var c: Dictionary = pending_haggle["customer"]
	pending_haggle = {}
	_walkout(c, "%s: 칫, 안 사요." % c["name"])


## Ends the day: unserved customers leave, rent is paid, stock ages, the market
## moves and events fire. Returns the day's report.
func close_day() -> Dictionary:
	if phase == Phase.OVER:
		return {}
	if not pending_haggle.is_empty():
		reject_offer()
	_queue.clear()

	var rent := daily_cost()
	money -= rent
	var spoil_rate := 1.0 - clampf(effect("spoil_slow"), 0.0, 0.9)
	var spoiled := inventory.age_one_day(spoil_rate)
	var events := market.advance_day(_data.events, shop_type_id)
	for ev in events:
		if ev.has("steal_fraction"):
			if effect("event_protect") > 0.0:
				_log("호위병이 도적을 막아냈어요!")
				continue
			ev["stolen"] = inventory.steal(float(ev["steal_fraction"]))
		_log("[이벤트] %s" % ev["text"])
	for item_id in spoiled:
		_log("%s %d개가 상해서 버렸어요" % [item_name(item_id), spoiled[item_id]])

	var report := _today.duplicate()
	report["day"] = day
	report["rent"] = rent
	report["spoiled"] = spoiled
	report["events"] = events
	report["profit"] = float(report["revenue"]) - float(report["cost"]) - rent
	report["money"] = money

	day += 1
	_traveled_today = false
	_reset_today()
	phase = Phase.OVER if is_won() or is_bankrupt() else Phase.PREP
	report["won"] = is_won()
	report["bankrupt"] = is_bankrupt()
	_log("%d일차 마감: 매출 %d, 원가 %d, 임대료 %d → 순이익 %d" % [report["day"],
			report["revenue"], report["cost"], rent, report["profit"]])
	day_closed.emit(report)
	return report


## Plays the rest of today without a player: opens if needed, counters every haggle
## at `counter_ratio` of the asking price, then closes. Used by tests and fast-forward.
func run_auto_day(counter_ratio: float = 0.95) -> Dictionary:
	open_shop()
	while has_next_customer():
		next_customer()
		while not pending_haggle.is_empty():
			var counter := maxi(int(pending_haggle["offer"]) + 1,
					roundi(float(pending_haggle["price"]) * counter_ratio))
			counter_offer(counter)
	return close_day()


## True once money reaches this shop type's goal.
func is_won() -> bool:
	return money >= float(def["goal_money"])


## True when the shop is in debt with nothing left to sell.
func is_bankrupt() -> bool:
	return money < 0.0 and inventory.total_qty() == 0


# --- Internals ----------------------------------------------------------------

func _sell(customer: Dictionary, item_id: String, price: int, qty: int) -> void:
	var cost := 0.0
	if is_recipe(item_id):
		var recipe: Dictionary = def["items"][item_id]["recipe"]
		for ingredient in recipe:
			cost += float(inventory.remove(ingredient, int(recipe[ingredient]) * qty)["cost"])
	else:
		cost = float(inventory.remove(item_id, qty)["cost"])
	money += price * qty
	_today["revenue"] = float(_today["revenue"]) + price * qty
	_today["cost"] = float(_today["cost"]) + cost
	_today["sold"] = int(_today["sold"]) + qty
	_change_reputation(float(_data.balance["reputation_on_sale"]) * (1.0 + effect("reputation_gain")))
	_log("%s: %s %d개 구매 (+%d원)" % [customer["name"], item_name(item_id), qty, price * qty])


func _walkout(customer: Dictionary, line: String) -> void:
	_change_reputation(float(_data.balance["reputation_on_walkout"]))
	_today["walkouts"] = int(_today["walkouts"]) + 1
	_log(line)


func _auto_haggle() -> void:
	var h := pending_haggle
	var middle := roundi((int(h["offer"]) + int(h["price"])) / 2.0)
	if counter_offer(middle) != "accept" and not pending_haggle.is_empty():
		_log("직원이 손님 제안을 받아들였어요")
		accept_offer()


func _change_reputation(delta: float) -> void:
	reputation = clampf(reputation + delta, float(_data.balance["reputation_min"]),
			float(_data.balance["reputation_max"]))


func _reset_today() -> void:
	_today = {"customers": 0, "sold": 0, "revenue": 0.0, "cost": 0.0, "walkouts": 0, "stockouts": 0}


func _log(text: String) -> void:
	message_logged.emit(text)
