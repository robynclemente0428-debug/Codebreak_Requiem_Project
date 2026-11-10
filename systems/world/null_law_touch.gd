class_name NullLawTouch
extends EnemyTrait
## The Null Laws' hold on every enemy in a Null zone (NullLawDirector adds one to each): the
## laws that change how hard the player hits.
##   LIFE READS INVERTED   your hits grow as your life falls: x0.7 at full life, up to x1.6 near death
##   NEAR MEANS FAR        your hits fall off up close and grow at range: x0.6 within 4 m, up to x1.5 at 10 m
## Now and then (one callout at a time across all enemies) it says what the law did to a hit.
## A player's kill under any law reports "null_law_kill" with the law's id (UNDER NEW RULES).

const NullLawsRef := preload("res://systems/world/null_laws.gd")
const COL_UP := Color(0.85, 0.6, 1.0)
const COL_DOWN := Color(1.0, 0.45, 0.5)
## Seconds between callouts, shared by every enemy so a crowd doesn't spam them.
const CALLOUT_GAP := 1.6

static var _callout_at := -10.0


func modify_incoming(info: HitInfo) -> void:
	if info.cast == null or not info.cast.is_valid():
		return
	var caster: Node = info.cast.caster
	if caster == null or not caster.is_in_group("players"):
		return
	var mult := 1.0
	var why := ""
	if NullLawsRef.law == "life_inverted":
		var life := ProgramCondition.health_fraction(caster)
		mult = NullLawsRef.inverted_life_mult(life)
		why = "HURT" if mult > 1.0 else "HEALTHY"
	elif NullLawsRef.law == "near_is_far" and caster is Node3D:
		var d: Vector3 = (caster as Node3D).global_position - enemy.global_position
		mult = NullLawsRef.distance_mult(Vector2(d.x, d.z).length())
		why = "FAR" if mult > 1.0 else "TOO NEAR"
	else:
		return
	info.damage *= mult
	var now := Time.get_ticks_msec() / 1000.0
	if absf(mult - 1.0) >= 0.15 and now - _callout_at >= CALLOUT_GAP:
		_callout_at = now
		pop("%s x%.1f" % [why, mult], COL_UP if mult > 1.0 else COL_DOWN, 0.0)


func after_hit(info: HitInfo) -> void:
	if not info.killed or NullLawsRef.law == "" or info.cast == null or not info.cast.is_valid():
		return
	if info.cast.caster != null and info.cast.caster.is_in_group("players"):
		GameEvents.report("null_law_kill", NullLawsRef.law)
