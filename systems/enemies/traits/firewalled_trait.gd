extends EnemyTrait
## FIREWALLED: blocks a share of every hit it takes, before armour. It only depends on the
## damage the player deals, never on the enemy's own health, so even a big boss stays killable:
## the answer is simply more damage (raise the damage knob, trade attack speed for it).

const COL := Color(1.0, 0.62, 0.25)

## Share of each hit the firewall blocks (0.75 = the enemy takes 25%).
@export_range(0.0, 0.95, 0.05) var block_fraction := 0.75


func modify_incoming(info: HitInfo) -> void:
	info.damage *= 1.0 - block_fraction
	pop("FIREWALL", Color(COL, 0.8), 1.2)
