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
## Story routing (quests count once started: active or done):
##   shown_after_quest  the portal doesn't exist for the player until then (hidden and inert):
##                      Hardfault's way onto the convoy waits for THE ROAD OUT
##   route_after_quest  from then on it leads to routed_area / routed_spawn instead: The Gate's
##                      exit goes on to the convoy rather than back to Hardfault
@export var shown_after_quest: String = ""
@export var route_after_quest: String = ""
@export_file("*.tscn") var routed_area: String = ""
@export var routed_spawn: StringName = &"default"

const SEALED_A := Color(1.0, 0.12, 0.15)
const SEALED_B := Color(1.0, 0.55, 0.45)

var _was_sealed := false
var _seal_check := 0.0
var _turned_back := 0.0          # seconds until the "sealed" message may show again
var _quest_check := 0.0
var _home_area := ""             # target_area / target_spawn before routing
var _home_spawn: StringName = &""


## True while the player doesn't have this portal's key.
func is_sealed() -> bool:
	if sealed_by_key == "":
		return false
	var player := get_tree().get_first_node_in_group("players")
	var qm = player.get("quests") if player != null else null
	if qm == null:
		return false
	return not (qm.has_recovered(sealed_by_key) or (open_after_quest != "" and qm.is_completed(open_after_quest)))


## True once the player has started this quest (it is active, or done).
static func quest_started(tree: SceneTree, quest_id: String) -> bool:
	var player := tree.get_first_node_in_group("players") if tree != null else null
	var qm = player.get("quests") if player != null else null
	return qm != null and (qm.is_active(quest_id) or qm.is_completed(quest_id))


## Copies the story routing from a PortalMarker's layout entry (DungeonLayoutReader).
func set_routing(d: Dictionary) -> void:
	shown_after_quest = str(d.get("shown_after_quest", ""))
	route_after_quest = str(d.get("route_after_quest", ""))
	routed_area = str(d.get("routed_area", ""))
	routed_spawn = StringName(str(d.get("routed_spawn", "default")))
	if is_inside_tree():
		_update_routing()


## Shows / hides the portal and points it where the story says (see shown_after_quest).
func _update_routing() -> void:
	if shown_after_quest != "":
		var shown := quest_started(get_tree(), shown_after_quest)
		visible = shown
		set_deferred("monitoring", shown)
	if route_after_quest != "" and routed_area != "":
		if _home_area == "":
			_home_area = target_area
			_home_spawn = target_spawn
		var routed := quest_started(get_tree(), route_after_quest)
		target_area = routed_area if routed else _home_area
		target_spawn = routed_spawn if routed else _home_spawn


func _process(delta: float) -> void:
	_turned_back = maxf(_turned_back - delta, 0.0)
	if shown_after_quest != "" or route_after_quest != "":
		_quest_check -= delta
		if _quest_check <= 0.0:
			_quest_check = 0.5                     # the quest can start while you stand here
			_update_routing()
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
	_update_routing()


func _on_body_entered(body: Node3D) -> void:
	if not body is Player or not visible:
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
