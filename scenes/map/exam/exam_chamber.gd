class_name ExamChamber
extends GameArea
## Examiner Sudo's sandbox: where rank exams are sat. A round arena of raw grid in the void,
## built in code, with an EXAM TERMINAL in the middle of it.
##
##   1. Arriving shows the exam's spec card (ExamSpec.brief). Edit your script ([K]) until it
##      meets the spec, then press [T] at the terminal. It refuses a script without the
##      required condition, like a compiler would.
##   2. The run: waves of "test processes" (hologram enemies) close in. The HUD shows the wave,
##      the clock, how often your rule fired, and the health you've lost. The sandbox ends the
##      run before you could die (ExamSpec.fail_health).
##   3. The result: PASS / MERIT / DISTINCTION, and Sudo's debrief of YOUR script, from what
##      happened in the run. RETRY, or RETURN to town. A first pass reports exam_passed, which
##      completes the exam quest; Sudo hands out the rank. The best grade is kept (QuestManager).
##
## Enter with ExamChamber.enter(tree, "operator") (Sudo's dialogue: > exam operator).
## While inside, the sandbox lends the perks the exam asks for (ExamSpec.lends, Ranks.lent):
## the Architect exam lends loops to players who don't hold the rank yet.

const SCENE := "res://scenes/map/exam/exam_chamber.tscn"
const RADIUS := 11.0                     # metres: the arena floor
const TERMINAL_AT := Vector3(0.0, 0.0, -2.5)
const SPAWN_AT := Vector3(0.0, 0.0, 2.0)
const HOLO := Color(0.25, 0.95, 1.0)

## Which exam the next visit runs (set by enter()).
static var pending_rank := "operator"

## AreaManager waits for this before fading in (like a dungeon's navmesh).
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
var _rule_fires := {}                    # "gem#index" -> times
var _ended := false


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
	# The HUD goes on the game window, not in here: the area lives in the low-resolution 3D view,
	# and UI inside it would be drawn three times too big. Freed when the chamber goes.
	_hud = ExamHud.new()
	_hud.chamber = self
	get_tree().root.add_child.call_deferred(_hud)
	GameEvents.happened.connect(_on_event)
	_bake.call_deferred()


func _exit_tree() -> void:
	if is_instance_valid(_hud):
		_hud.queue_free()
	if not Ranks.lent.is_empty():
		Ranks.lent = PackedStringArray()          # leaving: the lent perks go back
		_refresh_skills()


## Rebuilds the player's skills against the perks held now (lent or taken back).
func _refresh_skills() -> void:
	var p := _player if is_instance_valid(_player) else get_tree().get_first_node_in_group("players")
	var skills: SkillComponent = p.get("skills") if p != null else null
	if skills != null:
		skills.refresh_rank()


func get_spawn_position(_spawn_id: StringName = DEFAULT_SPAWN) -> Vector3:
	return to_global(SPAWN_AT)


func on_player_arrived(player: Node3D) -> void:
	_player = player
	if spec != null and not spec.lends.is_empty():
		Ranks.lent = spec.lends
		_refresh_skills()
	_hud.show_brief()


# ---------- THE RUN ----------
## The terminal: checks the script against the spec, then starts the run (or says what's missing).
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


## "" if the player's applied script meets the spec, otherwise what's wrong.
func _spec_problem() -> String:
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
	# assign(): filter() returns an untyped Array. Untyped `e`: freed enemies are still in the list.
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
	_wave += 1
	var turn := randf() * TAU
	for i in count:
		var a := turn + TAU * i / count
		var at := Vector3(cos(a), 0.0, sin(a)) * minf(spec.spawn_radius, RADIUS - 1.0) + Vector3.UP * 0.1
		var e := EnemySpawner.spawn_enemy(spec.wave_enemy, "normal", _enemies_root, to_global(at),
				spec.enemy_level, [])
		e.ai.aggro_range = RADIUS * 3.0          # they all come for you
		_holo(e)
		_alive.append(e)
		var numbers := get_tree().get_first_node_in_group("damage_numbers") as DamageNumbers
		if numbers:
			numbers.track(e.health)


## Test processes are holograms: every mesh of the model is drawn in glowing cyan, brightest at
## its edges, with scanlines rolling up it.
static var _holo_mat: ShaderMaterial


func _holo(enemy: Node3D) -> void:
	if _holo_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.25, 0.95, 1.0, 1.0);
void fragment() {
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	float scan = 0.55 + 0.45 * step(0.5, fract(FRAGCOORD.y * 0.25 - TIME * 3.0));
	ALBEDO = tint.rgb * (0.3 + rim * 1.6) * scan;
}
"""
		_holo_mat = ShaderMaterial.new()
		_holo_mat.shader = sh
	for g in enemy.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).material_override = _holo_mat


func _on_event(kind: String, target: String, _amount: int) -> void:
	if _state != State.RUNNING:
		return
	match kind:
		"rule_triggered":
			if target == spec.required_condition:
				_fires += 1
		"loop_repeat":
			if spec.required_stop_loop and target == "stop":
				_fires += 1
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


## Ends the run: `fail` is why it failed, or "" if every wave was cleared.
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
		"new_best": false, "first_pass": false,
	}


## The best efficiency tier ("elegant", "lean" or "") of an applied script that meets the spec.
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
	if spec.required_stop_loop:
		return _has_stop_loop(program)
	for rule in program.rules:
		for c in rule.conditions:
			if spec.required_condition == "" or c.type_id() == spec.required_condition:
				return true
	return false


static func _has_stop_loop(program: SkillProgram) -> bool:
	for rule in program.rules:
		if rule.loop != null and rule.loop.stops_itself():
			return true
	return false


## True when one of the player's applied (valid) scripts passes `check`.
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


# ---------- THE ARENA ----------
func _build_arena() -> void:
	_nav = NavigationRegion3D.new()
	_nav.name = "NavigationRegion3D"
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.agent_radius = 0.5
	_nav.navigation_mesh = nm
	add_child(_nav)

	# Floor: a disc of raw grid
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

	# The rim: invisible wall all round, and a glowing ring to show where it is
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
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = HOLO
	var ring := TorusMesh.new()
	ring.inner_radius = RADIUS - 0.12
	ring.outer_radius = RADIUS + 0.05
	ring.rings = 96
	ring.ring_segments = 4
	ring.material = ring_mat
	var ring_vis := MeshInstance3D.new()
	ring_vis.mesh = ring
	ring_vis.position.y = 0.03
	add_child(ring_vis)

	var terminal := _Terminal.new()
	terminal.chamber = self
	terminal.position = TERMINAL_AT
	add_child(terminal)


func _bake() -> void:
	_nav.bake_navigation_mesh(false)        # small arena: baking on the spot is quick
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


## The exam terminal in the middle of the arena: [T] RUN EXAM.
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
