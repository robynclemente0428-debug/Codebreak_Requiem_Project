class_name HitInfo
extends RefCounted
## One hit from a skill. SkillBehavior.hit() fills it in and hands it to every support hook.
## Supports can change `damage` or set `cancelled` in modify_hit(), before the damage is applied.

var cast: SkillCast
var target: Node
## Where the target stood when it was hit (kept even after it dies and is freed).
var position := Vector3.ZERO
## Damage before the target's armour. Supports may change this in modify_hit().
var damage := 0.0
var is_crit := false
## Set to true in modify_hit() to stop the hit entirely.
var cancelled := false

## Filled in after the damage is applied:
var dealt := 0.0          # damage after armour
var landed := false       # false if the target was already dead or had no health
var killed := false
