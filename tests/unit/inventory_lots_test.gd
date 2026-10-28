extends "res://tests/test_suite.gd"

const Inventory := preload("res://src/systems/inventory.gd")


func test_add_respects_capacity() -> void:
	var inv := Inventory.new(10)
	assert_eq(inv.add("milk", 7, 5.0, 3), 7, "first add fits")
	assert_eq(inv.add("ramen", 7, 2.0, 0), 3, "second add is cut to free space")
	assert_eq(inv.total_qty(), 10, "inventory is full")
	assert_eq(inv.add("ramen", 1, 2.0, 0), 0, "nothing fits when full")


func test_remove_takes_soonest_expiring_first() -> void:
	var inv := Inventory.new(100)
	inv.add("milk", 5, 10.0, 4)
	inv.add("milk", 5, 20.0, 1)
	var taken := inv.remove("milk", 6)
	assert_eq(taken["qty"], 6, "removes requested units")
	assert_eq(taken["cost"], 5 * 20.0 + 1 * 10.0, "cost basis uses the 1-day lot first")
	assert_eq(inv.qty("milk"), 4, "remaining units")


func test_remove_more_than_held() -> void:
	var inv := Inventory.new(100)
	inv.add("snack", 3, 4.0, 0)
	assert_eq(inv.remove("snack", 10)["qty"], 3, "only held units are removed")
	assert_eq(inv.qty("snack"), 0, "empty after")


func test_spoilage() -> void:
	var inv := Inventory.new(100)
	inv.add("kimbap", 4, 6.0, 2)
	inv.add("ramen", 4, 5.0, 0)
	assert_true(inv.age_one_day(1.0).is_empty(), "nothing spoils after day 1")
	var spoiled := inv.age_one_day(1.0)
	assert_eq(spoiled.get("kimbap", 0), 4, "kimbap spoils after its shelf life")
	assert_eq(inv.qty("ramen"), 4, "non-perishables never spoil")


func test_slower_spoil_rate_extends_life() -> void:
	var inv := Inventory.new(100)
	inv.add("kimbap", 2, 6.0, 1)
	assert_true(inv.age_one_day(0.5).is_empty(), "fridge: half a day used")
	assert_eq(inv.age_one_day(0.5).get("kimbap", 0), 2, "spoils on the second day")


func test_steal_and_average_cost() -> void:
	var inv := Inventory.new(100)
	inv.add("silk", 10, 100.0, 0)
	inv.add("silk", 10, 50.0, 0)
	assert_eq(inv.average_cost("silk"), 75.0, "average of both lots")
	assert_eq(inv.steal(0.2), 4, "20% of each lot of 10")
	assert_eq(inv.qty("silk"), 16, "remaining after theft")
