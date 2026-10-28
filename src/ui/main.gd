## Whole game UI, built in code: a title screen that lists every shop type in the
## data, and the shop screen (market table, customer/haggle panel, log, upgrades,
## travel, open/close day). All rules live in ShopSim; this script only displays
## state and forwards clicks.
extends Control

const GameData := preload("res://src/core/game_data.gd")
const ShopSim := preload("res://src/core/shop_sim.gd")

## Seconds between customers at normal and fast speed.
const CUSTOMER_INTERVAL := 0.7
const CUSTOMER_INTERVAL_FAST := 0.15

var _data: GameData
var _sim: ShopSim
var _timer := Timer.new()

var _status_label: Label
var _events_label: Label
var _item_grid: GridContainer
var _log: RichTextLabel
var _haggle_box: VBoxContainer
var _haggle_label: Label
var _counter_spin: SpinBox
var _open_button: Button
var _close_button: Button
var _fast_check: CheckBox
var _upgrade_option: OptionButton
var _travel_option: OptionButton
var _travel_row: HBoxContainer
var _buy_qty_spin: SpinBox


func _ready() -> void:
	_data = GameData.new()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_timer.one_shot = false
	_timer.timeout.connect(_on_customer_tick)
	add_child(_timer)
	_show_title()


# --- Title screen -------------------------------------------------------------

func _show_title() -> void:
	_timer.stop()
	_clear()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := Label.new()
	title.text = "장사 시뮬레이터"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var hint := Label.new()
	hint.text = "장사 종류를 고르세요"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

	for type_id in _data.shop_type_ids():
		var def: Dictionary = _data.shop_types[type_id]
		var button := Button.new()
		button.text = "%s — %s\n시작 자금 %d원 · 목표 %d원" % [def["name"],
				def.get("description", ""), def["start_money"], def["goal_money"]]
		button.custom_minimum_size = Vector2(520, 64)
		button.pressed.connect(_start_game.bind(type_id))
		box.add_child(button)


func _start_game(type_id: String) -> void:
	_sim = ShopSim.new(_data, type_id)
	_sim.message_logged.connect(_on_message)
	_sim.day_closed.connect(_on_day_closed)
	_build_shop_screen()
	_on_message("[%s] 1일차 아침입니다. 물건을 사고 가격을 정한 뒤 영업을 시작하세요." % _sim.def["name"])
	_refresh()


# --- Shop screen --------------------------------------------------------------

func _build_shop_screen() -> void:
	_clear()
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 20)
	root.add_child(_status_label)
	_events_label = Label.new()
	_events_label.modulate = Color(1.0, 0.85, 0.4)
	root.add_child(_events_label)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	# Left: market / stock table.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.4
	split.add_child(left)
	var qty_row := HBoxContainer.new()
	left.add_child(qty_row)
	var qty_label := Label.new()
	qty_label.text = "매입 수량:"
	qty_row.add_child(qty_label)
	_buy_qty_spin = SpinBox.new()
	_buy_qty_spin.min_value = 1
	_buy_qty_spin.max_value = 999
	_buy_qty_spin.value = 10
	qty_row.add_child(_buy_qty_spin)
	var reset_button := Button.new()
	reset_button.text = "판매가 시세에 맞추기"
	reset_button.pressed.connect(func():
		_sim.reset_prices()
		_refresh())
	qty_row.add_child(reset_button)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)
	_item_grid = GridContainer.new()
	_item_grid.columns = 6
	_item_grid.add_theme_constant_override("h_separation", 14)
	_item_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_item_grid)

	# Right: customer / haggle panel and log.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	_haggle_box = VBoxContainer.new()
	right.add_child(_haggle_box)
	_haggle_label = Label.new()
	_haggle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_haggle_box.add_child(_haggle_label)
	var haggle_row := HBoxContainer.new()
	_haggle_box.add_child(haggle_row)
	var accept_button := Button.new()
	accept_button.text = "수락"
	accept_button.pressed.connect(func():
		_sim.accept_offer()
		_after_haggle())
	haggle_row.add_child(accept_button)
	_counter_spin = SpinBox.new()
	_counter_spin.min_value = 1
	_counter_spin.max_value = 1000000
	haggle_row.add_child(_counter_spin)
	var counter_button := Button.new()
	counter_button.text = "역제안"
	counter_button.pressed.connect(func():
		_sim.counter_offer(int(_counter_spin.value))
		_after_haggle())
	haggle_row.add_child(counter_button)
	var reject_button := Button.new()
	reject_button.text = "거절"
	reject_button.pressed.connect(func():
		_sim.reject_offer()
		_after_haggle())
	haggle_row.add_child(reject_button)

	_log = RichTextLabel.new()
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_log)

	# Bottom: upgrades, travel, day controls.
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	root.add_child(bottom)
	_upgrade_option = OptionButton.new()
	bottom.add_child(_upgrade_option)
	var upgrade_button := Button.new()
	upgrade_button.text = "업그레이드 구매"
	upgrade_button.pressed.connect(_on_buy_upgrade)
	bottom.add_child(upgrade_button)

	_travel_row = HBoxContainer.new()
	bottom.add_child(_travel_row)
	_travel_option = OptionButton.new()
	_travel_row.add_child(_travel_option)
	var travel_button := Button.new()
	travel_button.text = "이동"
	travel_button.pressed.connect(_on_travel)
	_travel_row.add_child(travel_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	_fast_check = CheckBox.new()
	_fast_check.text = "빠르게"
	bottom.add_child(_fast_check)
	_open_button = Button.new()
	_open_button.text = "영업 시작"
	_open_button.pressed.connect(_on_open)
	bottom.add_child(_open_button)
	_close_button = Button.new()
	_close_button.text = "오늘 마감"
	_close_button.pressed.connect(_on_close)
	bottom.add_child(_close_button)
	var title_button := Button.new()
	title_button.text = "처음으로"
	title_button.pressed.connect(_show_title)
	bottom.add_child(title_button)


func _refresh() -> void:
	var prep := _sim.phase == ShopSim.Phase.PREP
	var city_text := ""
	if _sim.can_travel():
		city_text = " · 위치 %s" % _sim.market.city_name(_sim.city)
	_status_label.text = "%s · %d일차 · 돈 %d원 / 목표 %d원 · 평판 %d · 창고 %d/%d · 하루 비용 %d원%s" % [
			_sim.def["name"], _sim.day, roundi(_sim.money), _sim.def["goal_money"],
			roundi(_sim.reputation), _sim.inventory.total_qty(), _sim.storage_capacity(),
			roundi(_sim.daily_cost()), city_text]
	var event_texts := PackedStringArray()
	for ev in _sim.market.active_events:
		event_texts.append("%s (%d일 남음)" % [ev["text"], ev["days_left"]])
	_events_label.text = "진행 중 이벤트: " + (", ".join(event_texts) if not event_texts.is_empty() else "없음")

	_rebuild_item_grid(prep)

	_upgrade_option.clear()
	for upgrade_id in _sim.available_upgrades():
		var up: Dictionary = _data.upgrades[upgrade_id]
		_upgrade_option.add_item("%s (%d원)" % [up["name"], up["cost"]])
		_upgrade_option.set_item_metadata(_upgrade_option.item_count - 1, upgrade_id)
	_upgrade_option.disabled = not prep or _upgrade_option.item_count == 0

	_travel_row.visible = _sim.can_travel()
	if _sim.can_travel():
		_travel_option.clear()
		for city_id in _sim.market.city_ids():
			if city_id == _sim.city:
				continue
			_travel_option.add_item("%s (%d원)" % [_sim.market.city_name(city_id), _sim.travel_cost()])
			_travel_option.set_item_metadata(_travel_option.item_count - 1, city_id)
		_travel_option.disabled = not prep

	_open_button.disabled = not prep
	_close_button.disabled = _sim.phase != ShopSim.Phase.OPEN
	_haggle_box.visible = not _sim.pending_haggle.is_empty()
	if _haggle_box.visible:
		var h := _sim.pending_haggle
		_haggle_label.text = "흥정 중: %s — %s %d개, 개당 %d원 제안 (내 가격 %d원)" % [
				h["customer"]["name"], _sim.item_name(h["item"]), h["qty"], h["offer"], h["price"]]
		_counter_spin.value = roundi((int(h["offer"]) + int(h["price"])) / 2.0)


func _rebuild_item_grid(prep: bool) -> void:
	for child in _item_grid.get_children():
		_item_grid.remove_child(child)
		child.queue_free()
	for header in ["품목", "매입가", "재고", "기한", "판매가", ""]:
		var label := Label.new()
		label.text = header
		label.modulate = Color(0.7, 0.8, 1.0)
		_item_grid.add_child(label)

	for item_id in _sim.item_ids():
		var name_label := Label.new()
		name_label.text = _sim.item_name(item_id)
		_item_grid.add_child(name_label)

		var buy_label := Label.new()
		var stock_label := Label.new()
		var days_label := Label.new()
		if _sim.is_recipe(item_id):
			var parts := PackedStringArray()
			for ingredient in _sim.def["items"][item_id]["recipe"]:
				parts.append("%s×%d" % [_sim.item_name(ingredient), _sim.def["items"][item_id]["recipe"][ingredient]])
			buy_label.text = "제조: " + ", ".join(parts)
			stock_label.text = "%d 가능" % _sim.available_qty(item_id)
		else:
			var price := _sim.get_buy_price(item_id)
			var trend := _sim.market.multiplier(_sim.city, item_id)
			buy_label.text = "%d원 %s" % [price, "▲" if trend > 1.05 else ("▼" if trend < 0.95 else "")]
			stock_label.text = str(_sim.inventory.qty(item_id))
			var days := _sim.inventory.min_days_left(item_id)
			days_label.text = "-" if days < 0.0 else "%.1f일" % days
		_item_grid.add_child(buy_label)
		_item_grid.add_child(stock_label)
		_item_grid.add_child(days_label)

		if _sim.is_sellable(item_id):
			var price_spin := SpinBox.new()
			price_spin.min_value = 1
			price_spin.max_value = 1000000
			price_spin.value = _sim.get_sell_price(item_id)
			price_spin.suffix = "원"
			price_spin.value_changed.connect(func(v: float): _sim.set_sell_price(item_id, int(v)))
			_item_grid.add_child(price_spin)
		else:
			var no_sale := Label.new()
			no_sale.text = "(재료)"
			_item_grid.add_child(no_sale)

		if _sim.is_recipe(item_id):
			_item_grid.add_child(Control.new())
		else:
			var buy_button := Button.new()
			buy_button.text = "매입"
			buy_button.disabled = not prep
			buy_button.pressed.connect(func():
				_sim.buy_stock(item_id, int(_buy_qty_spin.value))
				_refresh())
			_item_grid.add_child(buy_button)


# --- Actions ------------------------------------------------------------------

func _on_open() -> void:
	_sim.open_shop()
	_timer.wait_time = CUSTOMER_INTERVAL_FAST if _fast_check.button_pressed else CUSTOMER_INTERVAL
	_timer.start()
	_refresh()


func _on_customer_tick() -> void:
	if not _sim.pending_haggle.is_empty():
		return
	if _sim.has_next_customer():
		_sim.next_customer()
		_refresh()
	else:
		_on_close()


func _after_haggle() -> void:
	_refresh()


func _on_close() -> void:
	_timer.stop()
	if _sim.phase == ShopSim.Phase.OPEN:
		_sim.close_day()


func _on_buy_upgrade() -> void:
	if _upgrade_option.selected < 0:
		return
	_sim.buy_upgrade(String(_upgrade_option.get_item_metadata(_upgrade_option.selected)))
	_refresh()


func _on_travel() -> void:
	if _travel_option.selected < 0:
		return
	_sim.travel(String(_travel_option.get_item_metadata(_travel_option.selected)))
	_refresh()


func _on_message(text: String) -> void:
	if _log != null:
		_log.append_text(text + "\n")


func _on_day_closed(report: Dictionary) -> void:
	_refresh()
	if report["won"] or report["bankrupt"]:
		var dialog := AcceptDialog.new()
		dialog.title = "게임 종료"
		dialog.dialog_text = ("목표 달성! %d일 만에 %d원을 모았어요." if report["won"]
				else "파산했어요... %d일차, 남은 돈 %d원") % [report["day"], roundi(report["money"])]
		dialog.confirmed.connect(_show_title)
		add_child(dialog)
		dialog.popup_centered()
	else:
		_on_message("— %d일차 아침 —" % _sim.day)


func _clear() -> void:
	for child in get_children():
		if child != _timer:
			child.queue_free()
	_log = null
