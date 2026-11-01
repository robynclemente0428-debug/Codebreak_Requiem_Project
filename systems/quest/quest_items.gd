class_name QuestItems
extends RefCounted
## Every quest item and ward beacon: its name, and where to find it (shown when a sealed
## portal turns you back). The id is what RecoverObjective, EnemyMarker.drops_key,
## PortalMarker.sealed_by_key and DungeonPopulator.ward_beacon_id use.
## To add one: add an entry here, then use its id in those places.

const ITEMS := {
	# Keys: carried by a mini-boss (EnemyMarker.drops_key), open a sealed portal
	"brood_key": {"name": "BROOD KEY",
		"hint": "The Enchanter in the Cache Warrens carries it."},
	"gate_key": {"name": "GATE KEY",
		"hint": "The Enchanter at the Firewall Approach carries it."},
	# Ward beacons: one per middle district (DungeonPopulator.ward_beacon_id)
	"beacon_spillway": {"name": "SPILLWAY BEACON"},
	"beacon_cache_warrens": {"name": "CACHE WARRENS BEACON"},
	"beacon_dead_sector": {"name": "DEAD SECTOR BEACON"},
	"beacon_relay_trench": {"name": "RELAY TRENCH BEACON"},
	"beacon_coolant_vaults": {"name": "COOLANT VAULTS BEACON"},
	"beacon_overclock_foundry": {"name": "FOUNDRY BEACON"},
	"beacon_firewall_approach": {"name": "FIREWALL BEACON"},
}


static func name_of(id: String) -> String:
	return ITEMS.get(id, {}).get("name", id.replace("_", " ").to_upper())


static func hint_of(id: String) -> String:
	return ITEMS.get(id, {}).get("hint", "")


## The player's QuestManager has it.
static func owned(tree: SceneTree, id: String) -> bool:
	var player := tree.get_first_node_in_group("players") if tree != null else null
	var qm = player.get("quests") if player != null else null
	return qm != null and qm.has_recovered(id)


## The quest tracker's toast, for messages about quest items.
static func toast(tree: SceneTree, text: String, colour := Color(1.0, 0.82, 0.30)) -> void:
	tree.call_group("quest_tracker", "show_toast", text, colour)
