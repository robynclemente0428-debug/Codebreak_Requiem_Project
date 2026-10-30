class_name Player
extends CharacterBody3D

@onready var collision: CollisionShape3D = $CollisionShape3D

## Collision size when the model scale is 1.0
@export var base_collision_height := 1.7
@export var base_collision_radius := 0.5

@onready var stats: StatComponent = $StatComponent
@onready var health: HealthComponent = $HealthComponent
@onready var mana: ManaComponent = $ManaComponent   # add as a child node of Player
@onready var skills: SkillComponent = $SkillComponent
@onready var inventory: InventoryComponent = $InventoryComponent
@onready var equipment: EquipmentComponent = $EquipmentComponent
@onready var currency: CurrencyComponent = $CurrencyComponent
@onready var quests: QuestManager = $QuestManager     # with the other @onready vars

## Input action for each equipped skill slot: slot 0 = attack, slot 1 = slam
var _held: Dictionary = {}            # action -> true only if the press started in the game world

var _attack_cooldown := 0.0
var _dead := false
var _attack_held := false

var input_locked := false               # set by UI windows that need the player to stand still
var _interactable: Interactable
var save_slot := -1          # put this next to your other vars at the top of the file

@export var aim_height: float = 1.0
@export_flags_3d_physics var aim_mask: int = 1

## Rotation ease speed
@export var ease_speed: float = 5.0
## Where the cursor last pointed on the ground (world space), for aiming the gun at it.
var _cursor_point := Vector3.INF

## Camera rig
@onready var camera_rig = $CameraRig
var walking: bool = false

signal walking_changed(is_walking: bool)
## This character's class (null when the scene is run on its own). SkillComponent reads its trait.
var class_data: ClassData

func _ready() -> void:
	var c: ClassData = null
	var data: Dictionary = {}
	if not SaveManager.party.is_empty():
		save_slot = SaveManager.party[0]
		data = SaveManager.get_data(save_slot)
		c = load("res://data/classes/%s.tres" % data["class_id"]) as ClassData
		class_data = c
	var base := {
		StatTypes.Stat.MAX_HEALTH: 100.0,
		StatTypes.Stat.ARMOUR: 0.0,
		StatTypes.Stat.MOVE_SPEED: 5.0,
		StatTypes.Stat.SKILL_DAMAGE_MULT: 1.0,
		StatTypes.Stat.MANA: 100.0,
		StatTypes.Stat.MANA_REGEN: 1.0,
		StatTypes.Stat.ATTACK_RANGE: 1.0,
		StatTypes.Stat.CRIT_MULTIPLIER: 1.50,
		StatTypes.Stat.REGENERATION: 1.0,
	}
	if c:
		base[StatTypes.Stat.STRENGTH] = float(c.strength)
		base[StatTypes.Stat.DEXTERITY] = float(c.dexterity)  # use your ClassData field names
		base[StatTypes.Stat.INTELLIGENCE] = float(c.intelligence)
	stats.base_stats = base          # assign the whole dict: the setter doesn't fire on mutation
	add_child(AimLine.new())         # ground line for ranged skills (gameplay setting "aim_line")
	if c != null:
		apply_movement_trait(c.get_trait())        # Rogue: phases through enemies

	AttributeEffects.bind(stats)        # re-applies whenever attributes change (gear, buffs)
	
	health.stats = stats
	health.initialize()
	health.died.connect(_on_died)
	health.health_changed.connect(_on_health_changed)
	stats.stats_changed.connect(health._on_stats_changed)
	_track_damage_numbers.call_deferred()   # the HUD may not be ready yet
	mana.stats = stats
	mana.initialize()
	stats.stats_changed.connect(mana._on_stats_changed)
	
	add_to_group("players")
	if not SaveManager.party.is_empty():
		$model.set_model(c.model_scene, c.model_scale, c.model_offset)
		_apply_model_size(c.model_scale)
	var hp_hud := get_tree().get_first_node_in_group("hp_hud") as HpHud
	if hp_hud:
		hp_hud.bind($HealthComponent)
	
	var stat_panel := get_tree().get_first_node_in_group("character_panel") as CharacterPanel
	if stat_panel:
		stat_panel.bind($StatComponent)
		
	var mana_hud := get_tree().get_first_node_in_group("mana_hud") as ManaHud
	if mana_hud:
		mana_hud.bind($ManaComponent)

	
	equipment.stat_component = stats
	equipment.equipment_changed.connect(_refresh_held_items)
	var inv_panel := get_tree().get_first_node_in_group("inventory_panel") as InventoryPanel
	if inv_panel:
		inv_panel.bind(inventory, equipment)
		inv_panel.bind_currency(currency)

	var skill_panel := get_tree().get_first_node_in_group("skill_panel") as SkillPanel
	if skill_panel:
		skill_panel.bind(skills, inventory, equipment)
	
	var skill_bar := get_tree().get_first_node_in_group("skill_bar") as SkillBar
	if skill_bar:
		skill_bar.bind(skills, mana, equipment)
	
	var shop_panel := get_tree().get_first_node_in_group("shop_panel") as ShopPanel
	if shop_panel:
		shop_panel.bind(inventory, equipment, currency)
	
	if not data.is_empty():
		GameEvents.muted = true 
		_apply_saved_equipment(data)
		_apply_saved_skills(data)
		_apply_saved_inventory(data)
		if data.has('currency'):
			currency.from_dict(data['currency'])
		if data.has('quests'):
			quests.from_dict(data['quests'])     # once you add the QuestManager
		
		GameEvents.muted = false
		# Saved gear raised max health / mana after they were filled, so start full
		health.initialize()
		mana.initialize()
	
	var quest_log := get_tree().get_first_node_in_group("quest_log") as QuestLogPanel
	if quest_log:
		quest_log.bind(quests)
	
	var quest_tracker := get_tree().get_first_node_in_group("quest_tracker") as QuestTracker
	if quest_tracker:
		quest_tracker.bind(quests)
	
		

## Shows the damage you take as floating numbers (Settings > Gameplay > "damage numbers on you").
func _track_damage_numbers() -> void:
	var numbers := get_tree().get_first_node_in_group("damage_numbers") as DamageNumbers
	if numbers != null:
		numbers.track(health, true)

func _apply_saved_equipment(data: Dictionary) -> void:
	var saved: Dictionary = data.get('equipment', {})
	for slot_name in saved:
		var entry = saved[slot_name]
		var item: ItemInstance = null
		if entry is Dictionary:
			item = ItemInstance.from_dict(entry)
		else:                                  # starting loadout: just a base item id
			var def := ItemDatabase.get_item(str(entry))
			if def:
				item = ItemInstance.new()
				item.definition = def
		if item == null:
			push_warning("Could not load equipment: %s" % str(entry))
			continue
		equipment.equip(item, EquipmentSlots.Slot.get(str(slot_name).to_upper(), -1))

func _apply_saved_inventory(data: Dictionary) -> void:
	for entry in data.get('inventory', []):
		var item: ItemInstance = null
		if entry is Dictionary:
			item = ItemInstance.from_dict(entry)
		else:                                  # starting loadout: just a base item id
			var def := ItemDatabase.get_item(str(entry))
			if def == null:
				push_warning("Could not load inventory item: %s" % str(entry))
				continue
			if def.is_gem():
				item = ItemInstance.make_gem(def)
			else:
				item = ItemInstance.new()
				item.definition = def
		if item:
			inventory.add_item(item)

func _apply_saved_skills(data: Dictionary) -> void:
	var saved: Array = data.get('skills', [])
	for i in mini(saved.size(), skills.sockets.size()):
		var entry: Dictionary = saved[i]
		var gem_def := ItemDatabase.get_item(str(entry.get('gem', '')))
		if gem_def == null:
			continue
		if not skills.socket_skill(i, ItemInstance.make_gem(gem_def)):
			continue
		for support_id in entry.get('supports', []):
			var support_def := ItemDatabase.get_item(str(support_id))
			if support_def:
				skills.socket_support(i, ItemInstance.make_gem(support_def))
		var action := StringName(entry.get('action', ''))
		if action != &"":
			skills.bind_action(action, i)
		if entry.get('program') is Dictionary:
			var result := skills.set_program(i, SkillProgram.from_dict(entry['program']))
			if result != null and not result.valid:
				push_warning("Saved program for socket %d no longer fits: %s" % [i, "; ".join(result.errors)])

func write_save() -> void:
	if save_slot < 0:
		return
	var data := SaveManager.get_data(save_slot)   # the live dictionary, so edits get saved
	data['skills'] = _collect_skills()
	data['equipment'] = _collect_equipment()
	data['inventory'] = _collect_inventory()
	data['currency'] = currency.to_dict()
	data['quests'] = quests.to_dict()   


func _collect_equipment() -> Dictionary:
	var out := {}
	for slot in equipment.equipped:
		var slot_name: String = EquipmentSlots.Slot.find_key(slot).to_lower()
		out[slot_name] = equipment.equipped[slot].to_dict()
	return out

func _collect_skills() -> Array:
	var out: Array = []
	for i in skills.sockets.size():
		var s := skills.sockets[i]
		if s.gem == null:
			out.append({})
			continue
		var support_ids: Array = []
		for item in s.supports:
			support_ids.append(item.definition.id)
		var entry := {
			'gem': s.gem.definition.id,
			'supports': support_ids,
			'action': String(skills.action_of(i)),
		}
		if s.program != null and s.program.has_rules():
			entry['program'] = s.program.to_dict()
		out.append(entry)
	return out

func _collect_inventory() -> Array:
	var out: Array = []
	for item in inventory.items:
		out.append(item.to_dict())
	return out

func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not is_on_floor():
		velocity += get_gravity() * delta
	_handle_movement()
	_handle_rotation(delta)
	_handle_attack(delta)

func _refresh_held_items() -> void:
	var weapon := equipment.get_equipped(EquipmentSlots.Slot.WEAPON)
	var off_hand := equipment.get_equipped(EquipmentSlots.Slot.OFF_HAND)
	var set_name := ""
	if weapon != null and weapon.definition.weapon_type != null:
		set_name = weapon.definition.weapon_type.animation_set
	$model.set_animation_set(set_name)
	$model.set_held_items(
		weapon.definition.mesh if weapon != null else null,
		off_hand.definition.mesh if off_hand != null else null)

func _is_two_handed(item: ItemInstance) -> bool:
	return item != null and item.definition.weapon_type != null \
		and item.definition.weapon_type.two_handed

func _apply_model_size(model_scale: float) -> void:
	# duplicate so the shared resource isn't edited for every player
	var shape := (collision.shape as CylinderShape3D).duplicate() as CylinderShape3D
	shape.height = base_collision_height * model_scale
	shape.radius = base_collision_radius * model_scale
	collision.shape = shape
	collision.position.y = shape.height * 0.5    # keep the feet on the ground

func _handle_attack(delta: float) -> void:
	if input_locked:
		return
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	if _attack_cooldown > 0.0 or Input.is_action_pressed("pickup"):
		return
	var actions := SkillComponent.ACTIONS
	for i in range(actions.size() - 1, -1, -1):     # the last key wins if several are held
		if not _wants(actions[i]):
			continue
		var skill := skills.get_skill(actions[i])
		if skill == null or not skill.weapon_allows(equipment) or not skill.can_afford(mana):
			continue
		_attack_cooldown = skill.get_cooldown(stats)
		skill.cast(self, stats, mana)
		GameEvents.report("cast", String(actions[i]))
		return

func _unhandled_input(event: InputEvent) -> void:
	if input_locked:
		return
	if event.is_action_pressed("interact") and _interactable != null:
		_interactable.interact(self)
		get_viewport().set_input_as_handled()
	for action in SkillComponent.ACTIONS:
		if event.is_action_pressed(action):
			_held[action] = true
		elif event.is_action_released(action):
			_held[action] = false


func _wants(action: StringName) -> bool:   # one place to change when co-op needs per-player input
	if not Input.is_action_pressed(action):
		_held[action] = false              # button is up, even if the release was eaten by UI
		return false
	return _held.get(action, false)

func _on_died() -> void:
	_dead = true
	velocity = Vector3.ZERO
	remove_from_group("players")
	$model.play_death()
	var dm := get_tree().get_first_node_in_group("death_menu") as DeathMenu
	if dm:
		dm.show_death(self)

func revive() -> void:
	_dead = false
	_attack_cooldown = 0.0
	_held.clear()
	health.revive()
	mana.initialize()          # refills mana, assuming it works like health.initialize()
	add_to_group("players")
	$model.revive()

func _on_health_changed(current: float, max_hp: float) -> void:
	#print("Player: %.1f / %.1f HP" % [current, max_hp])
	pass

## Handle player movement
func _handle_movement() -> void:
	if input_locked:
		velocity.x = 0.0
		velocity.z = 0.0
		if walking:
			walking = false
			walking_changed.emit(false)
		move_and_slide()
		return
	
	var input_dir = InputManager.get_input_direction()
	var velocity_vector = input_dir * stats.get_stat(StatTypes.Stat.MOVE_SPEED)
	velocity.x = velocity_vector.x
	velocity.z = velocity_vector.z
	
	var is_walking = input_dir.length() > 0.0
	if is_walking != walking:
		walking = is_walking
		walking_changed.emit(walking)
	# Each press of a movement key counts for "walk" objectives (the tutorial's WASD step)
	for action in [&"forward", &"backward", &"left", &"right"]:
		if Input.is_action_just_pressed(action):
			GameEvents.report("walk", String(action))
	move_and_slide()

## Called by skill behaviors. Returns seconds until the hit should land.
func play_skill_animation(key: String, fit_duration: float) -> float:
	if key == "":
		return 0.0
	var hit_in: float = $model.play_fitted_action(key, fit_duration)
	if hit_in > 0.0:
		SoundManager.play_skill(key, self, hit_in)       # swing / cast sound for this animation
	return hit_in



## Handle player rotation
func _handle_rotation(delta: float) -> void:
	if input_locked or not camera_rig:
		return
	var camera: Camera3D = camera_rig.camera
	var mouse_pos := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)

	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 200.0, aim_mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	var aim_point: Vector3
	if hit:
		aim_point = hit.position
	else:
		var p = Plane(Vector3.UP, global_position.y + aim_height).intersects_ray(from, dir)
		if p == null:
			return
		aim_point = p

	_cursor_point = aim_point
	var to_aim := aim_point - global_position
	to_aim.y = 0.0
	if to_aim.length_squared() < 0.04:   # cursor is on the player; avoid snapping to +Z
		return

	var target_rot_y := atan2(to_aim.x, to_aim.z)
	global_rotation.y = lerp_angle(global_rotation.y, target_rot_y, 1.0 - pow(0.001, delta * ease_speed))
	

## The point the gun and the bullets converge on: straight ahead of the player, as far away as
## the cursor (2 to 30 m). The gun sits at the shoulder, so aiming it (and the shots) at this
## point puts the barrel and the bullet line through the cursor instead of beside it.
func get_aim_point() -> Vector3:
	var fwd := global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var dist := 8.0
	if _cursor_point != Vector3.INF:
		var flat := _cursor_point - global_position
		flat.y = 0.0
		dist = flat.length()
	return global_position + fwd * clampf(dist, 2.0, 30.0)


## Physics layer enemies are on (layer 3).
const ENEMY_LAYER_BIT := 4

## Class trait movement rules. Rogue phases through enemies, both ways:
##   the player doesn't collide with enemies (they can't block it)
##   enemies don't collide with the player (otherwise each enemy's move_and_slide pushes it back
##   out of the player's capsule, the way the player walks, and it gets dragged along)
## Collision exceptions only change body-vs-body movement: enemy attacks, projectiles and the
## player's own skills still hit as before.
var _phasing := false

func apply_movement_trait(t: ClassTrait) -> void:
	var on := t != null and t.phase_through_enemies
	if on == _phasing:
		return
	_phasing = on
	if on:
		collision_mask &= ~ENEMY_LAYER_BIT
		for e in get_tree().get_nodes_in_group(&"enemies"):
			_phase_with(e)
		get_tree().node_added.connect(_on_node_added)          # enemies spawned later
	else:
		collision_mask |= ENEMY_LAYER_BIT
		if get_tree().node_added.is_connected(_on_node_added):
			get_tree().node_added.disconnect(_on_node_added)
		for e in get_tree().get_nodes_in_group(&"enemies"):
			if e is PhysicsBody3D:
				(e as PhysicsBody3D).remove_collision_exception_with(self)


func _on_node_added(n: Node) -> void:
	if n is PhysicsBody3D and n.is_in_group(&"enemies"):
		_phase_with.call_deferred(n)


func _phase_with(e: Node) -> void:
	if e is PhysicsBody3D and is_instance_valid(e) and e != self:
		(e as PhysicsBody3D).add_collision_exception_with(self)


## Where shots leave the held gun (ShootBehavior). null = no weapon held.
func get_muzzle_point() -> Variant:
	return $model.get_muzzle_point()


## Colours (and shader) of what the player holds, used by skill effects.
func get_effect_style() -> Dictionary:
	return SkillStyle.from_held($model.get_held_items())

func set_interactable(i: Interactable) -> void:
	_interactable = i

func clear_interactable(i: Interactable) -> void:
	if _interactable == i:
		_interactable = null
