class_name QuestItems
extends RefCounted
## Every quest item and ward beacon: its name, and where to find it (shown when a sealed
## portal turns you back). The id is what RecoverObjective, EnemyMarker.drops_key,
## PortalMarker.sealed_by_key and DungeonPopulator.ward_beacon_id use.
## To add one: add an entry here, then use its id in those places.
##
## Entries with "item": true are real quest items: once picked up they sit in the inventory's
## QUEST ITEMS pouch (no backpack space, can't be dropped or sold) with "desc" and "opens" on
## their card, until every quest that asks for them is turned in (carried()).

const ITEMS := {
	# Keys: carried by a mini-boss (EnemyMarker.drops_key), open a sealed portal
	"brood_key": {"name": "BROOD KEY", "item": true,
		"hint": "The Enchanter in the Cache Warrens carries it.",
		"desc": "A cracked access shard, still warm. The Queen's brood answers to its signal.",
		"opens": "The Glitchling Nest"},
	"gate_key": {"name": "GATE KEY", "item": true,
		"hint": "The Enchanter at the Firewall Approach carries it.",
		"desc": "A heavy override key cut from the Firewall's own code.",
		"opens": "The Gate"},
	# Ward beacons: one per middle district (DungeonPopulator.ward_beacon_id)
	"beacon_spillway": {"name": "SPILLWAY BEACON"},
	"beacon_cache_warrens": {"name": "CACHE WARRENS BEACON"},
	"beacon_dead_sector": {"name": "DEAD SECTOR BEACON"},
	"beacon_relay_trench": {"name": "RELAY TRENCH BEACON"},
	"beacon_coolant_vaults": {"name": "COOLANT VAULTS BEACON"},
	"beacon_overclock_foundry": {"name": "FOUNDRY BEACON"},
	"beacon_firewall_approach": {"name": "FIREWALL BEACON"},
	# Events: done by holding a place (DockDefense), they open a portal like a key does.
	# "sealed" replaces "NEEDS THE <name>" on the sealed portal.
	"outpost_evacuated": {"name": "HARDFAULT EVACUATED", "sealed": "HARDFAULT IS STILL EVACUATING",
		"hint": "Hold the portal until everyone in Hardfault is through."},
	"dock_held": {"name": "DOCK HELD", "sealed": "THE CONVOY IS STILL LOADING",
		"hint": "Hold the dock until the convoy is loaded."},
	# THE LAST MILE (q04c): the guns breach, the IFF patch, and Checkpoint's gate
	"checkpoint_guns_held": {"name": "DECK HELD UNDER FIRE", "sealed": "THE NULL ARE ON THE DECK",
		"hint": "Hold the route terminal and clear the deck while Checkpoint's guns fire."},
	"iff_patched": {"name": "IFF TRANSPONDER PATCHED", "sealed": "CHECKPOINT'S GUNS ARE TRACKING US",
		"hint": "Patch the IFF Transponder on the convoy's deck."},
	"checkpoint_clearance": {"name": "CHECKPOINT CLEARANCE", "item": true,
		"hint": "The Perimeter Warden at Checkpoint's gate carries it.",
		"desc": "A Custodian gate credential, issued for a challenge answered in code. It says HARDFAULT: INBOUND.",
		"opens": "The Quarantine Yard"},
	"quarantine_lifted": {"name": "QUARANTINE LIFTED", "sealed": "THE YARD IS IN QUARANTINE",
		"hint": "The Registrar keeps Hardfault in the yard until the duplicate is resolved."},
}


static func name_of(id: String) -> String:
	return ITEMS.get(id, {}).get("name", id.replace("_", " ").to_upper())


## What a portal sealed by `id` says it needs ("NEEDS THE GATE KEY").
static func sealed_text(id: String) -> String:
	return ITEMS.get(id, {}).get("sealed", "NEEDS THE " + name_of(id))


static func hint_of(id: String) -> String:
	return ITEMS.get(id, {}).get("hint", "")


## A real item (a key), as opposed to a beacon or an event.
static func is_item(id: String) -> bool:
	return bool(ITEMS.get(id, {}).get("item", false))


static func desc_of(id: String) -> String:
	return ITEMS.get(id, {}).get("desc", "")


## The place this key unlocks, "" if none is named.
static func opens_of(id: String) -> String:
	return ITEMS.get(id, {}).get("opens", "")


## Quests that ask for this item (a recover objective with it as the target).
static func quests_using(qm: QuestManager, id: String) -> Array[QuestDefinition]:
	var out: Array[QuestDefinition] = []
	if qm == null:
		return out
	for def: QuestDefinition in qm.catalog.values():
		for o in def.objectives:
			if o != null and o.kind == "recover" and o.target == id:
				out.append(def)
				break
	return out


## The quest items in the pouch: picked up, and still needed by a quest that isn't turned in
## (picked up before its quest was taken counts too). One no quest asks for is kept.
static func carried(qm: QuestManager) -> PackedStringArray:
	var out := PackedStringArray()
	if qm == null:
		return out
	for id in qm.recovered:
		if not is_item(id):
			continue
		var users := quests_using(qm, id)
		if users.is_empty() or users.any(func(d: QuestDefinition) -> bool: return not qm.is_completed(d.id)):
			out.append(id)
	return out


## The player's QuestManager has it.
static func owned(tree: SceneTree, id: String) -> bool:
	var player := tree.get_first_node_in_group("players") if tree != null else null
	var qm = player.get("quests") if player != null else null
	return qm != null and qm.has_recovered(id)


## The quest tracker's toast, for messages about quest items.
static func toast(tree: SceneTree, text: String, colour := Color(1.0, 0.82, 0.30)) -> void:
	tree.call_group("quest_tracker", "show_toast", text, colour)
