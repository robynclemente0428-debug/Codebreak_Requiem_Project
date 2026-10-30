extends Node
## Run this scene (F6) to try the SCRIPTING tab without playing: it sockets Strike + Cleave
## and Slam into a test SkillComponent and opens the skills menu on the SCRIPTING tab.
## Drag blocks around, press APPLY, and watch the Output panel for the applied program.

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.1, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var skills := SkillComponent.new()
	add_child(skills)
	var inv := InventoryComponent.new()
	add_child(inv)
	skills.socket_skill(0, ItemInstance.make_gem(ItemDatabase.get_item("strike_gem")))
	skills.socket_support(0, ItemInstance.make_gem(ItemDatabase.get_item("cleave_gem")))
	skills.socket_support(0, ItemInstance.make_gem(ItemDatabase.get_item("explode_on_kill_gem")))
	skills.socket_skill(1, ItemInstance.make_gem(ItemDatabase.get_item("slam_gem")))
	skills.changed.connect(func() -> void:
		for i in 2:
			var p := skills.get_program(i)
			if p != null:
				print("Socket %d program:\n  %s" % [i, "\n  ".join(p.describe(skills.program_limits_for(i)))]))

	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := SkillPanel.new()
	layer.add_child(panel)
	panel.bind(skills, inv, null)
	await get_tree().process_frame
	panel.open()
	panel.show_tab("scripting")
