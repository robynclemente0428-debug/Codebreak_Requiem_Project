class_name DeckSystem
extends Interactable
## One of the convoy's vital systems, standing on the deck where you can see it: what the Null
## go for in a HullBreach. Three of them, each keeping something working:
##   power   POWER JUNCTION   the market row's power: the deck's vendors trade
##   cargo   CARGO LOCK       the hold's seal: the breach's cargo bonus is paid
##   comms   COMMS RELAY      the convoy's signal: the route terminal can plot a course
## And one the Null leave alone (sabotage_target off), which only goes down in THE LAST MILE:
##   iff     IFF TRANSPONDER  answers a node's friend/foe challenge: Checkpoint's guns knock it
##                            out (GunsBreach), and patching it opens Checkpoint Approach
## During a breach some of the Null (saboteurs, picked by HullBreach) ignore you and head for a
## system. Each one standing at it drains its integrity; their swings take a chunk more. At 0 it
## goes OFFLINE: sparks, smoke, a dead core, and whatever it keeps working stops, for good,
## until you patch it: the Null corrupted its code, so walk up, interact, and fix the bug in the
## PATCH panel (patch_panel.gd: one small debugging puzzle per system). It costs no credits,
## only the thinking. Offline is saved (QuestManager.deeds "deck_down:<id>").
## Out of a breach a working system just hums; interacting says what it does.
##
## The integrity bar over it shows only while a breach is on. The Null hit it through
## `health.take_damage` (EnemyBase's swing), like they'd hit a player.

signal went_offline(system: DeckSystem)
signal repaired(system: DeckSystem)

enum Look { JUNCTION, CARGO, COMMS, TRANSPONDER }

## Which system: "power", "cargo", "comms" or "iff" (what RouteTerminal and ShopPanel ask about).
@export var system_id := "power"
@export var npc_name := "Power Junction"
@export var look := Look.JUNCTION
## Its letter on the minimap's diamond badge (MiniMap._paint_systems).
@export var map_glyph := "P"
## What it keeps working, shown on its plate and when inspected.
@export var keeps := "Powers the market row: the deck's vendors."
## What being offline costs, said when it goes down and when you try what it powers.
@export_multiline var offline_text := "The market row has no power. The vendors can't trade."
## Every boarder goes for the systems now (HullBreach.saboteur_every = 1): 3 at one take ~25-30 s.
@export var max_integrity := 300.0
## Integrity per second each saboteur at it takes (on top of their swings).
@export var drain_per_enemy := 2.0
## Integrity each swing at it takes (whatever the Null's damage: a system isn't armoured like you).
@export var hit_damage := 3.0
## Metres: a Null this close counts as at it.
@export var reach := 3.2
## Whether a breach's saboteurs go for it, and whether it counts for the blackout (every
## target down). Off for the IFF Transponder: only Checkpoint's guns take it down (knock_out).
@export var sabotage_target := true
## A QuestItems id recovered when its patch deploys ("" = none): the IFF's "iff_patched".
@export var recovers_on_repair := ""

const DEED_PREFIX := "deck_down:"
const PatchPanelScript := preload("res://scenes/map/town/convoy/patch_panel.gd")
## What the other scripts tell the player to do about an offline system.
const FIX_HINT := "Patch its code at the %s."
const GROUP := "deck_systems"
const COL_OK := Color(0.25, 0.95, 1.0)
const COL_HIT := Color(1.0, 0.55, 0.15)
const COL_DOWN := Color(1.0, 0.18, 0.2)
const COL_BAR_BACK := Color(0.05, 0.08, 0.1, 0.85)
## Its solid box for each Look (the housing), when the scene doesn't give it a Body.
const BODY_SIZES := [Vector3(1.4, 2.2, 0.7), Vector3(1.2, 1.1, 0.95), Vector3(1.0, 1.0, 0.75),
		Vector3(1.1, 1.0, 0.8)]
const BAR_WIDTH := 1.6
const BAR_HEIGHT := 0.14

var integrity := 300.0
## True while a breach is on: the bar shows, saboteurs drain it.
var contested := false
## Hit in the last moment and a half (the flicker, HullBreach's alert).
var under_attack := false
var health := _Hits.new()                         # what the Null's swings land on

var _offline := false
var _hit_flash := 0.0
var _attack_memory := 0.0
var _t := 0.0
var _core_mat: StandardMaterial3D
var _light: OmniLight3D
var _alarm: MeshInstance3D
var _alarm_mat: StandardMaterial3D
var _spin: Node3D                                 # a part that turns while it works
var _sparks: GPUParticles3D
var _smoke: GPUParticles3D
var _bar_root: Node3D
var _bar_fill: MeshInstance3D
var _bar_mat: StandardMaterial3D
var _label: Label3D


func _ready() -> void:
	super._ready()
	face_player = false
	add_to_group(GROUP)
	health.owner_system = self
	integrity = max_integrity
	prompt_text = "INSPECT"
	_build()
	_offline = is_down(get_tree(), system_id)
	_refresh()
	set_process(true)


## True when system `id` is offline (saved). False with no player loaded.
static func is_down(tree: SceneTree, id: String) -> bool:
	var qm := _quests(tree)
	return qm != null and int(qm.deeds.get(DEED_PREFIX + id, 0)) > 0


## The system of that id on this deck, or null.
static func find(tree: SceneTree, id: String) -> DeckSystem:
	for s in tree.get_nodes_in_group(GROUP):
		if (s as DeckSystem).system_id == id:
			return s
	return null


static func _quests(tree: SceneTree) -> QuestManager:
	var p := tree.get_first_node_in_group("players") if tree != null else null
	return p.get("quests") as QuestManager if p != null else null


func is_offline() -> bool:
	return _offline


func is_online() -> bool:
	return not _offline


## A breach starts (true) or ends (false). A working system starts it at full integrity.
func set_contested(on: bool) -> void:
	contested = on
	if on and not _offline:
		integrity = max_integrity
	under_attack = false
	_refresh()


## How many of `enemies` are at it now.
func attackers(enemies: Array) -> int:
	var n := 0
	for e in enemies:
		if is_instance_valid(e) and (e as Node3D).global_position.distance_to(global_position) <= reach:
			n += 1
	return n


## HullBreach calls this every frame of the fight with the Null on deck.
func drain(enemies: Array, delta: float) -> void:
	if _offline or not contested:
		return
	var n := attackers(enemies)
	if n > 0:
		_damage(drain_per_enemy * n * delta)


func _damage(amount: float) -> void:
	if _offline or not contested or amount <= 0.0:
		return
	integrity = maxf(integrity - amount, 0.0)
	_attack_memory = 1.5
	if integrity <= 0.0:
		_go_offline()


## Takes it straight offline, whatever its integrity (Checkpoint's guns hitting the IFF).
func knock_out() -> void:
	if not _offline:
		integrity = 0.0
		_go_offline()


func _go_offline() -> void:
	_offline = true
	var qm := _quests(get_tree())
	if qm != null:
		qm.deeds[DEED_PREFIX + system_id] = 1
	_refresh()
	went_offline.emit(self)


## The patch deployed (PatchPanel, once every test passes): back online.
func repair() -> void:
	if not _offline:
		return
	var qm := _quests(get_tree())
	if qm != null:
		qm.deeds.erase(DEED_PREFIX + system_id)
	_offline = false
	integrity = max_integrity
	_refresh()
	QuestItems.toast(get_tree(), "%s PATCHED  //  ONLINE\n%s" % [npc_name.to_upper(), keeps], COL_OK)
	if qm != null and recovers_on_repair != "":
		qm.recover(recovers_on_repair)
	repaired.emit(self)


## "Patch its code at the Power Junction." for toasts elsewhere.
func fix_hint() -> String:
	return FIX_HINT % npc_name


func interact(player: Node3D) -> void:
	if _offline:
		if contested:
			QuestItems.toast(get_tree(), "%s OFFLINE\nClear the deck first: they'd only wreck it again." % npc_name.to_upper(), COL_DOWN)
			return
		PatchPanelScript.open(self, player)
		return
	QuestItems.toast(get_tree(), "%s  //  ONLINE\n%s" % [npc_name.to_upper(), keeps], COL_OK)


func _process(delta: float) -> void:
	_t += delta
	_hit_flash = maxf(_hit_flash - delta * 4.0, 0.0)
	_attack_memory = maxf(_attack_memory - delta, 0.0)
	var was := under_attack
	under_attack = contested and not _offline and _attack_memory > 0.0
	if was != under_attack:
		_refresh()
	_animate(delta)


# ---------- LOOK ----------
func _animate(delta: float) -> void:
	if _offline:
		# A dying flicker: mostly dark, now and then a stutter of red
		var f := 1.0 if fposmod(_t * 7.3, 1.0) < 0.12 and fposmod(_t * 0.9, 1.0) < 0.5 else 0.0
		_core_mat.emission_energy_multiplier = 0.15 + f * 1.4
		_light.light_energy = 0.25 + f * 0.9
		_alarm_mat.emission_energy_multiplier = 3.0 if fposmod(_t, 1.0) < 0.5 else 0.3
	elif under_attack:
		var f := 0.5 + 0.5 * sin(_t * 18.0)
		_core_mat.emission_energy_multiplier = 1.2 + f * 2.0 + _hit_flash * 3.0
		_light.light_energy = 0.8 + f * 0.8
		_alarm_mat.emission_energy_multiplier = 3.0 if fposmod(_t * 3.0, 1.0) < 0.5 else 0.2
	else:
		var f := 0.5 + 0.5 * sin(_t * 2.0)
		_core_mat.emission_energy_multiplier = 1.6 + f * 0.8
		_light.light_energy = 0.7 + f * 0.25
	if _spin != null and not _offline:
		_spin.rotate_y(delta * (2.4 if under_attack else 0.8))
	if _bar_root.visible:
		var frac := clampf(integrity / maxf(max_integrity, 1.0), 0.0, 1.0)
		_bar_fill.scale.x = maxf(frac, 0.001)
		_bar_fill.position.x = -BAR_WIDTH * 0.5 * (1.0 - frac)
		_bar_mat.albedo_color = COL_OK.lerp(COL_DOWN, 1.0 - frac) if not under_attack \
				else COL_HIT.lerp(Color.WHITE, _hit_flash)
		_label.text = "%d%%" % ceili(frac * 100.0) if not _offline else "OFFLINE"


## Colours, particles, plate text and the bar for the state it's in now.
func _refresh() -> void:
	if _core_mat == null:
		return
	var col := COL_DOWN if _offline else (COL_HIT if under_attack else COL_OK)
	_core_mat.emission = col
	_core_mat.albedo_color = col.darkened(0.4)
	_light.light_color = col
	_alarm.visible = _offline or under_attack
	_sparks.emitting = _offline
	_smoke.emitting = _offline
	_bar_root.visible = contested
	_label.modulate = COL_DOWN if _offline else Color(0.85, 0.97, 1.0)
	if _offline:
		info_title = "OFFLINE  //  PATCH ITS CODE"
		prompt_text = "PATCH CODE"
	else:
		info_title = "ONLINE"
		prompt_text = "INSPECT"
	info_description = keeps + ("\nOFFLINE: " + offline_text if _offline else "")


func _build() -> void:
	var hull := StandardMaterial3D.new()
	hull.albedo_color = Color(0.11, 0.13, 0.16)
	hull.metallic = 0.7
	hull.roughness = 0.45
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.06, 0.08)
	dark.metallic = 0.5
	dark.roughness = 0.6
	_core_mat = StandardMaterial3D.new()
	_core_mat.emission_enabled = true
	_core_mat.emission = COL_OK
	_core_mat.albedo_color = COL_OK.darkened(0.4)
	_core_mat.emission_energy_multiplier = 2.0
	var top := 2.0                                    # height of the model (the light and bar go over it)
	match look:
		Look.JUNCTION:
			# A tall breaker cabinet: a housing, a glowing core column behind its grille, cable
			# runs into the deck, and a hazard-striped base.
			_box(Vector3(1.4, 2.2, 0.7), Vector3(0, 1.1, 0), hull)
			_box(Vector3(0.5, 1.5, 0.05), Vector3(0, 1.2, 0.36), dark)
			_cyl(0.16, 1.4, Vector3(0, 1.2, 0.3), _core_mat)
			for x in [-0.45, 0.45]:
				_box(Vector3(0.12, 1.7, 0.08), Vector3(x, 1.0, 0.38), _core_mat)
			for x in [-0.4, 0.0, 0.4]:
				_box(Vector3(0.16, 0.12, 1.4), Vector3(x, 0.06, -0.9), dark)        # cables into the deck
			_box(Vector3(1.5, 0.12, 0.8), Vector3(0, 0.06, 0), _hazard())
			top = 2.3
		Look.CARGO:
			# The hold's seal: a squat lock console with a spinning holographic crate over it,
			# and the seal ring it controls.
			_box(Vector3(1.2, 1.0, 0.8), Vector3(0, 0.5, 0), hull)
			_box(Vector3(1.0, 0.06, 0.6), Vector3(0, 1.03, 0), dark)
			var ring := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = 0.42
			torus.outer_radius = 0.52
			ring.mesh = torus
			ring.material_override = _core_mat
			ring.position = Vector3(0, 0.55, 0.42)
			ring.rotation.x = PI * 0.5
			add_child(ring)
			_spin = Node3D.new()
			_spin.position = Vector3(0, 1.55, 0)
			add_child(_spin)
			var holo := StandardMaterial3D.new()
			holo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			holo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			holo.albedo_color = Color(COL_OK, 0.35)
			var crate := MeshInstance3D.new()
			var cm := BoxMesh.new()
			cm.size = Vector3(0.5, 0.5, 0.5)
			crate.mesh = cm
			crate.material_override = holo
			_spin.add_child(crate)
			_box(Vector3(1.3, 0.1, 0.9), Vector3(0, 0.05, 0), _hazard())
			top = 2.0
		Look.COMMS:
			# A relay mast: a console at its foot, a tall pole, a turning cross-arm with emitters.
			_box(Vector3(1.0, 0.9, 0.7), Vector3(0, 0.45, 0), hull)
			_cyl(0.08, 3.0, Vector3(0, 1.5, -0.1), hull)
			_cyl(0.2, 0.3, Vector3(0, 0.95, -0.1), _core_mat)
			_spin = Node3D.new()
			_spin.position = Vector3(0, 2.9, -0.1)
			add_child(_spin)
			var arm := MeshInstance3D.new()
			var am := BoxMesh.new()
			am.size = Vector3(1.4, 0.08, 0.08)
			arm.mesh = am
			arm.material_override = hull
			_spin.add_child(arm)
			for x in [-0.7, 0.7]:
				var tip := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.09
				sm.height = 0.18
				tip.mesh = sm
				tip.material_override = _core_mat
				tip.position = Vector3(x, 0, 0)
				_spin.add_child(tip)
			_box(Vector3(1.1, 0.1, 0.8), Vector3(0, 0.05, 0), _hazard())
			top = 3.2
		Look.TRANSPONDER:
			# The friend/foe transponder: a squat console, a tilted answer dish on a turning head,
			# and a ring round the head that glows while it can answer a challenge.
			_box(Vector3(1.1, 1.0, 0.8), Vector3(0, 0.5, 0), hull)
			_box(Vector3(0.8, 0.3, 0.05), Vector3(0, 0.72, 0.41), dark)
			_box(Vector3(0.6, 0.06, 0.04), Vector3(0, 0.72, 0.44), _core_mat)
			_cyl(0.1, 0.5, Vector3(0, 1.25, 0), hull)
			_spin = Node3D.new()
			_spin.position = Vector3(0, 1.55, 0)
			add_child(_spin)
			var dish := MeshInstance3D.new()
			var dm := CylinderMesh.new()
			dm.top_radius = 0.55
			dm.bottom_radius = 0.12
			dm.height = 0.2
			dish.mesh = dm
			dish.material_override = hull
			dish.rotation.x = -0.9
			dish.position = Vector3(0, 0.1, 0.1)
			_spin.add_child(dish)
			var horn := MeshInstance3D.new()
			var hm := SphereMesh.new()
			hm.radius = 0.09
			hm.height = 0.18
			horn.mesh = hm
			horn.material_override = _core_mat
			horn.position = Vector3(0, 0.35, 0.42)
			_spin.add_child(horn)
			var halo := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = 0.42
			torus.outer_radius = 0.48
			halo.mesh = torus
			halo.material_override = _core_mat
			halo.position = Vector3(0, 1.05, 0)
			add_child(halo)
			_box(Vector3(1.2, 0.1, 0.9), Vector3(0, 0.05, 0), _hazard())
			top = 2.2
	prompt_height = top + 1.0                         # its name plate, over the integrity bar
	# The red alarm beacon on top (on while it's hit or down)
	_alarm_mat = StandardMaterial3D.new()
	_alarm_mat.emission_enabled = true
	_alarm_mat.emission = COL_DOWN
	_alarm_mat.albedo_color = COL_DOWN.darkened(0.3)
	_alarm = MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.1
	bm.height = 0.2
	_alarm.mesh = bm
	_alarm.material_override = _alarm_mat
	_alarm.position = Vector3(0.0, top + 0.08, 0.0) if look != Look.COMMS else Vector3(0.0, 3.1, -0.1)
	add_child(_alarm)
	_light = OmniLight3D.new()
	_light.omni_range = 4.5
	_light.light_color = COL_OK
	_light.position = Vector3(0, 1.4, 0.8)
	_light.shadow_enabled = false
	add_child(_light)
	_sparks = _particles(true)
	_sparks.position = Vector3(0, top * 0.6, 0.3)
	_smoke = _particles(false)
	_smoke.position = Vector3(0, top * 0.8, 0)
	# Where the player can use it from (InteractionShape), and its solid body (Body), so the Null
	# stand round it and the player can't walk through it. Both are in the scene, to see and
	# tweak them there (like RouteTerminal); one made in code only if the scene has none.
	collision_mask = 3
	if get_node_or_null("InteractionShape") == null:
		var reach_shape := CollisionShape3D.new()
		reach_shape.name = "InteractionShape"
		var sphere := SphereShape3D.new()
		sphere.radius = 2.2
		reach_shape.shape = sphere
		reach_shape.position = Vector3(0, 1.0, 0.6)
		add_child(reach_shape)
	if get_node_or_null("Body") == null:
		var body := StaticBody3D.new()
		body.name = "Body"
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = BODY_SIZES[look]
		shape.shape = bs
		shape.position.y = bs.size.y * 0.5
		body.add_child(shape)
		add_child(body)
	# The integrity bar and name over it, facing the camera (breaches only)
	_bar_root = Node3D.new()
	_bar_root.position = Vector3(0, top + 0.55, 0)
	add_child(_bar_root)
	var back := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(BAR_WIDTH + 0.06, BAR_HEIGHT + 0.06)
	back.mesh = bq
	back.material_override = _billboard(COL_BAR_BACK)
	_bar_root.add_child(back)
	_bar_fill = MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bar_fill.mesh = fq
	_bar_mat = _billboard(COL_OK)
	_bar_mat.render_priority = 1
	_bar_fill.material_override = _bar_mat
	_bar_root.add_child(_bar_fill)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.006
	_label.font_size = 40
	_label.outline_size = 10
	_label.position = Vector3(0, 0.22, 0)
	_label.render_priority = 2
	var font_path := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
	if ResourceLoader.exists(font_path):
		_label.font = load(font_path)
	_bar_root.add_child(_label)


func _box(size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat
	m.position = at
	add_child(m)
	return m


func _cyl(radius: float, height: float, at: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	m.mesh = c
	m.material_override = mat
	m.position = at
	add_child(m)
	return m


## Yellow and black, so the systems read as vital machinery from across the deck.
func _hazard() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.65, 0.1)
	m.emission_enabled = true
	m.emission = Color(0.85, 0.6, 0.05)
	m.emission_energy_multiplier = 0.4
	return m


func _billboard(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.albedo_color = col
	return m


## Sparks (fast orange flecks that fall) or smoke (slow dark puffs that rise), for OFFLINE.
func _particles(sparks: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	var mesh := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	if sparks:
		p.amount = 24
		p.lifetime = 0.6
		pm.direction = Vector3(0, 1, 0.4)
		pm.spread = 60.0
		pm.initial_velocity_min = 2.0
		pm.initial_velocity_max = 4.5
		pm.gravity = Vector3(0, -9.8, 0)
		pm.color = Color(1.0, 0.7, 0.25)
		mesh.size = Vector2(0.05, 0.05)
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	else:
		p.amount = 12
		p.lifetime = 2.4
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 15.0
		pm.initial_velocity_min = 0.6
		pm.initial_velocity_max = 1.1
		pm.gravity = Vector3(0, 0.2, 0)
		pm.scale_min = 1.0
		pm.scale_max = 2.0
		pm.color = Color(0.12, 0.12, 0.13, 0.55)
		mesh.size = Vector2(0.45, 0.45)
	mesh.material = mat
	p.draw_pass_1 = mesh
	p.process_material = pm
	p.emitting = false
	add_child(p)
	return p


## What the Null's swings land on (EnemyBase calls target.health.take_damage).
class _Hits extends RefCounted:
	var owner_system: DeckSystem
	var current_health := 1.0                       # (read by anything that checks for "dead")

	func take_damage(_amount: float, _ignore_armour := false) -> float:
		if owner_system == null or not is_instance_valid(owner_system):
			return 0.0
		owner_system._hit_flash = 1.0
		owner_system._damage(owner_system.hit_damage)
		return owner_system.hit_damage
