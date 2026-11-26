extends Node


var muted := false
signal happened(kind: String, target: String, amount: int)

func report(kind: String, target: String = "", amount: int = 1) -> void:
	if muted:
		return
	happened.emit(kind, target, amount)
