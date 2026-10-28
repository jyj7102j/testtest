extends "res://tests/test_suite.gd"

const CustomerAI := preload("res://src/systems/customer_ai.gd")


func _ai() -> CustomerAI:
	var data := GameData.new()
	return CustomerAI.new(data.customer_types, data.customer_types.keys(), data.balance, make_rng())


func _customer(haggle_chance: float = 0.0) -> Dictionary:
	return {"type": "t", "name": "손님", "want": "a", "qty": 2, "budget_mult": 1.0,
			"max_markup": 1.4, "haggle_chance": haggle_chance, "patience": 2}


func test_fair_price_buys() -> void:
	var d := _ai().decide(_customer(), 10, 10.0)
	assert_eq(d["action"], "buy", "price at value")
	assert_eq(d["qty"], 2, "buys wanted qty")


func test_far_too_expensive_leaves() -> void:
	assert_eq(_ai().decide(_customer(), 40, 10.0)["action"], "leave", "4x value")


func test_slightly_too_expensive_haggles_below_price() -> void:
	var d := _ai().decide(_customer(), 15, 10.0)
	assert_eq(d["action"], "haggle", "just over the 1.4x limit")
	assert_true(int(d["offer"]) < 15 and int(d["offer"]) >= 1, "offer below asking price")


func test_markup_bonus_raises_tolerance() -> void:
	assert_eq(_ai().decide(_customer(), 15, 10.0, 0.2)["action"], "buy", "clerk bonus makes 1.5x ok")


func test_budget_limits_quantity() -> void:
	var c := _customer()
	c["qty"] = 4
	c["budget_mult"] = 0.3
	var d := _ai().decide(c, 10, 10.0)
	assert_true(int(d["qty"]) < 4, "poor customer buys fewer")


func test_counter_offer_accept_and_patience() -> void:
	var ai := _ai()
	var c := _customer()
	assert_eq(ai.respond_counter(c, 14, 10.0), "accept", "within limit")
	assert_eq(ai.respond_counter(c, 30, 10.0), "again", "first refusal")
	assert_eq(ai.respond_counter(c, 30, 10.0), "leave", "patience runs out")


func test_make_customer_uses_allowed_types() -> void:
	var data := GameData.new()
	var ai := CustomerAI.new(data.customer_types, ["rich"], data.balance, make_rng())
	for i in 20:
		var c := ai.make_customer({"a": 1.0, "b": 0.0})
		assert_eq(c["type"], "rich", "only allowed type")
		assert_eq(c["want"], "a", "zero-weight item never wanted")
	assert_true(ai.make_customer({}).is_empty(), "no items, no customer")


func test_weighted_pick_all_zero() -> void:
	assert_eq(_ai().weighted_pick({"a": 0.0}), "", "nothing to pick")
