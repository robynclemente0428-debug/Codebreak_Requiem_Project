class_name GenerationsLock
extends EnemyTrait
## GENERATIONS (The Collector, process C-0, in the Sweep): a garbage collector cleans by
## generation, and so does this fight. Three phases by its life, each open only to one script set:
##   Gen 0  young garbage   a swarm of fresh adds               open to set A
##   Gen 1  survivors       armoured adds; half damage to it    open to set B
##                          while any of them live
##   Gen 2  old garbage     the Collector itself, attacking     open to set C
##                          twice as often
## The sets are the player's own, so this tests what each is built for. A hit from the wrong set
## does nothing and PROMOTES the generation: the Collector heals a little. Let the adds pile up
## and it sweeps them: one dies and it heals.

## Shown on the lock banner (LockBanner) and under the boss's quest objective.
const LOCK_NAME := "GENERATIONS"
const HINT := "Three phases, three script sets: A, then B, then C. The wrong set heals it. Watch this banner."

const GENS := [
	{"name": "GENERATION 0", "enemy": "res://data/enemies/glitchling.tres", "count": 5, "every": 9.0, "mods": []},
	{"name": "GENERATION 1", "enemy": "res://data/enemies/marker_drone.tres", "count": 2, "every": 11.0,
			"mods": ["res://data/enemy_modifiers/ironclad.tres"]},
	{"name": "GENERATION 2", "enemy": "res://data/enemies/marker_drone.tres", "count": 1, "every": 14.0, "mods": []},
]
const COL_GEN := Color(1.0, 0.25, 0.25)
const COL_OK := Color(0.45, 1.0, 0.6)
const COL_WRONG := Color(1.0, 0.75, 0.3)
const WRONG_GAP := 0.8
const LAST_WORDS := "YOU ARE NOT IN MY RECORDS. YOU CANNOT BE COPIED. ERROR."

## Metres: the fight starts once a player is this close.
@export var notice_range := 18.0
## Share of its life one PROMOTED costs you.
@export var promote_heal := 0.01
## Adds alive before it starts sweeping them, seconds between sweeps, and what each one heals.
@export var sweep_at := 5
@export var sweep_every := 5.0
@export var sweep_heal := 0.03
## While Gen 1's adds live, its damage is multiplied by this.
@export var shielded_mult := 0.5

var promoted_count := 0                          # for the test, and a HUD readout
var swept_count := 0

var _gen := -1
var _adds: Array = []
var _add_timer := 0.0
var _sweep_timer := 0.0
var _promote_at := -10.0
var _dead := false


func setup(p_enemy: Node3D) -> void:
	super(p_enemy)
	var hp := enemy.get("health") as HealthComponent
	if hp != null:
		hp.died.connect(_on_died)


## 0, 1 or 2; -1 before the fight starts.
func generation() -> int:
	return _gen


## The script set this generation is open to (index: A = 0).
func open_set() -> int:
	return maxi(_gen, 0)


func adds_alive() -> int:
	_adds.assign(_adds.filter(func(e) -> bool: return is_instance_valid(e) and not SkillBehavior.is_dead(e)))
	return _adds.size()


func modify_incoming(info: HitInfo) -> void:
	if _dead or info.cast == null or not info.cast.is_valid():
		return
	_update_generation()
	var used := _set_of(info.cast.caster)
	var gen_name: String = GENS[open_set()]["name"]
	var set_name: String = SkillComponent.SET_NAMES[open_set()]
	if used != open_set():
		info.absorbed = true
		var now := Time.get_ticks_msec() / 1000.0
		if now - _promote_at >= WRONG_GAP:
			_promote_at = now
			promoted_count += 1
			var hp := enemy.get("health") as HealthComponent
			if hp != null:
				hp.heal(max_health() * promote_heal)
			say("%s PROMOTED // USE SET %s" % [gen_name, set_name], COL_WRONG, 0.95)
		return
	if open_set() == 1 and adds_alive() > 0:
		info.damage *= shielded_mult
		pop("SHIELDED // KILL THE SURVIVORS", COL_GEN, 1.6)
	else:
		pop("%s // SET %s" % [gen_name, set_name], COL_OK, 2.4)


func after_hit(_info: HitInfo) -> void:
	if not _dead:
		_update_generation()


func _process(delta: float) -> void:
	if _dead or not is_instance_valid(enemy):
		return
	if _gen < 0:
		var p := get_tree().get_first_node_in_group("players") as Node3D
		if p != null and p.global_position.distance_to(enemy.global_position) <= notice_range:
			_enter_generation(0)
		return
	_update_generation()
	_add_timer -= delta
	if _add_timer <= 0.0:
		_add_timer = GENS[_gen]["every"]
		_spawn_adds()
	if adds_alive() >= sweep_at:
		_sweep_timer -= delta
		if _sweep_timer <= 0.0:
			_sweep_timer = sweep_every
			_sweep()


## Moves on when its life has fallen far enough. Life going back up doesn't undo a generation.
func _update_generation() -> void:
	if _gen < 0:
		return
	var hp := enemy.get("health") as HealthComponent
	if hp == null:
		return
	var share := hp.current_health / maxf(max_health(), 1.0)
	var want := 0 if share > 2.0 / 3.0 else (1 if share > 1.0 / 3.0 else 2)
	if want > _gen:
		_enter_generation(want)


func _enter_generation(gen: int) -> void:
	_gen = gen
	_add_timer = 0.5
	say("%s. MARKED. // OPEN TO SET %s" % [GENS[gen]["name"], SkillComponent.SET_NAMES[gen]], COL_GEN, 1.1)
	var caster := _enemy_skills()
	if gen == 2 and caster != null:
		caster.skill_cooldown *= 0.5


func _spawn_adds() -> void:
	var g: Dictionary = GENS[_gen]
	var def := load(g["enemy"]) as EnemyDefinition
	if def == null:
		return
	var mods: Array = []
	for path in g["mods"]:
		mods.append(load(path))
	var level: int = enemy.get("level") if enemy.get("level") != null else 1
	var nav := enemy.get("nav") as NavigationAgent3D
	var start := randf() * TAU
	for i in int(g["count"]):
		var a := start + TAU * float(i) / float(g["count"])
		var at := enemy.global_position + Vector3(cos(a), 0.0, sin(a)) * 5.0
		if nav != null and nav.get_navigation_map().is_valid() \
				and NavigationServer3D.map_get_iteration_id(nav.get_navigation_map()) > 0:
			var snapped := NavigationServer3D.map_get_closest_point(nav.get_navigation_map(), at)
			if snapped != Vector3.ZERO:
				at = snapped
		var e := EnemySpawner.spawn_enemy(def, "normal", enemy.get_parent(), at + Vector3.UP * 0.1, level, mods)
		if e == null:
			continue
		if e.get("ai") != null:
			e.ai.aggro_range = 40.0
		var numbers := get_tree().get_first_node_in_group("damage_numbers") as DamageNumbers
		if numbers != null:
			numbers.track(e.health)
		_adds.append(e)


## Too many marked processes: it collects the nearest, and the memory feeds it.
func _sweep() -> void:
	var nearest: Node3D = null
	var best := INF
	for e in _adds:
		if is_instance_valid(e) and not SkillBehavior.is_dead(e):
			var d: float = e.global_position.distance_to(enemy.global_position)
			if d < best:
				best = d
				nearest = e
	if nearest == null:
		return
	nearest.health.current_health = 0.0
	nearest.health.died.emit()
	swept_count += 1
	var hp := enemy.get("health") as HealthComponent
	if hp != null:
		hp.heal(max_health() * sweep_heal)
	say("REFERENCE TO NULL. COLLECTING.", COL_GEN, 0.95)


func _set_of(caster: Node) -> int:
	var skills := caster.get("skills") as SkillComponent if caster != null else null
	if skills == null:
		var p := get_tree().get_first_node_in_group("players")      # a hologram: its owner's set
		skills = p.get("skills") as SkillComponent if p != null else null
	return skills.script_set if skills != null else 0


func _on_died() -> void:
	_dead = true
	say(LAST_WORDS, COL_GEN, 1.05)
	for e in _adds:
		if is_instance_valid(e) and not SkillBehavior.is_dead(e):
			e.health.current_health = 0.0
			e.health.died.emit()
	_adds.clear()


## EnemySpawner adds this after the traits, so it's looked up when needed.
func _enemy_skills() -> EnemySkills:
	for c in enemy.get_children():
		if c is EnemySkills:
			return c
	return null
