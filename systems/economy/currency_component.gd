class_name CurrencyComponent
extends Node

signal changed(amount: int)

@export var starting_amount: int = 100
var amount: int = 0

func _ready() -> void:
	amount = starting_amount            # a save load should call from_dict() AFTER this

func can_afford(cost: int) -> bool:
	return amount >= cost

func add(n: int) -> void:
	amount += maxi(n, 0)
	changed.emit(amount)

func spend(cost: int) -> bool:
	if cost < 0 or amount < cost:
		return false
	amount -= cost
	changed.emit(amount)
	return true

func to_dict() -> Dictionary:
	return {"amount": amount}

func from_dict(d: Dictionary) -> void:
	amount = int(d.get("amount", 0))
	changed.emit(amount)
