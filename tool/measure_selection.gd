@tool
extends EditorScript
## Prints the real-world size (in metres) of whatever is selected in the Scene panel.
## Open this in the Script editor, select a node in the scene, then File > Run (Ctrl+Shift+X).
## Works on a character, a weapon scene root, a single mesh, anything with MeshInstance3D inside.

func _run() -> void:
	var selected := EditorInterface.get_selection().get_selected_nodes()
	if selected.is_empty():
		print("Select a node in the Scene panel first")
		return
	for node in selected:
		var box := _combined_aabb(node)
		if box.size == Vector3.ZERO:
			print("%s: no meshes found" % node.name)
			continue
		print("%s:  %.2f wide  x  %.2f tall  x  %.2f deep  (metres)   feet/bottom at y = %.2f" % [
			node.name, box.size.x, box.size.y, box.size.z, box.position.y])


## Bounding box of every mesh under `root`, in world space, so parent scales
## (like a rig scaled 1.88) are included in the answer.
func _combined_aabb(root: Node) -> AABB:
	var result := AABB()
	var first := true
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for m: MeshInstance3D in meshes:
		if m.mesh == null:
			continue
		var box: AABB = m.global_transform * m.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result
