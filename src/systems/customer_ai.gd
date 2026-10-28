## Customer behaviour: who walks in, what they want, and how they react to the
## shop's price — buy, walk out, or haggle.
extends RefCounted

var _types: Dictionary = {}
var _balance: Dictionary
var _rng: RandomNumberGenerator


## `allowed_ids` limits customers to the types a shop type lists.
func _init(all_types: Dictionary, allowed_ids: Array, balance: Dictionary, rng: RandomNumberGenerator) -> void:
	for type_id in allowed_ids:
		if all_types.has(type_id):
			_types[type_id] = all_types[type_id]
	_balance = balance
	_rng = rng


## Creates a customer who wants one item picked from `want_weights` ({item_id: weight}).
## Returns an empty Dictionary when nothing can be wanted.
func make_customer(want_weights: Dictionary) -> Dictionary:
	if _types.is_empty() or want_weights.is_empty():
		return {}
	var type_weights := {}
	for type_id in _types:
		type_weights[type_id] = float(_types[type_id].get("weight", 1.0))
	var type_id := weighted_pick(type_weights)
	var want := weighted_pick(want_weights)
	if type_id == "" or want == "":
		return {}
	var t: Dictionary = _types[type_id]
	var qty_range: Array = t.get("buy_qty", [1, 1])
	return {
		"type": type_id,
		"name": String(t.get("name", type_id)),
		"want": want,
		"qty": _rng.randi_range(int(qty_range[0]), int(qty_range[1])),
		"budget_mult": float(t.get("budget_mult", 1.0)),
		"max_markup": float(t.get("max_markup", 1.3)),
		"haggle_chance": float(t.get("haggle_chance", 0.0)),
		"patience": int(t.get("patience", 1)),
	}


## What `customer` does when asked `price` per unit for an item worth `value`.
## `markup_bonus` raises how much over value they tolerate (e.g. a friendly clerk).
## Returns {"action": "buy" | "haggle" | "leave", "qty": int, "offer": int}.
func decide(customer: Dictionary, price: int, value: float, markup_bonus: float = 0.0) -> Dictionary:
	var limit := value * (float(customer["max_markup"]) + markup_bonus)
	var wallet := value * float(customer["budget_mult"]) * int(customer["qty"]) * 1.2
	var qty := mini(int(customer["qty"]), int(floor(wallet / maxf(price, 1))))
	if qty <= 0 or price > limit * 1.25:
		return {"action": "leave", "qty": 0, "offer": 0}

	var wants_deal := _rng.randf() < float(customer["haggle_chance"]) * 0.3
	if price > limit or wants_deal:
		var ask: Array = _balance["haggle_discount_ask"]
		var offer := roundi(minf(limit, price * _rng.randf_range(float(ask[0]), float(ask[1]))))
		offer = clampi(offer, 1, maxi(price - 1, 1))
		return {"action": "haggle", "qty": qty, "offer": offer}
	return {"action": "buy", "qty": qty, "offer": price}


## How `customer` answers the shop's `counter` price during a haggle.
## Each refusal costs one patience. Returns "accept", "again" or "leave".
func respond_counter(customer: Dictionary, counter: int, value: float, markup_bonus: float = 0.0) -> String:
	var limit := value * (float(customer["max_markup"]) + markup_bonus) \
			* (1.0 + float(_balance["haggle_accept_margin"]))
	if counter <= limit:
		return "accept"
	customer["patience"] = int(customer["patience"]) - 1
	return "leave" if int(customer["patience"]) <= 0 else "again"


## Picks a key from {key: weight}; "" when every weight is zero.
func weighted_pick(weights: Dictionary) -> String:
	var total := 0.0
	for key in weights:
		total += maxf(float(weights[key]), 0.0)
	if total <= 0.0:
		return ""
	var roll := _rng.randf() * total
	for key in weights:
		roll -= maxf(float(weights[key]), 0.0)
		if roll <= 0.0:
			return String(key)
	return String(weights.keys()[-1])
