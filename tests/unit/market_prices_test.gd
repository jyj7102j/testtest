extends "res://tests/test_suite.gd"

const Market := preload("res://src/systems/market.gd")

const ITEMS := {
	"a": {"name": "A", "base_price": 10, "volatility": 0.2},
	"b": {"name": "B", "base_price": 50, "volatility": 0.0},
}
const CITIES := {
	"x": {"name": "X", "price_bias": {"a": 0.5}},
	"y": {"name": "Y", "price_bias": {"a": 2.0}},
}


func _balance() -> Dictionary:
	return GameData.new().balance


func test_local_city_when_none_defined() -> void:
	var m := Market.new(ITEMS, {}, _balance(), make_rng())
	assert_eq(m.city_ids(), [Market.LOCAL_CITY], "single implicit city")
	assert_eq(m.buy_price("b", Market.LOCAL_CITY), 50, "base price at multiplier 1")


func test_city_bias() -> void:
	var m := Market.new(ITEMS, CITIES, _balance(), make_rng())
	assert_eq(m.buy_price("a", "x"), 5, "cheap city")
	assert_eq(m.buy_price("a", "y"), 20, "expensive city")


func test_multiplier_stays_in_bounds() -> void:
	var balance := _balance()
	var m := Market.new(ITEMS, CITIES, balance, make_rng())
	for i in 500:
		m.advance_day({}, "test")
		for city_id in m.city_ids():
			assert_between(m.multiplier(city_id, "a"), float(balance["market_min_mult"]),
					float(balance["market_max_mult"]), "day %d multiplier" % i)
	assert_eq(m.multiplier("x", "b"), 1.0, "zero-volatility item never moves")


func test_events_scale_prices_and_expire() -> void:
	var m := Market.new(ITEMS, {}, _balance(), make_rng())
	var defs := {"boom": {"chance": 1.0, "target": "all", "price_mult": 2.0, "duration": 2, "text": "boom"}}
	var fired := m.advance_day(defs, "test")
	assert_eq(fired.size(), 1, "event fires at chance 1")
	assert_eq(m.buy_price("b", Market.LOCAL_CITY), 100, "price doubled while active")
	m.advance_day({}, "test")
	m.advance_day({}, "test")
	assert_eq(m.buy_price("b", Market.LOCAL_CITY), 50, "back to normal after duration")


func test_event_shop_type_filter() -> void:
	var m := Market.new(ITEMS, {}, _balance(), make_rng())
	var defs := {"bandits": {"chance": 1.0, "steal_fraction": 0.2, "duration": 0, "shop_types": ["trader"]}}
	assert_true(m.advance_day(defs, "convenience").is_empty(), "filtered out for other shops")
	var fired := m.advance_day(defs, "trader")
	assert_eq(fired.size(), 1, "fires for the listed shop type")
	assert_true(fired[0].has("steal_fraction"), "carries steal fraction")
	assert_true(m.active_events.is_empty(), "zero-duration event is not kept running")


func test_comment_keys_ignored() -> void:
	var m := Market.new(ITEMS, {}, _balance(), make_rng())
	assert_true(m.advance_day({"_comment": "not an event"}, "test").is_empty(), "_ keys skipped")
