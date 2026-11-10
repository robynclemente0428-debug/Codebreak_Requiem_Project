class_name EffectWarmup
extends RefCounted
## Pays the first-use cost of combat effects while the first area loads, with the screen dark,
## instead of in the first fight. The first time a shader is drawn it has to be compiled, and the
## first time a font size is drawn its glyphs have to be rasterized: a fight that shows them all
## at once (a rifle with pierce, forks and damage numbers) dropped to half the frame rate until
## each had been seen once. Compiled shaders and glyphs stay for the session, so this only runs
## for the first area. AreaManager calls it next to GlitchDeath.prewarm.
##
## Each effect is drawn once below the arrival point, under the floor: drawn, so compiled, but
## never seen. Damage numbers draw their digits nearly transparent (DamageNumbers.prewarm).

const BELOW := 2.0                         # metres under the arrival point

static var _done := false


static func run(area: Node3D, at: Vector3) -> void:
	if _done or area == null or not area.is_inside_tree():
		return
	_done = true
	var under := at + Vector3.DOWN * BELOW
	ShootTracers.prewarm(area, under)                                   # bullet tracers
	ShootTracers.spark(area, under, 0.5, Color(0, 0, 0, 0))             # hit rings + dust
	ImpactEffect.spawn(area, under, 0.5, Color(0, 0, 0, 0), Color(0, 0, 0, 0), false)   # Slam / Blast rings
	MuzzleFlash.spawn(area, under, Vector3.FORWARD)                     # the gun's flash
	SlashEffect.prewarm(area, under)                                    # Strike's slash
	var numbers := area.get_tree().get_first_node_in_group("damage_numbers")
	if numbers != null and numbers.has_method("prewarm"):
		numbers.prewarm()
