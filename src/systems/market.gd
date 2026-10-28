## Market prices. Every item has a price multiplier per city that drifts as a
## mean-reverting random walk, and market events temporarily scale prices, demand
## and foot traffic. Shops without travel use a single implicit city.
extends RefCounted

## City id used when the shop type defines no cities.
const LOCAL_CITY := "local"

## Events running now: {"id", "text", "item" ("" = every item), "days_left",
## "price_mult", "demand_mult", "traffic_mult"}.
var active_events: Array = []

var _items: Dictionary
var _cities: Dictionary
var _balance: Dictionary
var _rng: RandomNumberGenerator
# city_id -> {item_id: float}
var _mult: Dictionary = {}


func _init(items: Dictionary, cities: Dictionary, balance: Dictionary, rng: RandomNumberGenerator) -> void:
	_items = items
	_cities = cities if not cities.is_empty() else {LOCAL_CITY: {"name": "", "price_bias": {}}}
	_balance = balance
	_rng = rng
	for city_id in _cities:
		_mult[city_id] = {}
		for item_id in _items:
			_mult[city_id][item_id] = 1.0


## Ids of every city, in data order.
func city_ids() -> Array:
	return _cities.keys()


## Display name of a city.
func city_name(city_id: String) -> String:
	return String(_cities[city_id].get("name", city_id))


## Current random-walk multiplier for an item in a city (1.0 = base price).
func multiplier(city_id: String, item_id: String) -> float:
	return float(_mult[city_id][item_id])


## Fair value of one unit in a city: base price × city bias × drift × events.
## Customers judge the shop's asking price against this.
func reference_price(item_id: String, city_id: String) -> float:
	var bias := float(_cities[city_id].get("price_bias", {}).get(item_id, 1.0))
	return float(_items[item_id]["base_price"]) * bias * multiplier(city_id, item_id) \
			* _event_factor(item_id, "price_mult")


## Wholesale price the shop pays per unit (at least 1).
func buy_price(item_id: String, city_id: String) -> int:
	return maxi(1, roundi(reference_price(item_id, city_id)))


## Demand scale for an item from running events.
func demand_mult(item_id: String) -> float:
	return _event_factor(item_id, "demand_mult")


## Foot-traffic scale from running events.
func traffic_mult() -> float:
	var f := 1.0
	for ev in active_events:
		f *= float(ev.get("traffic_mult", 1.0))
	return f


## Moves the market forward one day: drifts every multiplier, ends finished events
## and rolls new ones from `event_defs`. Returns the events that fired today; an
## event with a "steal_fraction" key is for the shop to resolve.
func advance_day(event_defs: Dictionary, shop_type_id: String) -> Array:
	var reversion := float(_balance["market_mean_reversion"])
	var lo := float(_balance["market_min_mult"])
	var hi := float(_balance["market_max_mult"])
	for city_id in _mult:
		for item_id in _mult[city_id]:
			var vol := float(_items[item_id].get("volatility", 0.0))
			if vol <= 0.0:
				continue
			var m := float(_mult[city_id][item_id])
			m += reversion * (1.0 - m) + _rng.randfn(0.0, vol)
			_mult[city_id][item_id] = clampf(m, lo, hi)

	var still_running: Array = []
	for ev in active_events:
		ev["days_left"] = int(ev["days_left"]) - 1
		if int(ev["days_left"]) > 0:
			still_running.append(ev)
	active_events = still_running

	var fired: Array = []
	for event_id in event_defs:
		if String(event_id).begins_with("_"):
			continue
		var def: Dictionary = event_defs[event_id]
		var allowed: Array = def.get("shop_types", [])
		if not allowed.is_empty() and not allowed.has(shop_type_id):
			continue
		if _rng.randf() >= float(def["chance"]):
			continue
		var item_id := ""
		if def.get("target", "all") == "random_item":
			var keys := _items.keys()
			item_id = keys[_rng.randi_range(0, keys.size() - 1)]
		var item_name := String(_items[item_id]["name"]) if item_id != "" else ""
		var ev := {
			"id": event_id,
			"text": String(def.get("text", event_id)).format({"item": item_name}),
			"item": item_id,
			"days_left": int(def.get("duration", 0)),
			"price_mult": float(def.get("price_mult", 1.0)),
			"demand_mult": float(def.get("demand_mult", 1.0)),
			"traffic_mult": float(def.get("traffic_mult", 1.0)),
		}
		if def.has("steal_fraction"):
			ev["steal_fraction"] = float(def["steal_fraction"])
		if int(ev["days_left"]) > 0:
			active_events.append(ev)
		fired.append(ev)
	return fired


func _event_factor(item_id: String, key: String) -> float:
	var f := 1.0
	for ev in active_events:
		if ev["item"] == "" or ev["item"] == item_id:
			f *= float(ev.get(key, 1.0))
	return f
