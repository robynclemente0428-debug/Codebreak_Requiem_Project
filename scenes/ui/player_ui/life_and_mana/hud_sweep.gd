class_name HudSweep
extends Control
## The slow bright line that sweeps down the life and mana bars (CRT look). It's its own
## control that only moves, so the bar under it doesn't have to redraw every frame for it.

var thickness := 5.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Puts the line where the sweep is at `time` inside a bar of `bar_size`, between the cut
## corners (`inset` from each side). Hidden while it's above or below the bar.
func follow(bar_size: Vector2, inset: float, scale_: float, time: float) -> void:
	thickness = 5.0 * scale_
	var y := fposmod(time * 40.0 * scale_, bar_size.y + 60.0 * scale_) - 30.0 * scale_
	visible = y > 2.0 and y < bar_size.y - 2.0
	if not visible:
		return
	var want := Vector2(maxf(bar_size.x - inset * 2.0, 0.0), thickness)
	if size != want:
		size = want
		queue_redraw()
	position = Vector2(inset, y - thickness * 0.5)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.08))
