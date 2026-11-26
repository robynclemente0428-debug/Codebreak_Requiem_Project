class_name ExamChamber
extends GameArea

const SCENE := "res://scenes/map/exam/exam_chamber.tscn"
const RADIUS := 11.0
const TERMINAL_AT := Vector3(0.0, 0.0, -2.5)
const SPAWN_AT := Vector3(0.0, 0.0, 2.0)
const HOLO := ExamSpec.DEFAULT_TINT
const TILE_LANE := 0
const TILE_WALL := 1
const TILE_PAVER := 2
const TANK_HEIGHT := 2.2

static var pending_rank := "operator"

var navigation_is_ready := false

var spec: ExamSpec
var _hud: ExamHud
var _player: Node3D
var _nav: NavigationRegion3D
var _enemies_root: Node3D

enum State { BRIEF, RUNNING, RESULT }
var _state := State.BRIEF
var _wave := 0
var _alive: Array[Node3D] = []
var _time := 0.0
var _between_waves := 0.0
var _damage := 0.0
var _max_health := 1.0
var _fires := 0
var _casts := 0
var _rule_fires := {}
var _routine_callers := {}
var _order := {"hit_in": 0, "hit_out": 0, "kill_out": 0}
var _ended := false
var _real_loadout := {}
var _ring_mat: StandardMaterial3D
var _tanks: Array[Dictionary] = []
var _tank_tween: Tween


static func enter(tree: SceneTree, rank: String) -> void:
	pending_rank = rank
	var am := tree.get_first_node_in_group("area_manager") as AreaManager
	if am != null:
		am.go_to(SCENE, &"default")


func _ready() -> void:
	spec = ExamSpec.load_for(pending_rank)
	_build_arena()
	_enemies_root = Node3D.new()
	_enemies_root.name = "Enemies"
	add_child(_enemies_root)
	_hud = ExamHud.new()
	_hud.chamber = self
	get_tree().root.add_child.call_deferred(_hud)
	GameEvents.happened.connect(_on_event)
	_bake.call_deferred()


func _exit_tree() -> void:
	if is_instance_valid(_hud):
		_hud.queue_free()
	_leave_sandbox()
	if not Ranks.lent.is_empty():
		Ranks.lent = PackedStringArray()
		_refresh_skills()


func _refresh_skills() -> void:
	var p := _player if is_instance_valid(_player) else get_tree().get_first_node_in_group("players")
	var skills: SkillComponent = p.get("skills") if p != null else null
	if skills != null:
		skills.refresh_rank()


func get_spawn_position(_spawn_id: StringName = DEFAULT_SPAWN) -> Vector3:
	return to_global(SPAWN_AT)


func on_player_arrived(player: Node3D) -> void:
	_player = player
	_enter_sandbox()
	if spec != null and not spec.lends.is_empty():
		Ranks.lent = PackedStringArray(spec.lends)
		_refresh_skills()
	_hud.show_brief()


func _enter_sandbox() -> void:
	var p := _player as Player
	if p == null or not _real_loadout.is_empty():
		return
	_real_loadout = {"equipment": p.equipment.equipped.duplicate(),
			"inventory": p.inventory.items.duplicate(), "skills": p.skills.snapshot()}
	p.set_meta(&"exam_save", p.loadout_save())
	var worn := {}
	var def: ItemDefinition = p.class_data.starting_weapon if p.class_data != null else null
	if def != null:
		var weapon := ItemInstance.new()
		weapon.definition = def
		worn[p.equipment.slot_for(weapon)] = weapon
	GameEvents.muted = true
	p.equipment.swap_to(worn)
	p.skills.strip_for_exam()
	GameEvents.muted = false
	p.equipment.sandbox_locked = true
	p.skills.sandbox_locked = true
	p.skills.refresh_rank()
	p.health.heal(p.stats.get_stat(StatTypes.Stat.MAX_HEALTH))


func _leave_sandbox() -> void:
	var p := _player as Player
	if p == null or not is_instance_valid(p) or _real_loadout.is_empty():
		return
	p.equipment.sandbox_locked = false
	p.skills.sandbox_locked = false
	GameEvents.muted = true
	p.equipment.swap_to(_real_loadout["equipment"])
	p.inventory.items.assign(_real_loadout["inventory"])
	p.inventory.changed.emit()
	p.skills.restore(_real_loadout["skills"])
	GameEvents.muted = false
	p.remove_meta(&"exam_save")
	_real_loadout = {}


func try_start() -> void:
	if _state == State.RUNNING or spec == null:
		return
	var missing := _spec_problem()
	if missing != "":
		_hud.refuse(missing)
		return
	_reset_run()
	_state = State.RUNNING
	_hud.show_run()
	_hud.countdown()
	await get_tree().create_timer(3.0, false).timeout
	if _state == State.RUNNING and is_inside_tree():
		_next_wave()


func _spec_problem() -> String:
	if spec.required_routine:
		var need := _callers_needed()
		if _shared_routine_callers() < need:
			return "SPEC NOT MET: %d of your skills must call the same routine (%d do now).
Open routines.gd in the script editor ([K]), write the lines once under def name():, then add call name() to a rule of each skill. Apply each one." % [
				need, _shared_routine_callers()]
		return ""
	if spec.required_order and not _any_applied(_sorts_and_picks):
		return "SPEC NOT MET: no applied script sorts the registry and reads a place in it.
Three lines: always: registry.add(target), then registry.sort(key=hp) (least life first). Then a rule: when target is registry[0]: with a damage buff. Open your skill script with [K]."
	if spec.required_variable and not _any_applied(_keeps_a_count):
		return "SPEC NOT MET: no applied script keeps a registry.\nOne rule adds to it: always: registry.add(target) (every enemy the cast hits). Another reads it: when target in registry, or when registry.size >= N. Or make a buff grow with registry.size. Open your skill script with [K]."
	if spec.required_stop_loop and not _any_applied(_has_stop_loop):
		return "SPEC NOT MET: no applied script has a loop that stops itself.\nUse a while loop, or a for loop with break. Open your skill script with [K]."
	if spec.required_condition == "":
		return ""
	var check := ProgramObjective.new()
	check.kind = "program_condition"
	check.target = spec.required_condition
	if not check.already_met(_player):
		return "SPEC NOT MET: no applied script uses %s.\nOpen your skill script with [K], add the rule, apply it." \
				% spec.required_condition_label
	return ""


func _reset_run() -> void:
	_refill_tanks()
	for e in _alive:
		if is_instance_valid(e):
			e.queue_free()
	_alive.clear()
	_wave = 0
	_time = 0.0
	_between_waves = 0.0
	_damage = 0.0
	_fires = 0
	_casts = 0
	_rule_fires.clear()
	_routine_callers.clear()
	_order = {"hit_in": 0, "hit_out": 0, "kill_out": 0}
	_ended = false
	var health: HealthComponent = _player.get("health")
	_max_health = health.stats.get_stat(StatTypes.Stat.MAX_HEALTH)
	health.heal(_max_health)
	if not health.damage_taken.is_connected(_on_player_hurt):
		health.damage_taken.connect(_on_player_hurt)


func _process(delta: float) -> void:
	if _state != State.RUNNING or _wave == 0:
		return
	_time += delta
	_alive.assign(_alive.filter(func(e) -> bool: return is_instance_valid(e) and e.is_in_group("enemies")))
	if _alive.is_empty():
		if _wave >= spec.wave_sizes.size():
			_finish("")
			return
		_between_waves += delta
		if _between_waves >= 1.2:
			_next_wave()
	if _time >= spec.time_limit:
		_finish("TIME OUT")
		return
	_hud.update_run(_wave, spec.wave_sizes.size(), _time, spec.time_limit, _fires,
			spec.required_fires, _damage / _max_health)


func _next_wave() -> void:
	_between_waves = 0.0
	var count := spec.wave_sizes[_wave]
	var wave_def: EnemyDefinition = spec.wave_enemies[_wave] if _wave < spec.wave_enemies.size() else spec.wave_enemy
	var mods := spec.mods_for_wave(_wave)
	var tint := spec.wave_tint(_wave)
	if spec.arena_tiles != null:
		_ring_mat.albedo_color = tint
	_drain_tank(_wave)
	if spec.wave_name(_wave) != "":
		_hud.announce_wave(_wave, spec, tint)
	_wave += 1
	var turn := randf() * TAU
	for i in count:
		var a := turn + TAU * i / count
		var at := Vector3(cos(a), 0.0, sin(a)) * minf(spec.spawn_radius, RADIUS - 1.0) + Vector3.UP * 0.1
		var e := EnemySpawner.spawn_enemy(wave_def, "normal", _enemies_root, to_global(at),
				spec.enemy_level, mods)
		e.ai.aggro_range = RADIUS * 3.0
		_holo(e, tint)
		_alive.append(e)
		var numbers := get_tree().get_first_node_in_group("damage_numbers") as DamageNumbers
		if numbers:
			numbers.track(e.health)


static var _holo_shader: Shader
static var _holo_mats := {}


func _holo(enemy: Node3D, tint: Color) -> void:
	if _holo_shader == null:
		_holo_shader = Shader.new()
		_holo_shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.25, 0.95, 1.0, 1.0);
void fragment() {
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	float scan = 0.55 + 0.45 * step(0.5, fract(FRAGCOORD.y * 0.25 - TIME * 3.0));
	ALBEDO = tint.rgb * (0.3 + rim * 1.6) * scan;
}
"""
	if not _holo_mats.has(tint):
		var mat := ShaderMaterial.new()
		mat.shader = _holo_shader
		mat.set_shader_parameter("tint", tint)
		_holo_mats[tint] = mat
	for g in enemy.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).material_override = _holo_mats[tint]


func _on_event(kind: String, target: String, _amount: int) -> void:
	if _state != State.RUNNING:
		return
	match kind:
		"rule_triggered":
			if target == spec.required_condition:
				_fires += 1
			elif spec.required_variable and target.begins_with("var_"):
				_fires += 1
		"loop_repeat":
			if spec.required_stop_loop and target == "stop":
				_fires += 1
		FragmentLock.HIT_EVENT:
			if spec.required_order:
				_order["hit_in" if target == "in_order" else "hit_out"] += 1
		FragmentLock.KILL_EVENT:
			if spec.required_order:
				if target == "in_order":
					_fires += 1
				else:
					_order["kill_out"] += 1
		"routine_called":
			if spec.required_routine:
				_fires += 1
				_routine_callers[target.get_slice("|", 1)] = true
		"rule_fired":
			_rule_fires[target] = int(_rule_fires.get(target, 0)) + 1
		"cast":
			_casts += 1


func _on_player_hurt(amount: float) -> void:
	if _state != State.RUNNING:
		return
	_damage += amount
	var health: HealthComponent = _player.get("health")
	if health.current_health < _max_health * spec.fail_health:
		_finish("PROCESS TERMINATED")


func _finish(fail: String) -> void:
	if _ended:
		return
	_ended = true
	_state = State.RESULT
	for e in _alive:
		if is_instance_valid(e):
			e.queue_free()
	_alive.clear()
	var health: HealthComponent = _player.get("health")
	health.heal(_max_health)
	if fail == "" and _fires < spec.required_fires:
		fail = "SPEC NOT MET"
	if fail == "" and spec.required_routine and _routine_callers.size() < _callers_needed():
		fail = "SPEC NOT MET"
	var r := _result(fail)
	if r["passed"]:
		var qm: QuestManager = _player.get("quests")
		r["new_best"] = qm.record_exam(spec.rank_id, r["grade"])
		r["first_pass"] = qm.is_active("exam_" + spec.rank_id)
		GameEvents.report(ExamSpec.PASS_EVENT, spec.rank_id)
	_hud.show_result(r)


func _result(fail: String) -> Dictionary:
	var tier := _best_tier()
	var tier_pts := 2 if tier == "elegant" else (1 if tier == "lean" else 0)
	var fast := _time <= spec.par_time
	var unhurt := _damage / _max_health <= spec.par_damage
	var points := tier_pts + int(fast) + int(unhurt)
	return {
		"passed": fail == "", "fail": fail, "grade": ExamSpec.grade_of(points), "points": points,
		"tier": tier, "time": _time, "fast": fast, "damage": _damage / _max_health, "unhurt": unhurt,
		"fires": _fires, "casts": _casts, "waves": _wave, "rule_fires": _rule_fires.duplicate(),
		"callers": _routine_callers.size(), "callers_needed": _callers_needed() if spec.required_routine else 0,
		"order_hits": _order["hit_in"], "misorder_hits": _order["hit_out"], "misorder_kills": _order["kill_out"],
		"new_best": false, "first_pass": false,
	}


func _best_tier() -> String:
	var skills: SkillComponent = _player.get("skills")
	var best := ""
	for s in skills.sockets:
		if s.gem == null or s.skill == null or s.program == null or s.skill.program_validation == null:
			continue
		var v = s.skill.program_validation
		if not v.valid or v.tier == null or not _uses_condition(s.program):
			continue
		var t: String = v.tier.display_name.to_lower()
		if t == "elegant" or best == "":
			best = t
	return best


func _uses_condition(program: SkillProgram) -> bool:
	if spec.required_routine:
		return program.has_calls()
	if spec.required_stop_loop:
		return _has_stop_loop(program)
	if spec.required_order:
		return _sorts_and_picks(program)
	if spec.required_variable:
		return _keeps_a_count(program)
	for rule in program.flat_rules():
		for c in rule.conditions:
			if spec.required_condition == "" or c.type_id() == spec.required_condition:
				return true
	return false


func _callers_needed() -> int:
	var skills: SkillComponent = _player.get("skills")
	var socketed := 0
	for s in skills.sockets:
		if s.gem != null:
			socketed += 1
	return maxi(mini(spec.required_callers, socketed), 1)


func _shared_routine_callers() -> int:
	var skills: SkillComponent = _player.get("skills")
	var per_routine := {}
	for s in skills.sockets:
		if s.program == null or s.skill == null or s.skill.program_validation == null 				or not s.skill.program_validation.valid:
			continue
		for index in s.program.called_routines():
			per_routine[index] = int(per_routine.get(index, 0)) + 1
	var best := 0
	for index in per_routine:
		best = maxi(best, per_routine[index])
	return best


static func _has_stop_loop(program: SkillProgram) -> bool:
	for rule in program.rules:
		if rule.loop_stops_itself():
			return true
	return false


static func _sorts_and_picks(program: SkillProgram) -> bool:
	var sorts := false
	var picks := false
	for rule in program.flat_rules():
		for e in rule.effects:
			sorts = sorts or ScriptRegisters.is_sort(e)
		for c in rule.conditions:
			picks = picks or c is RegistryPositionCondition
	return sorts and picks and program.keeps_a_count()


static func _keeps_a_count(program: SkillProgram) -> bool:
	return program.keeps_a_count()


func _any_applied(check: Callable) -> bool:
	var skills: SkillComponent = _player.get("skills")
	for s in skills.sockets:
		if s.program != null and s.skill != null and s.skill.program_validation != null \
				and s.skill.program_validation.valid and check.call(s.program):
			return true
	return false


func retry() -> void:
	_state = State.BRIEF
	_hud.show_brief()


func leave() -> void:
	var town := SaveManager.last_town()
	if town == "":
		town = "res://scenes/map/town/act_1_town.tscn"
	var am := get_tree().get_first_node_in_group("area_manager") as AreaManager
	if am != null:
		am.go_to(town, &"default")


func _build_arena() -> void:
	_nav = NavigationRegion3D.new()
	_nav.name = "NavigationRegion3D"
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.agent_radius = 0.5
	_nav.navigation_mesh = nm
	add_child(_nav)

	var body := StaticBody3D.new()
	body.name = "Floor"
	_nav.add_child(body)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = RADIUS
	cyl.height = 0.4
	shape.shape = cyl
	shape.position.y = -0.2
	body.add_child(shape)
	if spec != null and spec.arena_tiles != null:
		_build_bay()
	else:
		var floor_mesh := CylinderMesh.new()
		floor_mesh.top_radius = RADIUS
		floor_mesh.bottom_radius = RADIUS
		floor_mesh.height = 0.4
		floor_mesh.radial_segments = 64
		var floor_mat := ShaderMaterial.new()
		floor_mat.shader = _grid_shader()
		floor_mesh.material = floor_mat
		var floor_vis := MeshInstance3D.new()
		floor_vis.mesh = floor_mesh
		floor_vis.position.y = -0.2
		body.add_child(floor_vis)

	var rim := StaticBody3D.new()
	rim.name = "Rim"
	_nav.add_child(rim)
	var n := 40
	for i in n:
		var a := TAU * i / n
		var s := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2.0 * PI * RADIUS / n + 0.2, 3.0, 0.6)
		s.shape = box
		s.position = Vector3(cos(a), 0.0, sin(a)) * (RADIUS + 0.3) + Vector3.UP * 1.5
		s.rotation.y = -a + PI * 0.5
		rim.add_child(s)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = HOLO
	var ring := TorusMesh.new()
	ring.inner_radius = RADIUS - 0.12
	ring.outer_radius = RADIUS + 0.05
	ring.rings = 96
	ring.ring_segments = 4
	ring.material = _ring_mat
	var ring_vis := MeshInstance3D.new()
	ring_vis.mesh = ring
	ring_vis.position.y = 0.03
	add_child(ring_vis)

	var terminal := _Terminal.new()
	terminal.chamber = self
	terminal.position = TERMINAL_AT
	add_child(terminal)


func _build_bay() -> void:
	var grid := GridMap.new()
	grid.name = "Tiles"
	grid.mesh_library = spec.arena_tiles
	grid.cell_size = Vector3(2.0, 2.0, 2.0)
	grid.cell_center_x = false
	grid.cell_center_z = false
	grid.position.y = -1.1
	grid.collision_layer = 0
	grid.collision_mask = 0
	add_child(grid)
	var inner := RADIUS + 1.6
	var reach := ceili((inner + 3.0) * 0.5)
	for x in range(-reach, reach + 1):
		for z in range(-reach, reach + 1):
			var d := Vector2(x, z).length() * 2.0
			if d <= inner:
				grid.set_cell_item(Vector3i(x, 0, z), TILE_LANE if x == 0 or z == 0 else TILE_PAVER)
			elif d <= inner + 3.0:
				grid.set_cell_item(Vector3i(x, 0, z), TILE_WALL)
				grid.set_cell_item(Vector3i(x, 1, z), TILE_WALL)
	var lamp := SpotLight3D.new()
	lamp.position = Vector3(0.0, 16.0, 0.0)
	lamp.rotation.x = -PI * 0.5
	lamp.spot_angle = 50.0
	lamp.spot_range = 24.0
	lamp.light_energy = 3.0
	lamp.light_color = Color(0.86, 0.94, 1.0)
	add_child(lamp)
	for i in spec.wave_sizes.size():
		_add_tank(spec.wave_tint(i), -PI * 0.5 + TAU * i / spec.wave_sizes.size())


func _add_tank(tint: Color, angle: float) -> void:
	var at := Vector3(cos(angle), 0.0, sin(angle)) * (RADIUS - 1.0)
	var body := StaticBody3D.new()
	body.name = "Tank"
	body.position = at
	_nav.add_child(body)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.55
	cyl.height = 3.0
	shape.shape = cyl
	shape.position.y = 1.5
	body.add_child(shape)

	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.13, 0.15, 0.19)
	steel.metallic = 0.6
	steel.roughness = 0.45
	for y in [0.15, TANK_HEIGHT + 0.4]:
		var cap := CylinderMesh.new()
		cap.top_radius = 0.6
		cap.bottom_radius = 0.6
		cap.height = 0.3
		cap.material = steel
		var cap_vis := MeshInstance3D.new()
		cap_vis.mesh = cap
		cap_vis.position.y = y
		body.add_child(cap_vis)

	var fill_mat := StandardMaterial3D.new()
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.albedo_color = tint
	var column := CylinderMesh.new()
	column.top_radius = 0.34
	column.bottom_radius = 0.34
	column.height = 1.0
	column.material = fill_mat
	var fill := MeshInstance3D.new()
	fill.mesh = column
	body.add_child(fill)

	var glass_mat := StandardMaterial3D.new()
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.albedo_color = Color(tint, 0.14)
	glass_mat.roughness = 0.1
	var glass := CylinderMesh.new()
	glass.top_radius = 0.5
	glass.bottom_radius = 0.5
	glass.height = TANK_HEIGHT
	glass.material = glass_mat
	var glass_vis := MeshInstance3D.new()
	glass_vis.mesh = glass
	glass_vis.position.y = 0.3 + TANK_HEIGHT * 0.5
	body.add_child(glass_vis)

	var light := OmniLight3D.new()
	light.light_color = tint
	light.omni_range = 5.0
	light.position.y = 1.4
	body.add_child(light)
	_tanks.append({"fill": fill, "light": light})
	_set_tank(_tanks.size() - 1, 1.0)


func _set_tank(index: int, level: float) -> void:
	var fill: MeshInstance3D = _tanks[index]["fill"]
	var height := maxf(level, 0.001) * TANK_HEIGHT
	fill.scale.y = height
	fill.position.y = 0.3 + height * 0.5
	(_tanks[index]["light"] as OmniLight3D).light_energy = 0.25 + 1.35 * level


func _drain_tank(index: int) -> void:
	if index >= _tanks.size():
		return
	if _tank_tween != null and _tank_tween.is_valid():
		_tank_tween.custom_step(10.0)
	_tank_tween = create_tween()
	_tank_tween.tween_method(func(level: float) -> void: _set_tank(index, level), 1.0, 0.0, 0.9)


func _refill_tanks() -> void:
	if _tank_tween != null:
		_tank_tween.kill()
		_tank_tween = null
	for i in _tanks.size():
		_set_tank(i, 1.0)
	_ring_mat.albedo_color = HOLO


func _bake() -> void:
	_nav.bake_navigation_mesh(false)
	navigation_is_ready = true


static func _grid_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded;
uniform vec4 base : source_color = vec4(0.01, 0.025, 0.045, 1.0);
uniform vec4 line : source_color = vec4(0.0, 0.85, 1.0, 1.0);
varying vec3 wp;
// The arena's own coordinates (the floor mesh isn't turned inside it), so the grid turns with
// the area like the dungeons' tiles do.
void vertex() { wp = VERTEX; }
void fragment() {
	vec2 g = abs(fract(wp.xz - 0.5) - 0.5) / fwidth(wp.xz);
	float l = 1.0 - min(min(g.x, g.y), 1.0);
	ALBEDO = mix(base.rgb, line.rgb * 0.55, l * 0.75);
}
"""
	return sh


class _Terminal extends Interactable:
	var chamber: ExamChamber

	func _ready() -> void:
		prompt_text = "RUN EXAM"
		prompt_height = 1.9
		face_player = false
		collision_layer = 0
		collision_mask = 3
		var s := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 1.8
		s.shape = sphere
		add_child(s)
		var body_mat := StandardMaterial3D.new()
		body_mat.albedo_color = Color(0.08, 0.09, 0.12)
		body_mat.metallic = 0.6
		var pillar := BoxMesh.new()
		pillar.size = Vector3(0.7, 1.1, 0.45)
		pillar.material = body_mat
		var p := MeshInstance3D.new()
		p.mesh = pillar
		p.position.y = 0.55
		add_child(p)
		var screen_mat := StandardMaterial3D.new()
		screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		screen_mat.albedo_color = HOLO
		var screen := BoxMesh.new()
		screen.size = Vector3(0.6, 0.4, 0.05)
		screen.material = screen_mat
		var sc := MeshInstance3D.new()
		sc.mesh = screen
		sc.position = Vector3(0.0, 1.25, 0.1)
		sc.rotation.x = -0.5
		add_child(sc)
		var light := OmniLight3D.new()
		light.light_color = HOLO
		light.light_energy = 1.2
		light.omni_range = 4.0
		light.position.y = 1.4
		add_child(light)
		super()

	func interact(_player: Node3D) -> void:
		if chamber != null:
			chamber.try_start()
