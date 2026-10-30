class_name StimRoller
extends RefCounted
## Rolls a stim item's numbers and modifiers. Everything a stim does is in item.stim_roll:
##   amount        restored per use
##   duration      seconds it's restored over (0 = instant)
##   max_charges   charges it can hold
##   per_use       charges one use costs
##   gain          multiplier on charges gained from kills
##   regen         charges gained per second on their own
## plus item.stim_mods (modifier ids, for the name and tooltip) and item.charges.
##
## Normal stims: just the base roll. Magic: one modifier. Rare: a prefix and a suffix.

## Charges each kill gives, by the enemy's rarity (times the stim's gain).
const CHARGES_PER_KILL := {"normal": 1.0, "magic": 2.0, "rare": 4.0, "champion": 6.0}

## id -> name, prefix?, what it changes, tooltip line
const MODS := {
	"potent":       {"name": "Potent",       "prefix": true,  "amount": 1.3,                 "text": "+30% amount restored"},
	"plentiful":    {"name": "Plentiful",    "prefix": true,  "max_charges": 1.4,            "text": "+40% maximum charges"},
	"efficient":    {"name": "Efficient",    "prefix": true,  "per_use": 0.7,                "text": "30% fewer charges per use"},
	"bubbling":     {"name": "Bubbling",     "prefix": true,  "instant": true, "amount": 0.75, "text": "Instant, but 25% less restored"},
	"of_haste":     {"name": "of Haste",     "prefix": false, "duration": 0.5,               "text": "Restores twice as fast"},
	"of_siphoning": {"name": "of Siphoning", "prefix": false, "gain": 1.6,                   "text": "+60% charges gained from kills"},
	"of_reserves":  {"name": "of Reserves",  "prefix": false, "regen": 0.25,                 "text": "Regains 1 charge every 4 seconds"},
	"of_the_medic": {"name": "of the Medic", "prefix": false, "amount": 1.15, "max_charges": 1.1, "text": "+15% amount restored, +10% maximum charges"},
}


static func roll(item: ItemInstance) -> void:
	var def: StimDefinition = item.definition.stim
	if def == null:
		return
	item.stim_mods.clear()
	var prefixes: Array = MODS.keys().filter(func(k): return MODS[k]["prefix"])
	var suffixes: Array = MODS.keys().filter(func(k): return not MODS[k]["prefix"])
	match item.rarity:
		"magic":
			var all: Array = prefixes + suffixes
			item.stim_mods.append(all[randi() % all.size()])
		"rare":
			item.stim_mods.append(prefixes[randi() % prefixes.size()])
			item.stim_mods.append(suffixes[randi() % suffixes.size()])
	var level_mult := 1.0 + def.amount_per_level * float(maxi(item.item_level, 1) - 1)
	item.stim_roll = {
		"base_amount": def.base_amount * level_mult * randf_range(def.amount_roll_min, def.amount_roll_max),
	}
	recompute(item)
	item.charges = int(item.stim_roll["max_charges"])          # new stims come full


## Works out the final numbers from the base roll and the modifiers (also after loading).
static func recompute(item: ItemInstance) -> void:
	var def: StimDefinition = item.definition.stim
	if def == null:
		return
	if not item.stim_roll.has("base_amount"):                 # starting gear: a plain base roll
		item.stim_roll["base_amount"] = def.base_amount * (1.0 + def.amount_per_level * float(maxi(item.item_level, 1) - 1))
	var amount: float = item.stim_roll["base_amount"]
	var duration := def.duration
	var max_c := float(def.max_charges)
	var per_use := float(def.charges_per_use)
	var gain := 1.0
	var regen := 0.0
	for id in item.stim_mods:
		var m: Dictionary = MODS.get(id, {})
		amount *= m.get("amount", 1.0)
		duration *= m.get("duration", 1.0)
		if m.get("instant", false):
			duration = 0.0
		max_c *= m.get("max_charges", 1.0)
		per_use *= m.get("per_use", 1.0)
		gain *= m.get("gain", 1.0)
		regen += m.get("regen", 0.0)
	item.stim_roll["amount"] = roundf(amount)
	item.stim_roll["duration"] = duration
	item.stim_roll["max_charges"] = maxi(roundi(max_c), 1)
	item.stim_roll["per_use"] = clampi(roundi(per_use), 1, maxi(roundi(max_c), 1))
	item.stim_roll["gain"] = gain
	item.stim_roll["regen"] = regen
	if item.charges < 0:
		item.charges = item.stim_roll["max_charges"]
	item.charges = mini(item.charges, item.stim_roll["max_charges"])


## Stim name with its modifiers: "Potent Health Stim of Haste".
static func display_name(item: ItemInstance) -> String:
	var pre := ""
	var suf := ""
	for id in item.stim_mods:
		var m: Dictionary = MODS.get(id, {})
		if m.get("prefix", false):
			pre = m["name"]
		else:
			suf = m["name"]
	var parts := PackedStringArray()
	for p in [pre, item.definition.display_name, suf]:
		if p != "":
			parts.append(p)
	return " ".join(parts)


## Tooltip lines: [text, is_modifier]
static func lines(item: ItemInstance) -> Array:
	if not item.stim_roll.has("amount"):
		recompute(item)                                       # starting gear made from a bare id
	var r := item.stim_roll
	var what := "life" if item.definition.stim.kind == StimDefinition.Kind.HEALTH else "mana"
	var out: Array = []
	if float(r.get("duration", 0.0)) <= 0.0:
		out.append(["Restores %d %s instantly" % [int(r["amount"]), what], false])
	else:
		out.append(["Restores %d %s over %.1f s" % [int(r["amount"]), what, float(r["duration"])], false])
	out.append(["Uses %d of %d charges" % [int(r["per_use"]), int(r["max_charges"])], false])
	out.append(["Currently %d charges" % item.charges, false])
	for id in item.stim_mods:
		out.append([MODS.get(id, {}).get("text", id), true])
	return out
