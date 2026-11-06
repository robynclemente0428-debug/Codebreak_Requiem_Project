extends Node
## A look at the Strategist exam's bay with its waves running. Run this scene from the editor (F6).
## Boots main.tscn with NO character slot loaded (nothing is saved), enters the exam, and sends
## each wave at the player in turn, `every` seconds apart. The player is kept alive. Writes how much
## each wave hurt the player to exam_tour_results.txt (gitignored), to show the samples can hit.

const MAIN := "res://scenes/map/main.tscn"
const YARD := "res://scenes/map/town/act_3_quarantine_yard.tscn"
const RESULTS := "res://tools/act3/exam_tour_results.txt"

@export var every := 12.0
## Where the player stands: near the rim, so the walls and a tank are in view.
@export var stand_at := Vector3(6.0, 0.1, -6.5)

var _hurt := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	var main: Node = load(MAIN).instantiate()
	for n in main.find_children("*", "", true, false):
		if n is AreaManager:
			n.start_area = YARD
	reparent(get_tree().root)
	var old := get_tree().current_scene
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	if old != null and old != self:
		old.queue_free()
	while not (_player() != null and _am() != null and _am().current_area != null and _am().can_go()):
		await get_tree().process_frame
	ExamChamber.enter(get_tree(), "strategist")
	while not (_am().current_area is ExamChamber and _am().can_go()):
		await get_tree().process_frame
	var chamber := _am().current_area as ExamChamber
	_player().global_position = chamber.to_global(stand_at)
	await get_tree().create_timer(every, true).timeout       # the bay, waiting
	(_player().get("health") as HealthComponent).damage_taken.connect(func(a: float) -> void: _hurt += a)
	chamber._reset_run()
	chamber._state = ExamChamber.State.RUNNING
	chamber._hud.show_run()
	var lines := PackedStringArray()
	for i in chamber.spec.wave_sizes.size():
		_hurt = 0.0
		for e in chamber._alive:
			if is_instance_valid(e):
				e.queue_free()
		chamber._alive.clear()
		chamber._next_wave()
		await get_tree().create_timer(every, true).timeout
		lines.append("wave %d %s: %d spawned, %.1f damage to the player" % [i + 1,
				chamber.spec.wave_name(i), chamber.spec.wave_sizes[i], _hurt])
	var f := FileAccess.open(RESULTS, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\nDONE\n")


func _process(_delta: float) -> void:
	if _player() != null:
		_player().get("health").heal(100000.0)


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("players") as Node3D


func _am() -> AreaManager:
	return get_tree().get_first_node_in_group("area_manager") as AreaManager
