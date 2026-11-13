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
		"hint": "The Perimeter Warden at Checkpoint's gate carries it.", "carrier": "perimeter_warden",
		"desc": "A Custodian gate credential, issued for a challenge answered in code. It says HARDFAULT: INBOUND.",
		"opens": "The Quarantine Yard"},
	"quarantine_lifted": {"name": "QUARANTINE LIFTED", "sealed": "THE YARD IS IN QUARANTINE",
		"hint": "The Registrar keeps Hardfault in the yard until the duplicate is resolved."},
	# ACT III: boss drops, archive shards (ward beacons by another name), and Hex's copied stock
	"guild_shard": {"name": "GUILD DATA SHARD", "item": true,
		"hint": "It fell out of The Leak, in the Heap.",
		"desc": "A Compiler Guild expedition log, partly eaten. The Registrar can read it.",
		"opens": ""},
	"root_key": {"name": "ROOT KEY", "item": true,
		"hint": "The Collector carries it, in the Sweep.", "carrier": "the_collector",
		"desc": "C-0's credential. The Registrar isn't authorized to touch it, and neither, strictly, are you.",
		"opens": "The way out of the Sweep"},
	# (no portal is sealed by inward_gate now: the Sweep's exit routes on once Root Access is done)
	"inward_gate": {"name": "INWARD GATE", "sealed": "THE INWARD GATE IS SHUT: THE NULL ZONE LIES BEYOND",
		"hint": "Root Access opens it: bring the root key to the Registrar."},
	# ACT IV: the way to the Core, and the fragments of DECODE THE NULL
	"fray_road": {"name": "THE WAY INTO THE FRAY", "sealed": "THE FRAY IS SHUT: SUDO HASN'T RANKED YOU ENGINEER",
		"hint": "Pass Examiner Sudo's Engineer exam, here in The Threshold."},
	"core_road": {"name": "ROAD TO THE CORE", "sealed": "THE ROAD TO THE CORE IS SHUT",
		"hint": "Defeat Null Weaver Prime in the Weaver's Loom."},
	"core_key": {"name": "CORE KEY", "item": true, "sealed": "THE CORE IS SHUT",
		"hint": "The Null Gatekeeper carries it.", "carrier": "null_gatekeeper",
		"desc": "It isn't a credential. It's a question the Core asked itself, with the answer already filled in.",
		"opens": "The Core"},
	"null_fragment_a": {"name": "NULL FRAGMENT (FIRST)", "item": true,
		"hint": "A Null Weaver in The Fray carries it.",
		"desc": "It repeats. Every repeat is slightly shorter."},
	"null_fragment_b": {"name": "NULL FRAGMENT (SECOND)", "item": true,
		"hint": "A Null Weaver in The Fray carries it.",
		"desc": "The same phrase, in AXIOM's oldest syntax."},
	"null_fragment_c": {"name": "NULL FRAGMENT (THIRD)", "item": true,
		"hint": "A Null Weaver in The Fray carries it.",
		"desc": "A condition with nothing after it: when ... and ..."},
	"null_fragment_d": {"name": "NULL FRAGMENT (FOURTH)", "item": true,
		"hint": "A Null Weaver in The Fray carries it.",
		"desc": "A date. It is older than the Executors."},
	"null_fragment_e": {"name": "NULL FRAGMENT (FIFTH)", "item": true,
		"hint": "A Null Weaver in The Fray carries it.",
		"desc": "The end of a message, signed with no name."},
	# ACT V: the way down to The Kernel, and LAST WORDS's logs
	"stack_road": {"name": "THE WAY INTO THE STACK TRACE", "sealed": "THE STACK TRACE IS SHUT: SUDO HASN'T RANKED YOU DEFRAGMENTER",
		"hint": "Pass Examiner Sudo's Defragmenter exam, here in The Core."},
	"kernel_road": {"name": "THE WAY DOWN", "item": true, "sealed": "THE WAY DOWN IS SHUT: THE CORE SENTINEL STILL GUARDS IT",
		"hint": "Defeat the Core Sentinel, here in Sentinel's Hall.", "carrier": "core_sentinel",
		"desc": "The Sentinel's watch list, one line long: who may go further down. Your name is on it now.",
		"opens": "The Page File"},
	"swap_road": {"name": "THE WAY THROUGH THE SWAP", "item": true, "sealed": "THE SCHEDULER IS SHUT: THE WATCHDOG STILL GUARDS IT",
		"hint": "Defeat The Watchdog, here in The Page File.", "carrier": "watchdog",
		"desc": "The Watchdog's last heartbeat, still ticking. The Scheduler lets through whatever is still alive.",
		"opens": "The Scheduler"},
	"architect_log_a": {"name": "ARCHITECT LOG (FIRST)", "item": true,
		"hint": "A replayed raider in the Stack Trace carries it.",
		"desc": "Day one of the shutdown. They argued about the word 'shutdown' for most of it."},
	"architect_log_b": {"name": "ARCHITECT LOG (SECOND)", "item": true,
		"hint": "A replayed Loop Hound in the Stack Trace carries it.",
		"desc": "They left the Null running on purpose. Someone signed it. The name is erased."},
	"architect_log_c": {"name": "ARCHITECT LOG (THIRD)", "item": true,
		"hint": "A replayed Null Weaver in the Stack Trace carries it.",
		"desc": "Addressed to the first one to reach the Core. It says: we're sorry it's you."},
	# ACT IV side quests: THE GUILD EXPEDITION's logs and STATIC FROM HOME's relay packets
	"guild_log_a": {"name": "GUILD EXPEDITION LOG (DAY 1)", "item": true,
		"hint": "A rewritten Guildsman at The Expedition's End carries it.",
		"desc": "The expedition reaches the edge of the Null. Morale high. The examiner insists on grading the campsite."},
	"guild_log_b": {"name": "GUILD EXPEDITION LOG (DAY 9)", "item": true,
		"hint": "A rewritten Guildsman at The Expedition's End carries it.",
		"desc": "Three of us wrote the same sentence in our sleep. None of us knows the language it's in."},
	"guild_log_c": {"name": "GUILD EXPEDITION LOG (DAY 14)", "item": true,
		"hint": "A rewritten Guildsman at The Expedition's End carries it.",
		"desc": "The examiner has stopped sleeping. It says the Null is the best-written code it has ever audited."},
	"relay_packet_a": {"name": "RELAY PACKET (BRACK)", "item": true,
		"hint": "An Echo Wisp in The Echo Wells is carrying it.",
		"desc": "Brack's voice, clipped: convoy holding, everyone accounted for, come home when you can."},
	"relay_packet_b": {"name": "RELAY PACKET (HEX)", "item": true,
		"hint": "An Echo Wisp in The Echo Wells is carrying it.",
		"desc": "Hex, testing the relay. Then, quieter: don't make me sell your stuff."},
	"relay_packet_c": {"name": "RELAY PACKET (UNKNOWN)", "item": true,
		"hint": "An Echo Wisp in The Echo Wells is carrying it.",
		"desc": "It's Brack's voice and Hardfault's call sign. The words are in the Null's syntax."},
	"shard_registry": {"name": "REGISTRY SHARD"},
	"shard_heap": {"name": "HEAP SHARD"},
	"shard_mirror": {"name": "MIRROR DOCK SHARD"},
	"shard_dangling": {"name": "DANGLING QUARTER SHARD"},
	"copied_crate_a": {"name": "COPIED CRATE (SCRATCHED)", "item": true,
		"hint": "A Mirror Husk at Mirror Dock is carrying it.",
		"desc": "Hex's crate. Exactly Hex's crate. Same scratches, same price tags."},
	"copied_crate_b": {"name": "COPIED CRATE (DENTED)", "item": true,
		"hint": "A Mirror Husk at Mirror Dock is carrying it.",
		"desc": "Hex's crate. The dent is in the right place. That's the worrying part."},
	"copied_crate_c": {"name": "COPIED CRATE (RELABELLED)", "item": true,
		"hint": "A Mirror Husk at Mirror Dock is carrying it.",
		"desc": "Hex's crate, with Hex's handwriting on a label Hex never wrote."},
	"copied_crate_d": {"name": "COPIED CRATE (SEALED)", "item": true,
		"hint": "A Mirror Husk at Mirror Dock is carrying it.",
		"desc": "Hex's crate. It rattles the way Hex's crates rattle."},
}


static func name_of(id: String) -> String:
	return ITEMS.get(id, {}).get("name", id.replace("_", " ").to_upper())


## What a portal sealed by `id` says it needs ("NEEDS THE GATE KEY").
static func sealed_text(id: String) -> String:
	return ITEMS.get(id, {}).get("sealed", "NEEDS THE " + name_of(id))


static func hint_of(id: String) -> String:
	return ITEMS.get(id, {}).get("hint", "")


## The enemy id of the boss that carries this item, or "" (see "carrier" in ITEMS).
static func carrier_of(id: String) -> String:
	return ITEMS.get(id, {}).get("carrier", "")


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
