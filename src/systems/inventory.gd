## Stock held by the shop. Units are tracked in lots so each one keeps the price it
## was bought at and how many days it has left before it spoils.
extends RefCounted

## days_left value for goods that never spoil.
const NO_EXPIRY := -1.0

## Maximum number of units the shop can hold across all items.
var capacity: int

# Each lot: {"item": String, "qty": int, "unit_cost": float, "days_left": float}
var _lots: Array = []


func _init(p_capacity: int) -> void:
	capacity = p_capacity


## Total units held across every item.
func total_qty() -> int:
	var total := 0
	for lot in _lots:
		total += int(lot["qty"])
	return total


## Units held of one item.
func qty(item_id: String) -> int:
	var total := 0
	for lot in _lots:
		if lot["item"] == item_id:
			total += int(lot["qty"])
	return total


## Units that still fit before capacity is reached.
func free_space() -> int:
	return maxi(capacity - total_qty(), 0)


## Adds up to `amount` units as one lot. Returns how many actually fit.
## A `shelf_life` of 0 or less means the goods never spoil.
func add(item_id: String, amount: int, unit_cost: float, shelf_life: int) -> int:
	var added := mini(amount, free_space())
	if added <= 0:
		return 0
	var days := NO_EXPIRY if shelf_life <= 0 else float(shelf_life)
	_lots.append({"item": item_id, "qty": added, "unit_cost": unit_cost, "days_left": days})
	return added


## Removes up to `amount` units, soonest-to-spoil first.
## Returns {"qty": units removed, "cost": total purchase cost of those units}.
func remove(item_id: String, amount: int) -> Dictionary:
	var candidates: Array = []
	for lot in _lots:
		if lot["item"] == item_id:
			candidates.append(lot)
	candidates.sort_custom(func(a, b): return _expiry_key(a) < _expiry_key(b))

	var removed := 0
	var cost := 0.0
	for lot in candidates:
		if removed >= amount:
			break
		var take := mini(int(lot["qty"]), amount - removed)
		lot["qty"] = int(lot["qty"]) - take
		removed += take
		cost += take * float(lot["unit_cost"])
	_drop_empty()
	return {"qty": removed, "cost": cost}


## Average purchase cost per unit of an item, or 0 when none is held.
func average_cost(item_id: String) -> float:
	var units := 0
	var cost := 0.0
	for lot in _lots:
		if lot["item"] == item_id:
			units += int(lot["qty"])
			cost += int(lot["qty"]) * float(lot["unit_cost"])
	return cost / units if units > 0 else 0.0


## Fewest days left among an item's lots; NO_EXPIRY when none of them spoil or none are held.
func min_days_left(item_id: String) -> float:
	var best := NO_EXPIRY
	for lot in _lots:
		if lot["item"] != item_id or float(lot["days_left"]) < 0.0:
			continue
		if best < 0.0 or float(lot["days_left"]) < best:
			best = float(lot["days_left"])
	return best


## Ages every perishable lot by `spoil_rate` days and throws away what expired.
## Returns {item_id: spoiled units}.
func age_one_day(spoil_rate: float) -> Dictionary:
	var spoiled := {}
	for lot in _lots:
		if float(lot["days_left"]) < 0.0:
			continue
		lot["days_left"] = float(lot["days_left"]) - spoil_rate
		if float(lot["days_left"]) <= 0.0001:
			spoiled[lot["item"]] = int(spoiled.get(lot["item"], 0)) + int(lot["qty"])
			lot["qty"] = 0
	_drop_empty()
	return spoiled


## Removes `fraction` of every lot (rounded down). Returns total units lost.
func steal(fraction: float) -> int:
	var lost := 0
	for lot in _lots:
		var take := int(floor(int(lot["qty"]) * fraction))
		lot["qty"] = int(lot["qty"]) - take
		lost += take
	_drop_empty()
	return lost


func _expiry_key(lot: Dictionary) -> float:
	return 1.0e9 if float(lot["days_left"]) < 0.0 else float(lot["days_left"])


func _drop_empty() -> void:
	_lots = _lots.filter(func(lot): return int(lot["qty"]) > 0)
