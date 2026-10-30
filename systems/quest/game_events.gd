extends Node

## One generic signal means a new event type never needs a new connection.
## kind examples: "kill", "equip", "enter_area", "talk", "pickup", "buy", "sell"
## target: a string id, e.g. "grunt_drone", "plasma_blade", "docks_gate", "vendor_01"

var muted := false
signal happened(kind: String, target: String, amount: int)

func report(kind: String, target: String = "", amount: int = 1) -> void:
	if muted:
		return
	happened.emit(kind, target, amount)
