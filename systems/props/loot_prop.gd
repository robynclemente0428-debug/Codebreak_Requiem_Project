class_name LootProp
extends StaticBody3D
## A barrel / supply cache that players can hit with any skill. When its life runs out it
## pays out credits and maybe items, then either OPENS (swaps to open_model_scene, stays as an
## obstacle) or BREAKS (shrinks away and stops blocking).
##
## Skills find it through the "breakables" group (see SkillTargets.hittable), so it takes hits
## like an enemy but never counts as one: no kill quests, no "enemies nearby" conditions, no
## life or mana on hit, and enemies ignore it.
##
## Drops use the dungeon's loot rules (DungeonPopulator.drop_item_at), so item level follows the
## dungeon level. The populator places props and remembers opened ones per dungeon instance.

signal opened(prop: LootProp)

@export_group("Looks")
## Model shown while closed. Instanced as a child called "Model".
@export var closed_model_scene: PackedScene
## Model swapped in when it pays out. Empty = the prop breaks and disappears instead.
@export var open_model_scene: PackedScene
@export var collision_radius: float = 0.35
@export var collision_height: float = 1.1

@export_group("Toughness")
@export var max_health: float = 12.0
@export var armour: float = 0.0

@export_group("Loot")
@export var credits_min: int = 3
@export var credits_max: int = 12
## Chance for each roll to drop an item.
@export_range(0.0, 1.0, 0.01) var item_chance: float = 0.35
@export var item_rolls: int = 1
## Rarity of dropped items, as weights.
@export var rarity_weights: Dictionary = {"normal": 60, "magic": 30, "rare": 10}

var index := -1                         # set by the populator: its number in this dungeon instance
var is_open := false
var health: HealthComponent              # read by skills (cast.hit) and damage numbers
var stats: StatComponent
var _model: Node3D
var _shape: CollisionShape3D
var _shake: Tween


func _ready() -> void:
	collision_layer = 1                  # world: blocks movement, stops projectiles
	collision_mask = 0
	_shape = CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = collision_radius
	cyl.height = collision_height
	_shape.shape = cyl
	_shape.position.y = collision_height * 0.5
	add_child(_shape)
	_set_model(closed_model_scene)

	stats = StatComponent.new()
	stats.name = "StatComponent"
	stats.base_stats = {StatTypes.Stat.MAX_HEALTH: max_health, StatTypes.Stat.ARMOUR: armour}
	add_child(stats)
	health = HealthComponent.new()
	health.name = "HealthComponent"
	health.stats = stats
	add_child(health)
	health.initialize()
	health.damage_taken.connect(_on_hit)
	health.died.connect(_on_broken)
	add_to_group("breakables")
	var numbers := get_tree().get_first_node_in_group("damage_numbers") as DamageNumbers
	if numbers:
		numbers.track(health)


## True while it still stands in the way: closed, or opened but kept as an open model. Only
## props that broke away let the navmesh through again (see dungeon.gd).
func still_blocks() -> bool:
	return not is_open or open_model_scene != null


## Shows it already looted (a revisit of the same dungeon instance). Pays nothing.
func set_already_open() -> void:
	is_open = true
	remove_from_group("breakables")
	if open_model_scene:
		_set_model(open_model_scene)
	else:
		queue_free()


func _set_model(scene: PackedScene) -> void:
	if _model:
		remove_child(_model)             # out now, so the new one can take the name "Model"
		_model.queue_free()
		_model = null
	if scene == null:
		return
	_model = scene.instantiate() as Node3D
	_model.name = "Model"
	add_child(_model)


func _on_hit(_amount: float) -> void:
	if _model == null or is_open:
		return
	if _shake:
		_shake.kill()
	_model.position = Vector3.ZERO
	_shake = create_tween()
	for i in 3:
		var off := Vector3(randf_range(-0.06, 0.06), 0.0, randf_range(-0.06, 0.06))
		_shake.tween_property(_model, "position", off, 0.035)
	_shake.tween_property(_model, "position", Vector3.ZERO, 0.05)


func _on_broken() -> void:
	if is_open:
		return
	is_open = true
	remove_from_group("breakables")      # skills stop aiming at it
	_pay_out()
	opened.emit(self)
	if open_model_scene:
		_set_model(open_model_scene)     # lid off, stays as scenery
		return
	_shape.set_deferred("disabled", true)
	if _model:                           # break: squash and vanish
		var t := create_tween()
		t.tween_property(_model, "scale", Vector3(1.3, 0.15, 1.3), 0.18).set_ease(Tween.EASE_IN)
		t.tween_callback(queue_free)
	else:
		queue_free()


func _pay_out() -> void:
	var player := get_tree().get_first_node_in_group("players")
	var credits := randi_range(credits_min, credits_max)
	if credits > 0 and player != null and player.get("currency") != null:
		player.currency.add(credits)
		get_tree().call_group("damage_numbers", "pop_credits", global_position + Vector3.UP * 1.2, credits)
	var populator := _populator()
	if populator == null:
		return
	for i in item_rolls:
		if randf() < item_chance:
			var ring := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU) * 0.8
			populator.drop_item_at(global_position + ring, _roll_rarity())


func _roll_rarity() -> String:
	var total := 0
	for w in rarity_weights.values():
		total += int(w)
	var roll := randi_range(1, maxi(total, 1))
	for r in rarity_weights:
		roll -= int(rarity_weights[r])
		if roll <= 0:
			return r
	return "normal"


## The DungeonPopulator of the dungeon this prop stands in.
func _populator() -> DungeonPopulator:
	var n := get_parent()
	while n != null:
		for c in n.get_children():
			if c is DungeonPopulator:
				return c
		n = n.get_parent()
	return null
