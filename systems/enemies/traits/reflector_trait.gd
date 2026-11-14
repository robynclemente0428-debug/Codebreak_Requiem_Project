extends EnemyTrait
## REFLECTOR: every hit that lands zaps the attacker for flat damage, through armour. The zap
## grows with the Reflector's level, not with the hit, so a light hit costs as much as a heavy
## one: attacking fast hurts, and fewer, bigger hits (or lowering attack speed) is the answer.
##   zap = zap_base + zap_per_level * (level - 1)     level 1: 5, level 6: 8, level 10: 10.4

const COL := Color(0.80, 0.45, 1.0)

## A lock (EnemyTrait): its tag, hover plate row and body, a chrome sheen.
const LOCK_NAME := "REFLECT"
const HINT := "Every hit you land zaps you back, however light. Fewer, bigger hits."
const LOCK_COLOR := COL
const LOCK_SHAPE := "diamond"
const LOCK_AURA := 4                 # EnemySilhouette.AURA_REFLECT
const BANNER := false                # it pops on every hit: the tag is enough

## Damage of each zap at level 1.
@export var zap_base := 5.0
## Added for every level above 1.
@export var zap_per_level := 0.6
## At most one zap per this many seconds from one Reflector (an area hit counts once).
@export var zap_gap := 0.12

var _zapped_at := -10.0


func zap_damage() -> float:
	var lvl: int = enemy.get("level") if is_instance_valid(enemy) and enemy.get("level") != null else 1
	return zap_base + zap_per_level * maxi(lvl - 1, 0)


## On its tag: what each of your hits costs you.
func tag_state() -> String:
	return "ZAP %d" % roundi(zap_damage()) if is_instance_valid(enemy) else ""


func after_hit(info: HitInfo) -> void:
	if info.facts == null or not info.facts.by_player or not is_instance_valid(info.facts.caster):
		return                                    # enemies' own skills (and holograms) never trip it
	var caster := info.facts.caster
	var now := Time.get_ticks_msec() / 1000.0
	if now - _zapped_at < zap_gap:
		return
	_zapped_at = now
	var hp := caster.get("health") as HealthComponent
	if hp == null:
		return
	Coop.hit_source = Coop.Hit.ENEMY             # co-op: a guest's zap reaches the guest's own machine
	hp.take_damage(zap_damage(), true)
	Coop.hit_source = Coop.Hit.NONE
	pop("REFLECT", COL, 0.8)
