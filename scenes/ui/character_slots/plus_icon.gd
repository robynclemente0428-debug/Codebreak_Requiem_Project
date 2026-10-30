extends Control

@export var color := Color("#00E5FF")
@export var arm := 27.0
@export var thickness := 2.5

func _draw() -> void:
    var c := size / 2.0
    draw_line(c + Vector2(-arm, 0), c + Vector2(arm, 0), color, thickness, true)
    draw_line(c + Vector2(0, -arm), c + Vector2(0, arm), color, thickness, true)
