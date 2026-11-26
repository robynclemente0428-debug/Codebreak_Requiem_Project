class_name Portal
extends Area3D

@export_file("*.tscn") var target_area: String
@export var target_spawn: StringName = &"default"
@export var dungeon_level: int = 0
@export var instance_id: int = 0
@export var sealed_by_key: String = ""
@export var open_after_quest: String = ""
@export var solid_while_sealed := false
@export var shown_after_quest: String = ""
@export var route_after_quest: String = ""
@export_file("*.tscn") var routed_area: String = ""
@export var routed_spawn: StringName = &"default"
@export var route_when_done := false
@export var routed_level: int = 0
@export var clears_stop: String = ""

const SEALED_A := Color(1.0, 0.12, 0.15)
const SEALED_B := Color(1.0, 0.55, 0.45)

var _was_sealed := false
var _seal_check := 0.0
var _turned_back := 0.0
var _quest_check := 0.0
var _home_area := ""
var _home_spawn: StringName = &""
var _home_level := 0
var _barrier: StaticBody3D


func is_sealed() -> bool:
	if sealed_by_key == "":
		return false
	var player := get_tree().get_first_node_in_group("players")
	var qm = player.get("quests") if player != null else null
	if qm == null:
		return false
	return not (qm.has_recovered(sealed_by_key) or (open_after_quest != "" and qm.is_completed(open_after_quest)))


static func quest_started(tree: SceneTree, quest_id: String) -> bool:
	var player := tree.get_first_node_in_group("players") if tree != null else null
	var qm = player.get("quests") if player != null else null
	return qm != null and (qm.is_active(quest_id) or qm.is_completed(quest_id))


static func quest_done(tree: SceneTree, quest_id: String) -> bool:
	var player := tree.get_first_node_in_group("players") if tree != null else null
	var qm = player.get("quests") if player != null else null
	return qm != null and qm.is_completed(quest_id)


func set_routing(d: Dictionary) -> void:
	shown_after_quest = str(d.get("shown_after_quest", ""))
	route_after_quest = str(d.get("route_after_quest", ""))
	routed_area = str(d.get("routed_area", ""))
	routed_spawn = StringName(str(d.get("routed_spawn", "default")))
	route_when_done = bool(d.get("route_when_done", false))
	routed_level = int(d.get("routed_level", 0))
	clears_stop = str(d.get("clears_stop", ""))
	if is_inside_tree():
		_update_routing()


func _update_routing() -> void:
	if shown_after_quest != "":
		var shown := quest_started(get_tree(), shown_after_quest)
		visible = shown
		set_deferred("monitoring", shown)
	if route_after_quest != "" and routed_area != "":
		if _home_area == "":
			_home_area = target_area
			_home_spawn = target_spawn
			_home_level = dungeon_level
		var routed := quest_done(get_tree(), route_after_quest) if route_when_done \
				else quest_started(get_tree(), route_after_quest)
		target_area = routed_area if routed else _home_area
		target_spawn = routed_spawn if routed else _home_spawn
		dungeon_level = routed_level if routed else _home_level


func _process(delta: float) -> void:
	_turned_back = maxf(_turned_back - delta, 0.0)
	if shown_after_quest != "" or route_after_quest != "":
		_quest_check -= delta
		if _quest_check <= 0.0:
			_quest_check = 0.5
			_update_routing()
	if sealed_by_key == "":
		return
	_seal_check -= delta
	if _seal_check > 0.0:
		return
	_seal_check = 0.5
	var sealed := is_sealed()
	if sealed != _was_sealed:
		_was_sealed = sealed
		_show_seal(sealed)
		if _barrier != null:
			_barrier.process_mode = Node.PROCESS_MODE_INHERIT if sealed else Node.PROCESS_MODE_DISABLED


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
	collision_layer = 5
	collision_mask = 3
	monitoring = true
	body_entered.connect(_on_body_entered)
	_update_routing()
	if solid_while_sealed:
		_build_barrier()


func _build_barrier() -> void:
	_barrier = StaticBody3D.new()
	_barrier.collision_layer = 1
	_barrier.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.3, 2.3, 2.0)
	shape.shape = box
	shape.position.y = 0.67
	_barrier.add_child(shape)
	_barrier.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_barrier)


func _on_body_entered(body: Node3D) -> void:
	if not body is Player or not visible:
		return
	if (body as Player).is_remote:
		return
	if is_sealed():
		if _turned_back <= 0.0:
			_turned_back = 2.5
			QuestItems.toast(get_tree(), "SEALED: %s\n%s" % [QuestItems.sealed_text(sealed_by_key),
					QuestItems.hint_of(sealed_by_key)], SEALED_A)
		return
	var manager := get_tree().get_first_node_in_group("area_manager") as AreaManager
	if manager == null:
		push_error("Portal: no AreaManager found in the scene")
		return
	if clears_stop != "" and manager.can_go():
		GameEvents.report(Waypoints.FINISH_DEED, clears_stop)
		for w in Waypoints.clear_stop(clears_stop):
			QuestItems.toast(get_tree(), "ROUTE UNLOCKED: %s" % w.display_name.to_upper(),
					Color(0.25, 1.0, 0.55))
		Coop.stop_cleared(clears_stop)
	manager.go_to.call_deferred(target_area, target_spawn, dungeon_level, instance_id)
