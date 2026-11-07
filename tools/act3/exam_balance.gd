extends Node
## Sits the real Strategist exam with a bot: every class's exam loadout, several scripts, two ways of
## playing. Run this scene from the editor (F6). Boots main.tscn with NO character slot loaded, so
## nothing is saved. One line per run in exam_balance_results.txt (gitignored).
##
## The bot aims perfectly and never wastes a cast, so its times are a best case for its positioning.
##   stand  faces the nearest enemy and attacks. Melee walks up to it, and it never backs away.
##   kite   as stand, but keeps off the rim and backs away: melee from three or more enemies within
##          reach, ranged from anything close.

const MAIN := "res://scenes/map/main.tscn"
const YARD := "res://scenes/map/town/act_3_quarantine_yard.tscn"
const RESULTS := "res://tools/act3/exam_balance_results.txt"
const CLASSES := ["raider", "rogue", "gladiator", "assassin", "paladin", "enchanter"]
const SCRIPTS := ["none", "flat", "read", "grow"]
const BOTS := ["stand", "kite"]
const MELEE_REACH := 2.0

## Game speed. Some enemy animation timers run on real time, so compare with 1.0 before trusting it.
@export var speed := 3.0
@export var classes: PackedStringArray = PackedStringArray(CLASSES)
@export var scripts: PackedStringArray = PackedStringArray(SCRIPTS)
@export var bots: PackedStringArray = PackedStringArray(BOTS)
@export var repeats := 1
@export var result_file := RESULTS

var _chamber: ExamChamber
var _bot := ""
var _driving := false
var _cooldown := 0.0
var _starved := 0.0
var _melee := true
var _last_alive := 0
var _wave_started := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	var main: Node = load(MAIN).instantiate()
	for n in main.find_children("*", "", true, false):
		if n is AreaManager:
			n.start_area = YARD
	reparent(get_tree().root)
	var old := get_tree().current_scene
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	if old != null and old != self:
		old.queue_free()
	while not (_player() != null and _am() != null and _am().current_area != null and _am().can_go()):
		await get_tree().process_frame
	ExamChamber.enter(get_tree(), "strategist")
	while not (_am().current_area is ExamChamber and _am().can_go()):
		await get_tree().process_frame
	_chamber = _am().current_area as ExamChamber
	_write("speed %.1f" % speed, true)
	_write("class gem hp | script bot | result time waves damage fires casts starved tier grade | wave seconds | script points")
	Engine.time_scale = speed
	for class_id in classes:
		_wear_class(class_id)
		for script_kind in scripts:
			for bot in bots:
				for _i in repeats:
					await _sit(class_id, script_kind, bot)
	Engine.time_scale = 1.0
	_write("ALL DONE")


## Puts the player in this class's exam loadout, as if they had walked in with it.
func _wear_class(class_id: String) -> void:
	var p := _player() as Player
	_chamber._leave_sandbox()
	var c: ClassData = load("res://data/classes/%s.tres" % class_id)
	p.class_data = c
	var base: Dictionary = p.stats.base_stats.duplicate()
	base[StatTypes.Stat.STRENGTH] = float(c.strength)
	base[StatTypes.Stat.DEXTERITY] = float(c.dexterity)
	base[StatTypes.Stat.INTELLIGENCE] = float(c.intelligence)
	p.stats.base_stats = base
	p.apply_movement_trait(c.get_trait())
	var skills: SkillComponent = p.skills
	for s in skills.sockets:
		s.gem = null
		s.skill = null
		s.program = null
		s.sets.fill(null)
	skills.bindings.clear()
	var gem := ItemInstance.new()
	gem.definition = c.starting_skill_gem
	skills.socket_skill(0, gem)
	skills.bind_action(SkillComponent.ACTIONS[0], 0)
	_chamber._enter_sandbox()
	var tags: Array = skills.sockets[0].gem.definition.skill_gem.tags
	var gem_id: String = skills.sockets[0].gem.definition.skill_gem.id
	_melee = gem_id == "strike" or gem_id == "slam"
	assert(tags != null)


## One run of the exam.
func _sit(class_id: String, script_kind: String, bot: String) -> void:
	var p := _player() as Player
	var skills: SkillComponent = p.skills
	var spec := _chamber.spec
	var counted := script_kind == "read" or script_kind == "grow"
	var keeps_required := spec.required_variable
	var fires_required := spec.required_fires
	if not counted:                                   # the controls don't keep a count
		spec.required_variable = false
		spec.required_fires = 0
	var built := _best_program(script_kind)
	if built != null:
		var v := skills.set_program(0, built)
		if not v.valid:
			_write("%s %s: INVALID %s" % [class_id, script_kind, "; ".join(v.errors)])
			return
	else:
		skills.set_program(0, null)
	if p._dead:
		p.revive()
	p.mana.initialize()
	p.global_position = _chamber.get_spawn_position()
	p.velocity = Vector3.ZERO
	p.input_locked = true
	_chamber.retry()
	_bot = bot
	_cooldown = 0.0
	_starved = 0.0
	_last_alive = 0
	_wave_started = {}
	_chamber.try_start()
	await get_tree().process_frame
	_driving = true
	while not _chamber._ended:
		await get_tree().process_frame
	_driving = false
	p.walking = false
	var outcome := "PASS"
	if _last_alive > 0:
		outcome = "TIMEOUT" if _chamber._time >= spec.time_limit else "KILLED"
	elif _chamber._fires < spec.required_fires:
		outcome = "SPEC"
	var r := _chamber._result("")
	var waves := PackedStringArray()
	for w in range(1, spec.wave_sizes.size() + 1):
		if _wave_started.has(w):
			var ended: float = _wave_started[w + 1] if _wave_started.has(w + 1) else _chamber._time
			waves.append("%.1f" % (ended - float(_wave_started[w])))
	var skill := skills.sockets[0].skill
	var line_points := skill.program_validation.points_used if built != null and skill.program_validation != null else 0.0
	_write("%s %s %.0f | %s %s | %s %.1fs w%d dmg%d%% fires%d casts%d starved%.1fs %s %s | %s | %s %.1fpts" % [
		class_id, skills.sockets[0].gem.definition.skill_gem.id, p.stats.get_stat(StatTypes.Stat.MAX_HEALTH),
		script_kind, bot, outcome, _chamber._time, _chamber._wave, roundi(_chamber._damage / _chamber._max_health * 100.0),
		_chamber._fires, _chamber._casts, _starved, r["tier"] if r["tier"] != "" else "-", r["grade"],
		" ".join(waves), _describe(built), line_points])
	spec.required_variable = keeps_required
	spec.required_fires = fires_required


## The strongest version of this kind of script the class's point budget allows.
func _best_program(kind: String) -> SkillProgram:
	if kind == "none":
		return null
	var skills: SkillComponent = (_player() as Player).skills
	for steps in range(20, 0, -1):
		var p := _program(kind, steps)
		if skills.preview_program(0, p).valid:
			return p
	return null


func _program(kind: String, steps: int) -> SkillProgram:
	var p := SkillProgram.new()
	match kind:
		"flat":
			var always := ProgramRule.new()
			always.effects.append(ProgramEffect.make(&"damage", steps))
			p.rules.append(always)
		"read":                                       # when enemies_nearby: x += 1 / when x >= 3: damage, x = 0
			p.rules.append(_counting_rule())
			var spend := ProgramRule.new()
			spend.conditions.append(VarCondition.make("x", ">=", 3))
			spend.effects.append(ProgramEffect.make(&"damage", steps))
			spend.effects.append(ProgramEffect.make_write("x", "=", 0))
			p.rules.append(spend)
		"grow":                                       # when enemies_nearby: x += 1 / always: damage += x * N%
			p.rules.append(_counting_rule())
			var grow := ProgramRule.new()
			var e := ProgramEffect.make(&"damage", steps)
			e.ramp = 0
			grow.effects.append(e)
			p.rules.append(grow)
	return p


func _counting_rule() -> ProgramRule:
	var rule := ProgramRule.new()
	rule.conditions.append(ProgramConditions.create("enemies_nearby"))
	rule.effects.append(ProgramEffect.make_write("x", "+=", 1))
	return rule


func _describe(p: SkillProgram) -> String:
	if p == null:
		return "no script"
	for rule in p.rules:
		for e in rule.effects:
			if e.knob == &"damage":
				return "damage steps %d" % e.steps
	return "?"


func _physics_process(delta: float) -> void:
	if not _driving or _chamber == null or _chamber._ended:
		return
	var p := _player() as Player
	if p == null or p._dead:
		return
	if _chamber._wave > 0 and not _wave_started.has(_chamber._wave):
		_wave_started[_chamber._wave] = _chamber._time
	_last_alive = _chamber._alive.filter(func(e) -> bool: return is_instance_valid(e) and e.is_in_group("enemies")).size()
	var target := _nearest(p)
	_move(p, target)
	if target == null:
		return
	var to := target.global_position - p.global_position
	to.y = 0.0
	if to.length_squared() > 0.01:
		p.global_rotation.y = atan2(to.x, to.z)
	p._cursor_point = target.global_position
	_attack(p, to.length(), delta)


func _nearest(p: Node3D) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for e in _chamber._alive:
		if is_instance_valid(e) and e.is_in_group("enemies"):
			var d := p.global_position.distance_squared_to(e.global_position)
			if d < best_d:
				best_d = d
				best = e
	return best


## As player._handle_attack does it, without the mouse and keyboard.
func _attack(p: Player, distance: float, delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _cooldown > 0.0 or (_melee and distance > MELEE_REACH):
		return
	var action: StringName = SkillComponent.ACTIONS[0]
	var skill := p.skills.get_skill(action)
	if skill == null or not skill.weapon_allows(p.equipment):
		return
	if not skill.can_afford(p.mana):
		_starved += delta
		return
	_cooldown = skill.get_cooldown(p.stats)
	skill.cast(p, p.stats, p.mana)
	GameEvents.report("cast", String(action))


func _move(p: Player, target: Node3D) -> void:
	var dir := Vector3.ZERO
	if _bot == "kite":
		var close := 0
		for e in _chamber._alive:
			if not is_instance_valid(e) or not e.is_in_group("enemies"):
				continue
			var away: Vector3 = p.global_position - e.global_position
			away.y = 0.0
			var d := away.length()
			if d > 0.01 and d < (MELEE_REACH if _melee else 6.0):
				dir += away / (d * d)
				close += 1
		if _melee and close < 3:
			dir = Vector3.ZERO
		var from_centre := p.global_position - _chamber.global_position
		from_centre.y = 0.0
		if from_centre.length() > ExamChamber.RADIUS - 2.5:
			dir -= from_centre.normalized() * 2.0
	if dir == Vector3.ZERO and _melee and target != null:
		var to := target.global_position - p.global_position
		to.y = 0.0
		if to.length() > MELEE_REACH * 0.8:
			dir = to
	var moving := dir.length_squared() > 0.0001
	var speed_now := p.stats.get_stat(StatTypes.Stat.MOVE_SPEED)
	var flat := dir.normalized() * speed_now if moving else Vector3.ZERO
	p.velocity.x = flat.x
	p.velocity.z = flat.z
	p.walking = moving
	p.move_and_slide()


func _write(line: String, fresh := false) -> void:
	var f: FileAccess
	if fresh or not FileAccess.file_exists(result_file):
		f = FileAccess.open(result_file, FileAccess.WRITE)
	else:
		f = FileAccess.open(result_file, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
	if f != null:
		f.store_line(line)
		f.close()


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("players") as Node3D


func _am() -> AreaManager:
	return get_tree().get_first_node_in_group("area_manager") as AreaManager
