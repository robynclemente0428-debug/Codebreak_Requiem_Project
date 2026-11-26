class_name Player
extends CharacterBody3D

@onready var collision: CollisionShape3D = $CollisionShape3D

@export var base_collision_height := 1.7
@export var base_collision_radius := 0.5

@onready var stats: StatComponent = $StatComponent
@onready var health: HealthComponent = $HealthComponent
@onready var mana: ManaComponent = $ManaComponent
@onready var skills: SkillComponent = $SkillComponent
@onready var inventory: InventoryComponent = $InventoryComponent
@onready var equipment: EquipmentComponent = $EquipmentComponent
@onready var currency: CurrencyComponent = $CurrencyComponent
@onready var quests: QuestManager = $QuestManager

var _held: Dictionary = {}

var _attack_cooldown := 0.0
var _dead := false
var _attack_held := false

var input_locked := false
var _interactable: Interactable
var save_slot := -1

@export var aim_height: float = 1.0

@export var ease_speed: float = 5.0
var _cursor_point := Vector3.INF

@onready var camera_rig = $CameraRig
var walking: bool = false

signal walking_changed(is_walking: bool)

var is_remote := false
var coop_data: Dictionary = {}
signal skill_cast(action: StringName)

var class_data: ClassData

const LIGHT_NAME := "PlayerLight"
const LIGHT_COLOR := Color(0.55, 0.75, 1.0)
const LIGHT_ENERGY := 16.0
const LIGHT_RANGE := 13.0
const LIGHT_ATTENUATION := 2.5
const LIGHT_HEIGHT := 3.5


func _add_light() -> void:
	var light := OmniLight3D.new()
	light.name = LIGHT_NAME
	light.light_color = LIGHT_COLOR
	light.omni_range = LIGHT_RANGE
	light.omni_attenuation = LIGHT_ATTENUATION
	light.shadow_enabled = GraphicsQuality.player_shadows()
	light.position = Vector3.UP * LIGHT_HEIGHT
	add_child(light)
	set_light_strength(AreaLighting.player_light)


func set_light_shadows(on: bool) -> void:
	var light := get_node_or_null(LIGHT_NAME) as OmniLight3D
	if light != null:
		light.shadow_enabled = on


func set_light_strength(t: float) -> void:
	var light := get_node_or_null(LIGHT_NAME) as OmniLight3D
	if light == null:
		return
	light.light_energy = LIGHT_ENERGY * t
	light.visible = t > 0.0


func _ready() -> void:
	if not is_remote:
		_add_light()
	var c: ClassData = null
	var data: Dictionary = {}
	if not coop_data.is_empty():
		data = coop_data
		c = load("res://data/classes/%s.tres" % data["class_id"]) as ClassData
		class_data = c
	elif not SaveManager.party.is_empty():
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
		base[StatTypes.Stat.DEXTERITY] = float(c.dexterity)
		base[StatTypes.Stat.INTELLIGENCE] = float(c.intelligence)
	stats.base_stats = base
	if not is_remote:
		add_child(AimLine.new())
		add_child(RegistryMarkers.new())
	if c != null:
		apply_movement_trait(c.get_trait())

	AttributeEffects.bind(stats)
	
	health.stats = stats
	health.initialize()
	health.died.connect(_on_died)
	health.health_changed.connect(_on_health_changed)
	stats.stats_changed.connect(health._on_stats_changed)
	if not is_remote:
		_track_damage_numbers.call_deferred()
	mana.stats = stats
	mana.initialize()
	stats.stats_changed.connect(mana._on_stats_changed)
	
	add_to_group("players")
	if c != null:
		$model.set_model(c.model_scene, c.model_scale, c.model_offset)
		_apply_model_size(c.model_scale)
	equipment.stat_component = stats
	equipment.equipment_changed.connect(_refresh_held_items)
	if not is_remote:
		_bind_hud()

	if not data.is_empty():
		GameEvents.muted = true
		if is_remote and data.get('limits') is Dictionary:
			skills.remote_limits = data['limits']
		if data.has('quests'):
			quests.from_dict(data['quests'])
		_apply_saved_equipment(data)
		_apply_saved_skills(data)
		_apply_saved_inventory(data)
		if data.has('currency'):
			currency.from_dict(data['currency'])
		
		GameEvents.muted = false
		health.initialize()
		mana.initialize()

	if not is_remote:
		var quest_log := get_tree().get_first_node_in_group("quest_log") as QuestLogPanel
		if quest_log:
			quest_log.bind(quests)

		var quest_tracker := get_tree().get_first_node_in_group("quest_tracker") as QuestTracker
		if quest_tracker:
			quest_tracker.bind(quests)


func _bind_hud() -> void:
	var hp_hud := get_tree().get_first_node_in_group("hp_hud") as HpHud
	if hp_hud:
		hp_hud.bind($HealthComponent)

	var stat_panel := get_tree().get_first_node_in_group("character_panel") as CharacterPanel
	if stat_panel:
		stat_panel.bind($StatComponent)

	var mana_hud := get_tree().get_first_node_in_group("mana_hud") as ManaHud
	if mana_hud:
		mana_hud.bind($ManaComponent)

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
		else:
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
		else:
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
	skills.script_set = clampi(int(data.get('script_set', 0)), 0, skills.sets_unlocked() - 1)
	if data.get('script_set_names') is Array:
		skills.restore_set_names(data['script_set_names'])
	if data.get('script_library') is Array:
		skills.restore_library(data['script_library'])
	if data.get('script_routines') is Array:
		skills.restore_routines(data['script_routines'])
	if data.get('kernel') is Array:
		skills.kernel.clear()
		for id in data['kernel']:
			if KernelScript.LINES.has(str(id)) and not (str(id) in skills.kernel):
				skills.kernel.append(str(id))
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
		var result: ProgramValidation = null
		if entry.get('sets') is Array:
			result = skills.restore_sets(i, entry['sets'])
		elif entry.get('program') is Dictionary:
			result = skills.restore_sets(i, [entry['program']])
		if result != null and not result.valid:
			push_warning("Saved program for socket %d no longer fits: %s" % [i, "; ".join(result.errors)])

func write_save() -> void:
	if save_slot < 0:
		return
	var data := SaveManager.get_data(save_slot)
	if has_meta(&"exam_save"):
		data.merge(get_meta(&"exam_save"), true)
	else:
		data.merge(loadout_save(), true)
	data['script_library'] = skills.library.duplicate(true)
	data['script_routines'] = skills.routines_to_list()
	data['kernel'] = Array(skills.kernel)
	data['currency'] = currency.to_dict()
	data['quests'] = quests.to_dict()   


func loadout_save() -> Dictionary:
	return {
		'skills': _collect_skills(),
		'script_set': skills.script_set,
		'script_set_names': skills.set_names_list(),
		'equipment': _collect_equipment(),
		'inventory': _collect_inventory(),
	}


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
		if skills.uses_scripts():
			entry['sets'] = skills.sets_to_list(i)
		out.append(entry)
	return out

func _collect_inventory() -> Array:
	var out: Array = []
	for item in inventory.items:
		out.append(item.to_dict())
	return out

func _process(_delta: float) -> void:
	if is_remote:
		return
	if not coop_data.is_empty() or get_tree().get_first_node_in_group("players") == self:
		RenderingServer.global_shader_parameter_set(&"player_world_pos", global_position)


func _physics_process(delta: float) -> void:
	if _dead or is_remote:
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
	var shape := (collision.shape as CylinderShape3D).duplicate() as CylinderShape3D
	shape.height = base_collision_height * model_scale
	shape.radius = base_collision_radius * model_scale
	collision.shape = shape
	collision.position.y = shape.height * 0.5

func _handle_attack(delta: float) -> void:
	if input_locked:
		return
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	if _attack_cooldown > 0.0 or Input.is_action_pressed("pickup"):
		return
	var actions := SkillComponent.ACTIONS
	for i in range(actions.size() - 1, -1, -1):
		if not _wants(actions[i]):
			continue
		var skill := skills.get_skill(actions[i])
		if skill == null or not skill.weapon_allows(equipment) or not skill.can_afford(mana):
			continue
		_attack_cooldown = skill.get_cooldown(stats)
		skill.cast(self, stats, mana)
		GameEvents.report("cast", String(actions[i]))
		skill_cast.emit(actions[i])
		return


func remote_cast(action: StringName, facing: float, aim_point: Vector3) -> void:
	if not is_remote or _dead:
		return
	var skill := skills.get_skill(action)
	if skill == null:
		return
	global_rotation.y = facing
	_cursor_point = aim_point
	skill.cast(self, stats)


func _unhandled_input(event: InputEvent) -> void:
	if input_locked or is_remote:
		return
	if event.is_action_pressed("interact") and _interactable != null:
		_interactable.interact(self)
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("script_set"):
		_next_script_set()
		get_viewport().set_input_as_handled()
	for action in SkillComponent.ACTIONS:
		if event.is_action_pressed(action):
			_held[action] = true
		elif event.is_action_released(action):
			_held[action] = false


func _next_script_set() -> void:
	var bar := get_tree().get_first_node_in_group("skill_bar") as SkillBar
	if not skills.uses_scripts():
		if bar:
			bar.show_set_message("NO SCRIPTS YET: WRITE ONE IN THE SKILLS MENU [K]")
		return
	if skills.sets_unlocked() <= 1:
		if bar:
			bar.show_set_message("ONLY ONE SCRIPT SET")
		return
	var why := skills.switch_script_set((skills.script_set + 1) % skills.sets_unlocked())
	if bar:
		bar.show_set_message(why)


func _wants(action: StringName) -> bool:
	if not Input.is_action_pressed(action):
		_held[action] = false
		return false
	return _held.get(action, false)

func _on_died() -> void:
	_dead = true
	velocity = Vector3.ZERO
	remove_from_group("players")
	$model.play_death()
	var dm := get_tree().get_first_node_in_group("death_menu") as DeathMenu
	if dm and not is_remote:
		dm.show_death(self)

func revive() -> void:
	_dead = false
	_attack_cooldown = 0.0
	_held.clear()
	health.revive()
	mana.initialize()
	add_to_group("players")
	$model.revive()

func _on_health_changed(current: float, max_hp: float) -> void:
	pass

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
	for action in [&"forward", &"backward", &"left", &"right"]:
		if Input.is_action_just_pressed(action):
			GameEvents.report("walk", String(action))
	move_and_slide()

func play_skill_animation(key: String, fit_duration: float) -> float:
	if key == "":
		return 0.0
	var hit_in: float = $model.play_fitted_action(key, fit_duration)
	if hit_in > 0.0:
		SoundManager.play_skill(key, self, hit_in)
	return hit_in


func _handle_rotation(delta: float) -> void:
	if input_locked or not camera_rig:
		return
	var camera: Camera3D = camera_rig.camera
	var mouse_pos := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)

	var p = Plane(Vector3.UP, global_position.y + aim_height).intersects_ray(from, dir)
	if p == null:
		return
	var aim_point: Vector3 = p

	_cursor_point = aim_point
	var to_aim := aim_point - global_position
	to_aim.y = 0.0
	if to_aim.length_squared() < 0.04:
		return

	var target_rot_y := atan2(to_aim.x, to_aim.z)
	global_rotation.y = lerp_angle(global_rotation.y, target_rot_y, 1.0 - pow(0.001, delta * ease_speed))
	

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


const ENEMY_LAYER_BIT := 4

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
		get_tree().node_added.connect(_on_node_added)
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


func get_muzzle_point() -> Variant:
	return $model.get_muzzle_point()


func get_effect_style() -> Dictionary:
	return SkillStyle.from_held($model.get_held_items())

func set_interactable(i: Interactable) -> void:
	_interactable = i

func clear_interactable(i: Interactable) -> void:
	if _interactable == i:
		_interactable = null
