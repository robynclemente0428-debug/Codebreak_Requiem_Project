@tool
class_name EnemyMarker
extends DungeonMarker
## Spawns one specific enemy (a boss, a mini-boss, a guard) at an exact spot in the layout.
##
## To put a boss in the middle of a room: make the EnemyMarker a CHILD of the RoomMarker and
## leave its position at (0, 0, 0). If you move the room, the boss moves with it.
## You can also place it anywhere inside a room that another marker made.

## The enemy to spawn. Same resource type as the entries in the theme's enemy_pool.
@export var enemy: EnemyDefinition
## Rarity the enemy is rolled as. Champion enemies always drop loot.
@export_enum("normal", "magic", "rare", "champion") var rarity: String = "champion"
## The modifiers this enemy gets. Drag in EnemyModifierDefinition resources (data/enemy_modifiers).
@export var modifiers: Array[EnemyModifierDefinition] = []
## On: the enemy has exactly the modifiers above and nothing is rolled (an empty list means none).
## Off: yours are added on top of the random ones its rarity rolls.
@export var replace_random_modifiers: bool = false
## A quest key this enemy carries (an id from QuestItems, e.g. "brood_key"). It drops where
## the enemy dies, until the player has picked it up once. Empty = none.
@export var drops_key: String = ""
## On: no random enemies spawn in the room this marker sits in (a clean boss room).
@export var clear_room: bool = true
## On: this marker also makes its own room (Room Size). Off: it is only a spot inside a room
## that another marker made, which is what you want when nested under a RoomMarker.
@export var create_room: bool = false:
	set(v):
		create_room = v
		_refresh_preview()


func _marker_color() -> Color:
	return Color(1.0, 0.25, 0.30, 0.30)


## The preview box is one cell when the marker is only a spot, not a room.
func _footprint() -> Vector2i:
	return room_size if create_room else Vector2i.ONE
