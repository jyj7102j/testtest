# Data files — schema

All gameplay numbers live here. Keys are `snake_case`; keys starting with `_` are
comments and are ignored by the loader (`src/core/game_data.gd`).

> Export note: these are plain JSON, not imported resources. When you create an
> export preset, add `*.json` to **Resources → Filters to export non-resource files**.

## `shop_types.json` — one entry per playable shop type

| Key | Type | Meaning |
|---|---|---|
| `name`, `description` | string | Shown on the title screen |
| `start_money` | number | Money on day 1 (원) |
| `goal_money` | number | Win when money reaches this |
| `daily_rent` | number | Charged at every close of day |
| `base_traffic` | number | Customers per day at reputation 50, before modifiers |
| `storage_capacity` | int | Units the shop can hold before upgrades |
| `customer_types` | string[] | Ids from `customer_types.json` that visit this shop |
| `travel` | bool | Shop can move between `cities` (default false) |
| `cities` | object | `{city_id: {name, price_bias: {item_id: multiplier}}}`; only with `travel` |
| `travel_cost` | number | Money per trip, before upgrades |
| `items` | object | `{item_id: item}` — see below |
| `upgrades` | string[] | Ids from `shop_upgrades.json` this shop can buy |

Item:

| Key | Type | Meaning |
|---|---|---|
| `name` | string | Display name |
| `base_price` | number | Fair value per unit at market multiplier 1.0 |
| `volatility` | number | Std-dev of the daily random-walk step (0 = price never drifts) |
| `shelf_life` | int | Days before a bought unit spoils; 0 = never |
| `demand` | number | Relative chance a customer wants this item |
| `sellable` | bool | false for ingredients customers cannot buy (default true) |
| `recipe` | object | `{ingredient_id: qty per unit}` — item is made, not bought |

## `customer_types.json`

| Key | Meaning |
|---|---|
| `weight` | Relative chance this type walks in |
| `budget_mult` | Wallet = fair value × budget_mult × wanted qty × 1.2 |
| `max_markup` | Highest price / fair value they accept without haggling |
| `haggle_chance` | Chance-weight of haggling even at an acceptable price (× 0.3) |
| `patience` | Refused counter-offers before they walk out |
| `buy_qty` | `[min, max]` units wanted |

## `shop_upgrades.json`

`cost`, optional `requires` (another upgrade id), and `effects`, summed over owned upgrades:
`storage` (+units), `traffic_mult` (+fraction of customers), `reputation_gain` (+fraction per
sale), `spoil_slow` (fraction of a day perishables do not age, max 0.9), `auto_haggle` (>0: a
clerk answers haggles), `extra_rent` (+daily cost), `max_markup_bonus` (customers tolerate
+this × value), `travel_cost_mult` (−fraction of trip cost), `event_protect` (>0: blocks theft).

## `market_events.json`

`chance` per day, `target` (`random_item` | `all`), `duration` days, and multipliers
`price_mult`, `demand_mult`, `traffic_mult`. `steal_fraction` removes that share of every stock
lot. `shop_types` limits the event to those shop types. `text` may use `{item}`.

## `sim_balance.json`

| Key | Meaning |
|---|---|
| `market_mean_reversion` | How strongly multipliers pull back to 1.0 each day |
| `market_min_mult`, `market_max_mult` | Multiplier clamp |
| `reputation_start`, `reputation_min`, `reputation_max` | Reputation range (traffic neutral at 50) |
| `reputation_on_sale`, `reputation_on_walkout`, `reputation_on_stockout` | Reputation change per event |
| `reputation_traffic_weight` | Traffic × (1 + weight × (reputation − 50)) |
| `haggle_discount_ask` | `[min, max]` fraction of asking price a haggler offers |
| `haggle_accept_margin` | Extra tolerance when answering a counter-offer |
| `default_markup` | Asking price = fair value × this, until the player sets one |
| `unstocked_want_weight` | Demand weight multiplier for items currently out of stock |
| `day_customer_variance` | ± random fraction on the day's customer count |
