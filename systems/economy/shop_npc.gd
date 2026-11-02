class_name ShopNPC
extends DialogueNPC

signal stock_changed

@export var shop: ShopDefinition
@export var stock_level: int = 1 
	    # item level used when rolling stock
@export_group("Appearance")
@export var model_scene: PackedScene
@export var model_scale: Vector3 = Vector3.ONE

@onready var model_anchor: Node3D = $ModelAnchor

var stock: Array[ItemInstance] = []
var _infinite: Array[ItemInstance] = []
var _rerolls := 0                     # rerolls since the last natural restock
var _stock_rank := 0                  # the player rank the stock was filtered for (_locked)

func _ready() -> void:
	super._ready()
	_apply_model()
	restock()

func _apply_model() -> void:
	if model_scene == null:
		push_warning("ShopNPC: No model scene assigned.")
		return
	
	for child in model_anchor.get_children():
		model_anchor.remove_child(child)
		child.queue_free()
	var model := model_scene.instantiate() as Node3D
	if model == null:
		push_warning("ShopNPC: Model root must inherit Node3D.")
		return
	
	model.scale = model_scale
	model_anchor.add_child(model)

func interact(player: Node3D) -> void:
	if dialogue != null:
		super.interact(player)           # reports "talk" and opens the conversation
		return
	GameEvents.report("talk", npc_id)    # no dialogue assigned: go straight to the shop
	var panel := get_tree().get_first_node_in_group("shop_panel") as ShopPanel
	if panel == null:
		push_warning("ShopNPC: no ShopPanel in the scene (group shop_panel)")
		return
	panel.open_shop(self, player)

func restock() -> void:
	stock.clear()
	_infinite.clear()
	_rerolls = 0
	if shop == null:
		return
	_stock_rank = Ranks.of_player(get_tree())

	for def in shop.fixed_stock:
		if _locked(def, _stock_rank):
			continue
		var item := _make_item(def, false)
		if item == null:
			continue
		stock.append(item)
		if shop.infinite_fixed:
			_infinite.append(item)

	var pool := _build_random_pool()
	for def in _roll_defs(pool, shop.random_slots):
		var item := _make_item(def, true)
		if item != null:
			stock.append(item)

	print("[Shop %s] level %d: %d eligible items, %d on sale" % [npc_name, stock_level, pool.size(), stock.size()])
	stock_changed.emit()

# ---------- REROLL ----------
## True when this shop sells random stock and allows paying to roll it again.
func can_reroll() -> bool:
	return shop != null and shop.allow_reroll and shop.random_slots > 0 \
			and (shop.use_catalog or not shop.random_pool.is_empty())


## Credits the next reroll costs (grows with each reroll since the last restock).
func reroll_cost() -> int:
	if shop == null:
		return 0
	var base := float(shop.reroll_base_cost + shop.reroll_cost_per_level * stock_level)
	return maxi(roundi(base * pow(maxf(shop.reroll_cost_growth, 1.0), _rerolls)), 0)


## Pays and replaces the random stock. Fixed stock stays as it is.
## Returns "" on success, otherwise the message to show the player.
func try_reroll(wallet: CurrencyComponent) -> String:
	if not can_reroll():
		return "THIS SHOP CAN'T REROLL"
	var pool := _build_random_pool()
	if pool.is_empty():
		return "NOTHING ELSE TO STOCK"
	if wallet == null or not wallet.spend(reroll_cost()):
		return "NOT ENOUGH CREDITS"
	_rerolls += 1
	stock.assign(stock.filter(func(item: ItemInstance) -> bool: return item.definition in shop.fixed_stock))
	for def in _roll_defs(pool, shop.random_slots):
		var item := _make_item(def, true)
		if item != null:
			stock.append(item)
	GameEvents.report("shop_reroll", npc_id)
	stock_changed.emit()
	return ""


func _build_random_pool() -> Array[ItemDefinition]:
	var found: Array[ItemDefinition] = []
	if shop.use_catalog:
		var folders := PackedStringArray()
		for f in shop.catalog_folders:
			folders.append(f if f.ends_with("/") else f + "/")    # "weapons" must not match "weapons_old"
		found.append_array(ItemCatalog.for_level(stock_level, shop.level_window, shop.include_gems, folders))
	for def in shop.random_pool:
		if def not in found:
			found.append(def)

	var pool: Array[ItemDefinition] = []
	for def in found:
		if def in shop.excluded_items or def in shop.fixed_stock or _locked(def, _stock_rank):
			continue
		pool.append(def)
	return pool

## Picks `count` different definitions, weighted towards higher item levels when level_bias > 0.
func _roll_defs(pool: Array[ItemDefinition], count: int) -> Array[ItemDefinition]:
	var left: Array[ItemDefinition] = pool.duplicate()
	var out: Array[ItemDefinition] = []
	for i in mini(count, left.size()):
		var total := 0.0
		for d in left:
			total += _weight(d)
		var roll := randf() * total
		var pick: ItemDefinition = left[0]
		for d in left:
			roll -= _weight(d)
			if roll <= 0.0:
				pick = d
				break
		left.erase(pick)
		out.append(pick)
	return out


func _weight(def: ItemDefinition) -> float:
	return pow(maxf(float(def.item_level), 1.0), shop.level_bias)

func buy_price(item: ItemInstance) -> int:
	return maxi(ceili(ItemPricing.value_of(item) * shop.buy_markup), 1)

func sell_price(item: ItemInstance) -> int:
	return maxi(floori(ItemPricing.value_of(item) * shop.sell_ratio), 1)

## Returns "" on success, otherwise the message to show the player.
func try_buy(item: ItemInstance, inv: InventoryComponent, wallet: CurrencyComponent) -> String:
	var idx := stock.find(item)
	if idx < 0:
		return "NO LONGER AVAILABLE"
	if inv.is_full():
		return "BACKPACK FULL"
	if not wallet.spend(buy_price(item)):
		return "NOT ENOUGH CREDITS"

	if item in _infinite:
		var fresh := _make_item(item.definition, false)
		var inf_idx := _infinite.find(item)
		if fresh != null:
			stock[idx] = fresh
			_infinite[inf_idx] = fresh
		else:
			stock.remove_at(idx)
			_infinite.remove_at(inf_idx)
	else:
		stock.remove_at(idx)
	inv.add_item(item)
	stock_changed.emit()
	return ""

func try_sell(item: ItemInstance, inv: InventoryComponent, wallet: CurrencyComponent) -> String:
	if not inv.has_item(item):
		return "ONLY BACKPACK ITEMS CAN BE SOLD"
	var qm: QuestManager = inv.get_parent().get("quests")
	var keep := qm.keep_reason(item) if qm != null else ""
	if keep != "":
		return keep
	wallet.add(sell_price(item))
	inv.remove_item(item)
	return ""

# ---------- RANKS ----------
## Support gems above the player's rank (Ranks.LOCKED_BLOCKS: For Loop below ARCHITECT) aren't sold.
static func _locked(def: ItemDefinition, rank: int) -> bool:
	return def != null and def.support_gem != null and not Ranks.allows(rank, "gem:" + def.support_gem.id)


## Opening the shop: gems the player's rank unlocked since the stock was made go on sale.
func engage(player: Node3D) -> void:
	super.engage(player)
	var rank := Ranks.of(player)
	if shop == null or rank <= _stock_rank:
		return
	var before := _stock_rank
	_stock_rank = rank
	for def in shop.fixed_stock:
		if _locked(def, before) and not _locked(def, rank):
			var item := _make_item(def, false)
			if item == null:
				continue
			stock.append(item)
			if shop.infinite_fixed:
				_infinite.append(item)
	for def in _build_random_pool():       # random stock (the gem vendor): one of each, on top
		if _locked(def, before):
			var item := _make_item(def, false)
			if item != null:
				stock.append(item)
	stock_changed.emit()


func _make_item(def: ItemDefinition, roll_rarity: bool) -> ItemInstance:
	if def.is_gem():
		return ItemInstance.make_gem(def)          # may return null, callers skip those
	var rarity := "normal"
	if roll_rarity:
		var r := randf()
		if r < shop.rare_chance:
			rarity = "rare"
		elif r < shop.rare_chance + shop.magic_chance:
			rarity = "magic"
	return ItemGenerator.generate_item(def, stock_level, rarity)
