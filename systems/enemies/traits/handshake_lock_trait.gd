class_name HandshakeLock
extends PortLock
## HANDSHAKE: the boss's gate only opens to someone who answers its slam with a shield. When one
## of its own skills (the Gate Guard's slam) lands on a player whose scripted barrier or guard
## is up (the BARRIER / GUARD knobs, SkillBehavior._apply_defense), the port opens (see
## PortLock). Unshielded, the slam just hurts, and the boss says what was missing.
## Dodging every slam and swinging back, the old way, does nothing: the answer is a skill
## scripted to shield you, cast just before the slam lands.
##     "LOCKED // NO HANDSHAKE"         a hit on the closed port (now and then, not every hit)
##     "HANDSHAKE FAILED // NO SHIELD"  its slam hit you with no barrier or guard up
##     "HANDSHAKE OK // PORT OPEN"      its slam hit your shield

const LOCKED_GAP := 1.5                          # seconds between "LOCKED" pops


func modify_incoming(info: HitInfo) -> void:
	super(info)
	if info.absorbed:
		pop("LOCKED // NO HANDSHAKE", Color(COL_REJECT, 0.85), LOCKED_GAP)


func on_outgoing(info: HitInfo) -> void:
	if is_open() or not (info.target is Node) or not info.target.is_in_group("players"):
		return
	var hp := info.target.get("health") as HealthComponent
	if hp == null:
		return
	if hp.is_shielded():
		open_port("HANDSHAKE OK // PORT OPEN")
	else:
		fail("HANDSHAKE FAILED // NO SHIELD", COL_SHORT)
