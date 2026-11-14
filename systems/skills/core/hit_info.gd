class_name HitInfo
extends RefCounted
## One hit from a skill. SkillBehavior.hit() fills it in and hands it to every support hook.
## Supports can change `damage` or set `cancelled` in modify_hit(), before the damage is applied.

var cast: SkillCast
var target: Node
## What the target's traits may know about this hit (set when the target has traits). Traits
## read this, never `cast`, so a guest's hit can later be judged on the host (HitFacts).
var facts: HitFacts
## Where the target stood when it was hit (kept even after it dies and is freed).
var position := Vector3.ZERO
## Damage before the target's armour. Supports may change this in modify_hit().
var damage := 0.0
var is_crit := false
## Per-hit script rules (ProgramSupport.modify_hit): extra leech for this hit, and barrier
## (share of max life) / guard given to the caster if it lands. Applied in SkillBehavior.hit().
var leech_bonus := 0.0
var barrier_bonus := 0.0
var guard_bonus := 0.0
## Support gem flags a per-hit script rule changed for this hit only (flag key -> amount), e.g.
## "explode_radius": a marked enemy explodes bigger. Read them with flag().
var flag_bonus := {}
## Set to true in modify_hit() to stop the hit entirely.
var cancelled := false
## Set by an enemy trait (a boss lock) in modify_incoming: the hit counts as landed (loops,
## on-hit supports and conditions see it) but deals no damage. Unlike cancelled.
var absorbed := false

## Filled in after the damage is applied:
var dealt := 0.0          # damage after armour
var landed := false       # false if the target was already dead or had no health
var killed := false


## A flag for this hit: the cast's, plus what a per-hit script rule added for this hit only.
func flag(key: String) -> float:
	return (cast.flag(key) if cast != null else 0.0) + float(flag_bonus.get(key, 0.0))
