class_name AuditLock
extends EnemyTrait
## AUDIT (The Auditor, at The Expedition's End): the Compiler Guild expedition's examiner, rewritten
## by the Null and still grading. It only accepts work that earns a tier: a hit from a skill whose
## script is LEAN or ELEGANT lands, and ELEGANT lands harder. A skill with no script, or one too
## heavy to earn a tier, is ungraded: absorbed. Practice for Sudo's Engineer exam (ELEGANT).
##     "GRADE: ELEGANT"     a hit from an ELEGANT script: lands, x1.25
##     "GRADE: LEAN"        a hit from a LEAN script: lands
##     "UNGRADED // ..."    anything else: absorbed, with what it would take

## Shown on the lock banner (LockBanner) and under the boss's quest objective.
const LOCK_NAME := "AUDIT"
const HINT := "It grades every hit. Only a skill whose script earns LEAN or ELEGANT gets through, and ELEGANT lands harder. Trim the script."

const COL_ELEGANT := Color(0.3, 1.0, 0.6)
const COL_LEAN := Color(0.6, 0.9, 1.0)
const COL_REJECT := Color(1.0, 0.35, 0.35)
const GAP := 1.2

## ELEGANT hits are multiplied by this.
@export var elegant_mult := 1.25


func modify_incoming(info: HitInfo) -> void:
	var f := info.facts
	if f == null or not f.by_player:
		return
	match f.tier:                                 # "elegant", "lean", or "": ungraded (HitFacts.tier)
		"elegant":
			info.damage *= elegant_mult
			pop("GRADE: ELEGANT", COL_ELEGANT, GAP)
		"lean":
			pop("GRADE: LEAN", COL_LEAN, GAP)
		_:
			info.absorbed = true
			pop(_why(f), COL_REJECT, GAP)


func _why(f: HitFacts) -> String:
	if not f.has_script:
		return "UNGRADED // NO SCRIPT"
	if f.blocks_to_next > 0:
		return "UNGRADED // %d BLOCK%s TOO MANY" % [f.blocks_to_next, "" if f.blocks_to_next == 1 else "S"]
	return "UNGRADED // TRIM THE SCRIPT"
