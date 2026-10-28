## Loads every JSON data file the simulation reads. All gameplay numbers live in
## these files (see assets/data/data_schema.md), so a new shop type is a data change.
extends RefCounted

const DEFAULT_DIR := "res://assets/data"

var shop_types: Dictionary
var customer_types: Dictionary
var upgrades: Dictionary
var events: Dictionary
var balance: Dictionary


func _init(data_dir: String = DEFAULT_DIR) -> void:
	shop_types = load_json(data_dir.path_join("shop_types.json"))
	customer_types = load_json(data_dir.path_join("customer_types.json"))
	upgrades = load_json(data_dir.path_join("shop_upgrades.json"))
	events = load_json(data_dir.path_join("market_events.json"))
	balance = load_json(data_dir.path_join("sim_balance.json"))


## Ids of every playable shop type, in data order.
func shop_type_ids() -> Array:
	return shop_types.keys().filter(func(id): return not String(id).begins_with("_"))


## Reads a JSON object from `path`; pushes an error and returns {} on failure.
static func load_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Data file missing or empty: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("Data file is not a JSON object: %s" % path)
		return {}
	return parsed
