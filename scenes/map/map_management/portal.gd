class_name Portal
extends Area3D
## A gate/portal/door trigger. Build it as a scene: Area3D (this script) +
## CollisionShape3D (box) + any visual mesh. Place it in an area and set the
## two exports below.

## Scene to load (must have a GameArea root).
@export_file("*.tscn") var target_area: String
## Which spawn marker/id to arrive at in that scene.
@export var target_spawn: StringName = &"default"
## Above 0, this portal leads into a dungeon instance of that level (see WorldState).
## Leave it at 0 for portals into towns and hand-built areas.
@export var dungeon_level: int = 0
## 0 = rejoin this dungeon's open instance (or open one), -1 = always a fresh instance,
## above 0 = that exact instance (for a gate screen that lists open dungeons).
@export var instance_id: int = 0
## A quest key that opens this portal (an id from QuestItems). Until the player has it, the
## portal glows red and turns them back with a message saying where the key is. Empty = open.
@export var sealed_by_key: String = ""
## Also open once this quest is done (saves from before the seal existed).
@export var open_after_quest: String = ""

const SEALED_A := Color(1.0, 0.12, 0.15)
const SEALED_B := Color(1.0, 0.55, 0.45)

var _was_sealed := false
var _seal_check := 0.0
var _turned_back := 0.0          # seconds until the "sealed" message may show again


## True while the player doesn't have this portal's key.
func is_sealed() -> bool:
	if sealed_by_key == "":
		return false
	var player := get_tree().get_first_node_in_group("players")
	var qm = player.get("quests") if player != null else null
	if qm == null:
		return false
	return not (qm.has_recovered(sealed_by_key) or (open_after_quest != "" and qm.is_completed(open_after_quest)))


func _process(delta: float) -> void:
	_turned_back = maxf(_turned_back - delta, 0.0)
	if sealed_by_key == "":
		return
	_seal_check -= delta
	if _seal_check > 0.0:
		return
	_seal_check = 0.5                          # the key can turn up at any moment
	var sealed := is_sealed()
	if sealed != _was_sealed:
		_was_sealed = sealed
		_show_seal(sealed)


## Red while sealed, the scene's own blue when open (the material is made unique first).
func _show_seal(sealed: bool) -> void:
	var mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	var mat := mesh.material_override as ShaderMaterial if mesh != null else null
	if mat == null:
		return
	if not has_meta(&"open_a"):
		mat = mat.duplicate()
		mesh.material_override = mat
		set_meta(&"open_a", mat.get_shader_parameter("color_a"))
		set_meta(&"open_b", mat.get_shader_parameter("color_b"))
	mat.set_shader_parameter("color_a", SEALED_A if sealed else get_meta(&"open_a"))
	mat.set_shader_parameter("color_b", SEALED_B if sealed else get_meta(&"open_b"))


func _ready() -> void:
	# The player is on physics layer 3 (value 4), see player.tscn.
	collision_layer = 5
	collision_mask = 3
	monitoring = true
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body is Player:
		return
	if is_sealed():
		if _turned_back <= 0.0:
			_turned_back = 2.5
			QuestItems.toast(get_tree(), "SEALED: NEEDS THE %s\n%s" % [QuestItems.name_of(sealed_by_key),
					QuestItems.hint_of(sealed_by_key)], SEALED_A)
		return
	var manager := get_tree().get_first_node_in_group("area_manager") as AreaManager
	if manager == null:
		push_error("Portal: no AreaManager found in the scene")
		return
	# Deferred: we are inside a physics callback, and the manager is about to
	# free the area that contains this very Area3D.
	manager.go_to.call_deferred(target_area, target_spawn, dungeon_level, instance_id)
