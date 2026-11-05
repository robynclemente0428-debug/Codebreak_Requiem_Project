class_name Modifier
extends Resource

enum ModOp {
	FLAT_ADD,
	PERCENT_ADD,
	PERCENT_MULT,
	OVERRIDE
}

@export var stat: StatTypes.Stat
@export var op: ModOp
@export var value: float
@export var source_id: String = ""
@export var tags: Array[String] = []
