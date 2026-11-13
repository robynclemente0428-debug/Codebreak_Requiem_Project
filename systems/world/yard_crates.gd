class_name YardCrates
extends RefCounted
## Hardfault's cargo in the Quarantine Yard: six crates the Collector's sweeps come for (YardSweep).
## Each belongs to someone, and losing it changes something:
##   CargoA  HEX'S SPARE CELLS          Hex sells two fewer items (ShopNPC, every Hex)
##   CargoB  SUDO'S EXAM ARCHIVE        Sudo has lost every grade it ever wrote (dialogue)
##   CargoC  THE MEMORIAL BOARD         Hardfault's notes for the missing (Brack)
##   CargoD  BRACK'S CONVOY LOG         the convoy's whole road, written down (Brack)
##   CargoE  THE MED STORES             Act III towns refill stims only to half (TownArea)
##   CargoF  THE VALE FAMILY'S THINGS   everything one family carried out (the Registrar)
## A deleted crate isn't gone yet: it waits in C-0's deletion queue, in the Sweep, until the
## Collector falls (QueuedCrate, placed by DungeonPopulator.place_queued_crates). Walking into it
## there sends it back to the yard. Whatever is still queued when the Collector dies is burned.
## After Root Access, the Registrar reads the census: what Hardfault kept, lost and got back.
##
## Deeds (QuestManager.DEED_KINDS): sweep_lost:<crate> each time a sweep deletes it,
## crate_restored:<crate> each time it comes back from the queue, crate_mourned:<crate> once its
## owner has said so (dialogue: @ crate_news:CargoD).

const LOST := "sweep_lost"                       # YardSweep.LOST_DEED
const RESTORED := "crate_restored"
const MOURNED := "crate_mourned"
const COLLECTOR := "the_collector"
const COL := Color(1.0, 0.35, 0.25)

## In the order sweeps audit them.
const ORDER := ["CargoA", "CargoB", "CargoC", "CargoD", "CargoE", "CargoF"]
const CRATES := {
	"CargoA": {"name": "HEX'S SPARE CELLS", "said": "Hex's spare cells", "owner": "Hex",
		"loss": "Hex sells two fewer items", "shop": "hex", "slots": 2},
	"CargoB": {"name": "SUDO'S EXAM ARCHIVE", "said": "Sudo's exam archive", "owner": "Sudo",
		"loss": "every grade Sudo ever wrote"},
	"CargoC": {"name": "THE MEMORIAL BOARD", "said": "the memorial board", "owner": "Hardfault",
		"loss": "Hardfault's notes for the missing"},
	"CargoD": {"name": "BRACK'S CONVOY LOG", "said": "Brack's convoy log", "owner": "Brack",
		"loss": "the convoy's whole road, written down"},
	"CargoE": {"name": "THE MED STORES", "said": "the med stores", "owner": "Hardfault",
		"loss": "the yard refills stims only to half", "stims": 0.5},
	"CargoF": {"name": "THE VALE FAMILY'S THINGS", "said": "the Vale family's things", "owner": "the Vales",
		"loss": "everything one family carried out of Hardfault"},
}


static func is_crate(id: String) -> bool:
	return CRATES.has(id)


static func name_of(id: String) -> String:
	return str(CRATES.get(id, {}).get("name", id.to_upper()))


static func owner_of(id: String) -> String:
	return str(CRATES.get(id, {}).get("owner", "Hardfault"))


static func loss_of(id: String) -> String:
	return str(CRATES.get(id, {}).get("loss", ""))


## Deleted by a sweep and not (yet) brought back.
static func is_deleted(qm: QuestManager, id: String) -> bool:
	return qm != null and qm.deed_count(LOST, id) > qm.deed_count(RESTORED, id)


## Deleted, and still waiting in C-0's queue: it can be brought back from the Sweep.
static func is_queued(qm: QuestManager, id: String) -> bool:
	return is_deleted(qm, id) and not ScriptBudget.is_boss_killed(qm, COLLECTOR)


## Deleted, and the Collector fell with it still queued: gone for good.
static func is_burned(qm: QuestManager, id: String) -> bool:
	return is_deleted(qm, id) and ScriptBudget.is_boss_killed(qm, COLLECTOR)


## Brought back from the queue at least once, and in the yard now.
static func was_restored(qm: QuestManager, id: String) -> bool:
	return qm != null and qm.deed_count(RESTORED, id) > 0 and not is_deleted(qm, id)


## Deleted and still queued, and its owner hasn't said so yet (dialogue: @ crate_news:CargoD).
## The owners' lines point at the queue, so a crate that burned before they spoke is left to the
## census.
static func has_news(qm: QuestManager, id: String) -> bool:
	return is_queued(qm, id) and qm.deed_count(MOURNED, id) == 0


## The crates waiting in the queue now.
static func queued(qm: QuestManager) -> Array:
	return ORDER.filter(func(id: String) -> bool: return is_queued(qm, id))


## Stock slots a shop has lost with its owner's crate (Hex: two).
static func shop_slots_lost(qm: QuestManager, npc_id: String) -> int:
	var n := 0
	for id in ORDER:
		if str(CRATES[id].get("shop", "")) == npc_id and is_deleted(qm, id):
			n += int(CRATES[id].get("slots", 0))
	return n


## How full a town fills your stims on arrival (1 = all the way; the med stores lost: half).
static func stim_refill(qm: QuestManager) -> float:
	var share := 1.0
	for id in ORDER:
		if CRATES[id].has("stims") and is_deleted(qm, id):
			share = minf(share, float(CRATES[id]["stims"]))
	return share


## The crate the next sweep's audit goes for: the next one in ORDER still in the yard, by how many
## sweeps have run. "" when every crate is gone.
static func audit_target(qm: QuestManager, sweeps_done: int, present: Array) -> String:
	var kept: Array = ORDER.filter(func(id: String) -> bool: return id in present)
	if kept.is_empty():
		return ""
	return kept[posmod(sweeps_done, kept.size())]


## What the Registrar reads after Root Access: Hardfault's census.
static func census_lines(qm: QuestManager) -> PackedStringArray:
	var out := PackedStringArray()
	var ever_lost: Array = []
	var burned: Array = []
	var back: Array = []
	for id in ORDER:
		if qm != null and qm.deed_count(LOST, id) > 0:
			ever_lost.append(id)
		if is_deleted(qm, id):
			burned.append(id)
		elif was_restored(qm, id):
			back.append(id)
	out.append("Census. Hardfault, record two. Items registered on arrival: %d." % ORDER.size())
	if ever_lost.is_empty():
		out.append("Items deleted by C-0: none. I have checked twice. Hardfault kept everything it carried in.")
		return out
	out.append("Items deleted by C-0: %d." % ever_lost.size())
	if not back.is_empty():
		out.append("Restored from its deletion queue: %s." % _names(back))
	if burned.is_empty():
		out.append("Net loss: none. Correct.")
	else:
		out.append("Burned with the queue: %s." % _names(burned))
		out.append("Net loss: %d. I have entered them as Hardfault's, not as errors. It is the least a registry can do." % burned.size())
	return out


static func _names(ids: Array) -> String:
	return ", ".join(PackedStringArray(ids.map(func(id: String) -> String: return str(CRATES.get(id, {}).get("said", name_of(id))))))


static func qm_of(tree: SceneTree) -> QuestManager:
	var p := tree.get_first_node_in_group("players") if tree != null else null
	return p.get("quests") as QuestManager if p != null else null
