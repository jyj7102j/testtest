## Base class for test files. Every method named `test_*` is run by
## tests/run_tests.gd; failed assertions are collected, not thrown.
extends RefCounted

const GameData := preload("res://src/core/game_data.gd")
const ShopSim := preload("res://src/core/shop_sim.gd")

## Messages of assertions that failed in the current test.
var failures: Array = []


## Fails when `condition` is false.
func assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


## Fails when `actual` != `expected`.
func assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s (expected %s, got %s)" % [message, str(expected), str(actual)])


## Fails when `value` is outside [lo, hi].
func assert_between(value: float, lo: float, hi: float, message: String) -> void:
	if value < lo or value > hi:
		failures.append("%s (%s not in [%s, %s])" % [message, value, lo, hi])


## A seeded RNG so tests are reproducible.
func make_rng(rng_seed: int = 1234) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	return rng
