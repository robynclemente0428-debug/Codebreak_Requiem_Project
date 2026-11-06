class_name DeckOutages
extends Node
## What a downed deck system (DeckSystem) looks like on the convoy, so losing one is obvious
## at a glance and not just a toast. Put it in the convoy scene, as a child of the area.
##   POWER  the market row's hanging lamps (built over every vendor) go dark, and the vendors'
##          plates read NO POWER
##   CARGO  the hold is emptied: its props (Furniture/<cargo_prefix>*) are gone, a red warning
##          beacon turns over the empty hold, and a HOLD OPEN tag hangs there
##   COMMS  the route terminal's screen fills with static and reads NO SIGNAL
##          (RouteTerminal.set_signal), and the satellite dish sags off its mount
## Plus a badge at the top of the screen listing what's down while you're aboard (hidden during
## a hull breach, whose own HUD lists the systems). All three down: ConvoyBlackout takes over.
## Arriving with systems already down applies it all at once; patching one undoes its part.

## Hold props whose names start with this (under the area's Furniture) are the cargo.
@export var cargo_prefix := "Hold"
@export var lamp_color := Color(1.0, 0.78, 0.45)
@export var lamp_energy := 1.6
@export var lamp_height := 3.3

const FONT_PATH := "res://scenes/ui/font/Courier_Prime/CourierPrime-Bold.ttf"
const COL_DOWN := Color(1.0, 0.3, 0.25)
const SHORT := {"power": "POWER", "cargo": "CARGO", "comms": "COMMS", "iff": "IFF"}

var _systems: Dictionary = {}            # system_id -> DeckSystem
var _lamps: Array[Dictionary] = []       # {light, mat}
var _vendors: Array = []                 # [ShopNPC, its own info_title]
var _cargo: Array[Node3D] = []
var _hold_beacon: Node3D
var _hold_light: SpotLight3D
var _dish: Node3D
var _dish_basis := Basis.IDENTITY
var _badge_layer: CanvasLayer
var _badge: Label
var _t := 0.0


func _ready() -> void:
	add_to_group("deck_outages")
	_hook.call_deferred()


func _hook() -> void:
	var area := get_parent()
	for s in get_tree().get_nodes_in_group(DeckSystem.GROUP):
		if not area.is_ancestor_of(s):
			continue
		_systems[s.system_id] = s
		s.went_offline.connect(_refresh.unbind(1))
		s.repaired.connect(_refresh.unbind(1))
	_build_lamps(area)
	_find_cargo(area)
	_dish = area.get_node_or_null("Furniture/Dish") as Node3D
	if _dish != null:
		_dish_basis = _dish.basis
	_build_badge()
	_refresh()


func _exit_tree() -> void:
	if is_instance_valid(_badge_layer):
		_badge_layer.queue_free()


func _down(id: String) -> bool:
	var s = _systems.get(id)
	return s != null and is_instance_valid(s) and s.is_offline()


## Every system's look, from its state now.
func _refresh() -> void:
	_set_power(not _down("power"))
	_set_cargo(not _down("cargo"))
	_set_comms(not _down("comms"))
	_update_badge()


# ---------- POWER: the market row's lamps ----------
func _build_lamps(area: Node) -> void:
	var cable_mat := StandardMaterial3D.new()
	cable_mat.albedo_color = Color(0.05, 0.05, 0.06)
	for v in area.find_children("*", "ShopNPC", true, false):
		_vendors.append([v, v.info_title])
		var at: Vector3 = (v as Node3D).global_position + Vector3.UP * lamp_height
		var lamp := Node3D.new()
		lamp.name = "MarketLamp"
		add_child(lamp)
		lamp.global_position = at
		var cable := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.015
		cm.bottom_radius = 0.015
		cm.height = 1.2
		cm.material = cable_mat
		cable.mesh = cm
		cable.position.y = 0.7
		lamp.add_child(cable)
		var shade := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.08
		sm.bottom_radius = 0.26
		sm.height = 0.2
		sm.material = cable_mat
		shade.mesh = sm
		shade.position.y = 0.1
		lamp.add_child(shade)
		var bulb_mat := StandardMaterial3D.new()
		bulb_mat.emission_enabled = true
		bulb_mat.emission = lamp_color
		bulb_mat.albedo_color = lamp_color
		bulb_mat.emission_energy_multiplier = 3.0
		var bulb := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = 0.09
		bm.height = 0.18
		bm.material = bulb_mat
		bulb.mesh = bm
		lamp.add_child(bulb)
		var light := OmniLight3D.new()
		light.light_color = lamp_color
		light.light_energy = lamp_energy
		light.omni_range = 5.5
		light.position.y = -0.2
		lamp.add_child(light)
		_lamps.append({"light": light, "mat": bulb_mat, "on": true})


func _set_power(on: bool) -> void:
	for l in _lamps:
		if l["on"] == on:
			continue
		l["on"] = on
		(l["light"] as OmniLight3D).visible = on
		var mat := l["mat"] as StandardMaterial3D
		mat.emission_energy_multiplier = 3.0 if on else 0.0
		mat.albedo_color = lamp_color if on else Color(0.12, 0.11, 0.1)
	for pair in _vendors:
		if is_instance_valid(pair[0]):
			pair[0].info_title = pair[1] if on else "NO POWER"


# ---------- CARGO: the hold emptied ----------
func _find_cargo(area: Node) -> void:
	var furniture := area.get_node_or_null("Furniture")
	if furniture == null or cargo_prefix == "":
		return
	var centre := Vector3.ZERO
	for c in furniture.get_children():
		if c is Node3D and String(c.name).begins_with(cargo_prefix):
			_cargo.append(c)
			centre += (c as Node3D).global_position
	if _cargo.is_empty():
		return
	centre /= _cargo.size()
	# A red warning beacon turning over the hold, and a tag (only while it's open)
	_hold_beacon = Node3D.new()
	_hold_beacon.name = "HoldBeacon"
	add_child(_hold_beacon)
	_hold_beacon.global_position = centre + Vector3.UP * 3.0
	_hold_light = SpotLight3D.new()
	_hold_light.light_color = COL_DOWN
	_hold_light.light_energy = 6.0
	_hold_light.spot_range = 9.0
	_hold_light.spot_angle = 28.0
	_hold_light.rotation_degrees.x = -50.0
	_hold_beacon.add_child(_hold_light)
	var tag := _tag("HOLD OPEN  //  CARGO LOST", COL_DOWN)
	tag.position = Vector3.UP * 0.4
	_hold_beacon.add_child(tag)


func _set_cargo(kept: bool) -> void:
	for c in _cargo:
		if is_instance_valid(c):
			c.visible = kept
			# Off = out of the physics too (CollisionObject3D's disable_mode removes it)
			c.process_mode = Node.PROCESS_MODE_INHERIT if kept else Node.PROCESS_MODE_DISABLED
	if _hold_beacon != null:
		_hold_beacon.visible = not kept


# ---------- COMMS: no signal ----------
func _set_comms(ok: bool) -> void:
	for t in get_parent().find_children("*", "RouteTerminal", true, false):
		if t.signal_ok != ok:
			t.set_signal(ok)
	if _dish != null:
		# Knocked off its mount: tipped over and turned away
		_dish.basis = _dish_basis if ok else _dish_basis * Basis(Vector3.RIGHT, deg_to_rad(38.0)) * Basis(Vector3.UP, deg_to_rad(25.0))


# ---------- THE BADGE ----------
func _build_badge() -> void:
	_badge_layer = CanvasLayer.new()
	_badge_layer.layer = 19                    # under the HUD's panels (20)
	# On the game window, not in here: the convoy lives in the low-resolution 3D view, and UI
	# inside it is drawn blurred and too big (like DockDefense's HUD). Freed in _exit_tree.
	get_tree().root.add_child(_badge_layer)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.02, 0.02, 0.82)
	sb.border_color = COL_DOWN
	sb.set_border_width_all(1)
	sb.set_content_margin_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.offset_top = 14
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_layer.add_child(panel)
	_badge = Label.new()
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.add_theme_font_size_override("font_size", 15)
	_badge.add_theme_color_override("font_color", COL_DOWN)
	if ResourceLoader.exists(FONT_PATH):
		_badge.add_theme_font_override("font", load(FONT_PATH))
	panel.add_child(_badge)


func _update_badge() -> void:
	if _badge == null:
		return
	var down: Array[String] = []
	var targets := 0
	var targets_down := 0
	for id in ["power", "cargo", "comms", "iff"]:
		var s = _systems.get(id)
		if s != null and is_instance_valid(s) and s.sabotage_target:
			targets += 1
			if s.is_offline():
				targets_down += 1
		if _down(id):
			down.append(SHORT[id])
	var panel := _badge.get_parent() as Control
	panel.visible = not down.is_empty()
	if targets > 0 and targets_down == targets:
		_badge.text = "ALL SYSTEMS DOWN  //  DEAD IN THE VOID"
	else:
		_badge.text = "SYSTEMS DOWN: %s  //  PATCH THEIR CODE ON DECK" % "  ".join(down)
	panel.reset_size()


func _process(delta: float) -> void:
	_t += delta
	if _hold_beacon != null and _hold_beacon.visible:
		_hold_beacon.rotate_y(delta * 4.0)
	# A dead lamp now and then sparks back for a blink
	for l in _lamps:
		if not l["on"]:
			var mat := l["mat"] as StandardMaterial3D
			mat.emission_energy_multiplier = 2.0 if randf() < 0.004 else 0.0
	# The breach HUD lists the systems itself: no badge on top of it
	if _badge_layer != null:
		var breach := false
		for b in get_tree().get_nodes_in_group("hull_breach"):
			if b.has_method("is_running") and b.is_running():
				breach = true
		_badge_layer.visible = not breach


func _tag(text: String, col: Color) -> Label3D:
	var tag := Label3D.new()
	tag.text = text
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.pixel_size = 0.006
	tag.font_size = 36
	tag.outline_size = 10
	tag.modulate = col
	if ResourceLoader.exists(FONT_PATH):
		tag.font = load(FONT_PATH)
	return tag
