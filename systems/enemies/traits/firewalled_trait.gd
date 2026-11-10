extends EnemyTrait
## FIREWALLED: blocks a share of every hit it takes, before armour. It only depends on the
## damage the player deals, never on the enemy's own health, so even a big boss stays killable:
## the answer is simply more damage (raise the damage knob, trade attack speed for it).

const COL := Color(1.0, 0.62, 0.25)

## A lock (EnemyTrait): its tag, hover plate row and body, an orange hex shield.
const LOCK_NAME := "FIREWALLED"
const HINT := "Blocks most of every hit. Fewer, bigger hits get through: raise damage, trade attack speed for it."
const LOCK_COLOR := COL
const LOCK_SHAPE := "hex"
const LOCK_AURA := 3                 # EnemySilhouette.AURA_FIREWALL
const BANNER := false                # it pops on every hit: the tag is enough

## Share of each hit the firewall blocks (0.75 = the enemy takes 25%).
@export_range(0.0, 0.95, 0.05) var block_fraction := 0.75


## On its tag: how much of each hit it blocks.
func tag_state() -> String:
	return "-%d%%" % roundi(block_fraction * 100.0)


func modify_incoming(info: HitInfo) -> void:
	info.damage *= 1.0 - block_fraction
	pop("FIREWALL", Color(COL, 0.8), 1.2)
