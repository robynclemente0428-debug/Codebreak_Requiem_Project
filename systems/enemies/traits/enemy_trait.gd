class_name EnemyTrait
extends Node
## A behaviour an enemy modifier adds (EnemyModifierDefinition.on_spawn_script). EnemySpawner
## adds one as a child of the enemy and lists it in enemy.traits. Traits are what make one
## script better than another in a dungeon (see DungeonThreats):
##   Firewalled  shrugs off part of every hit: few big hits beat many small ones
##   Reflector   zaps the attacker on every hit: fast attacks hurt the player
##   Swarmling   small and weak, but there are twice as many: area skills shine

var enemy: Node3D
var _popped_at := -10.0


## Called by EnemySpawner once the enemy is built.
func setup(p_enemy: Node3D) -> void:
	enemy = p_enemy


## Before the hit lands: change info.damage or set info.cancelled.
func modify_incoming(_info: HitInfo) -> void:
	pass


## After the hit landed (info.landed is true).
func after_hit(_info: HitInfo) -> void:
	pass


## Floating text over the enemy, at most once per `gap` seconds so fast attacks don't spam it.
func pop(text: String, col: Color, gap := 0.6) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _popped_at < gap or not is_instance_valid(enemy):
		return
	_popped_at = now
	var numbers := get_tree().get_first_node_in_group("damage_numbers") as DamageNumbers
	if numbers != null:
		numbers.pop_text(enemy.global_position + Vector3.UP * 2.2, text, col, 0.8)


func max_health() -> float:
	var stats := enemy.get("stats") as StatComponent
	return stats.get_stat(StatTypes.Stat.MAX_HEALTH) if stats != null else 0.0
