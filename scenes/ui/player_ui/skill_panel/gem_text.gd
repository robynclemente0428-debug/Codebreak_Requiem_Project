class_name GemText
extends RefCounted
## Readable text for skill and support gems, used by the skills menu tooltips.

## Tooltip colours, shared by every panel that shows gem text.
const COL_TEXT := Color(0.85, 0.96, 1.0)
const COL_DIM := Color(0.55, 0.78, 0.85)
const COL_SKILL := Color(0.30, 0.95, 0.60)
const COL_SUPPORT := Color(0.45, 0.75, 1.0)

const STAT_LABELS := {
	StatTypes.Stat.SKILL_DAMAGE_MULT: "Skill Damage",
	StatTypes.Stat.MANA_COST: "Mana Cost",
	StatTypes.Stat.MIN_ATTACK_DAMAGE: "Attack Damage",
	StatTypes.Stat.MAX_ATTACK_DAMAGE: "Attack Damage",
	StatTypes.Stat.ATTACK_SPEED: "Attack Speed",
	StatTypes.Stat.CRIT_CHANCE: "Critical Strike Chance",
	StatTypes.Stat.CRIT_MULTIPLIER: "Critical Strike Multiplier",
}

## Short name for the key bound to an Input Map action, read from your actual Input Map.
static func key_label(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "?"
	for e in InputMap.action_get_events(action):
		if e is InputEventMouseButton:
			if e.button_index == MOUSE_BUTTON_LEFT:
				return "LMB"
			if e.button_index == MOUSE_BUTTON_RIGHT:
				return "RMB"
			if e.button_index == MOUSE_BUTTON_MIDDLE:
				return "MMB"
			return "MOUSE"
		if e is InputEventKey:
			return key_name(e)
	return "?"


## "W", "SPACE", "SHIFT+Q"... Physical keys are named after the player's keyboard layout,
## without Godot's " - Physical" suffix.
static func key_name(e: InputEventKey) -> String:
	var code := e.keycode
	if code == KEY_NONE and e.physical_keycode != KEY_NONE:
		code = DisplayServer.keyboard_get_keycode_from_physical(e.physical_keycode)
		if code == KEY_NONE:
			code = e.physical_keycode
	var text := OS.get_keycode_string(e.get_keycode_with_modifiers() & ~KEY_CODE_MASK | code) if code != KEY_NONE else ""
	if text == "":
		text = e.as_text().get_slice(" (", 0).get_slice(" - ", 0)
	return text.to_upper()


## Tooltip lines for a skill that sits in a socket: an array of [text, colour, font size].
## `action` is the hotkey it is bound to (or &"" if none), shown as the key name.
static func skill_tip(socket: SkillComponent.Socket, action: StringName) -> Array:
	if socket == null or socket.gem == null:
		return []
	var def := socket.gem.definition.skill_gem
	var parts: Array = [[socket.gem.get_display_name().to_upper(), COL_SKILL, 20]]
	var sub := "SKILL GEM"
	if action != &"":
		sub += "  //  KEY [%s]" % key_label(action)
	parts.append([sub, COL_DIM, 14])
	parts.append(["TAGS: " + tag_names(def.tags), COL_DIM, 13])
	if def.description != "":
		parts.append([def.description, COL_TEXT, 15])
	parts.append(["", COL_TEXT, 5])
	if socket.skill != null:
		for line in skill_lines(socket.skill):
			parts.append([line, COL_TEXT, 16])
	if not socket.supports.is_empty():
		parts.append(["", COL_TEXT, 5])
		parts.append(["SUPPORTS", COL_DIM, 14])
		for sup in socket.supports:
			parts.append([sup.get_display_name(), COL_SUPPORT, 15])
	return parts
	
## Tooltip lines for a gem ITEM that isn't socketed (backpack, picker): [text, colour, font size].
static func item_tip(item: ItemInstance, footer := "") -> Array:
	var def := item.definition
	var parts: Array = []
	if def.skill_gem != null:
		var gem := def.skill_gem
		parts = [
			[item.get_display_name().to_upper(), COL_SKILL, 20],
			["SKILL GEM", COL_DIM, 14],
			["TAGS: " + tag_names(gem.tags), COL_DIM, 13]]
		if gem.description != "":
			parts.append([gem.description, COL_TEXT, 15])
		parts.append(["", COL_TEXT, 5])
		for line in gem_lines(gem):
			parts.append([line, COL_TEXT, 16])
	elif def.support_gem != null:
		var sup := def.support_gem
		parts = [
			[item.get_display_name().to_upper(), COL_SUPPORT, 20],
			["SUPPORT GEM", COL_DIM, 14],
			["WORKS WITH: " + tag_names(sup.allowed_tags), COL_DIM, 13]]
		if sup.description != "":
			parts.append([sup.description, COL_TEXT, 15])
		parts.append(["", COL_TEXT, 5])
		for line in support_lines(sup):
			parts.append([line, COL_SUPPORT, 16])
	else:
		return []
	if footer != "":
		parts.append(["", COL_TEXT, 5])
		parts.append([footer, COL_DIM, 13])
	return parts

static func tag_names(tags: Array) -> String:
	var names := PackedStringArray()
	for t in tags:
		names.append(str(TagTypes.TagGem.find_key(t)).capitalize())
	return ", ".join(names)


static func num(v: float) -> String:
	return "%d" % roundi(v) if is_equal_approx(v, roundf(v)) else "%.1f" % v


## Lines for a skill that is socketed right now (includes its supports' effects).
static func skill_lines(skill: SkillInstance) -> Array[String]:
	var out: Array[String] = []
	out.append("Mana Cost: %s" % num(skill.get_mana_cost()))
	var effectiveness := apply_mods(skill.get_modifiers(), StatTypes.Stat.SKILL_DAMAGE_MULT, 1.0)
	out.append("Damage Effectiveness: %d%%" % roundi(effectiveness * 100.0))
	out.append_array(_base_flag_lines({
		"arc_angle": skill.get_flag("arc_angle"),
		"range": skill.get_flag("range"),
	}))
	return out


## (base + flat) * (1 + sum of percent add) * product of percent mult. Used by the tooltips.
static func apply_mods(mods: Array, stat: int, base_value: float) -> float:
	var flat := 0.0
	var add := 0.0
	var mult := 1.0
	var forced = null
	for m in mods:
		if m.stat != stat:
			continue
		match m.op:
			Modifier.ModOp.FLAT_ADD:
				flat += m.value
			Modifier.ModOp.PERCENT_ADD:
				add += m.value
			Modifier.ModOp.PERCENT_MULT:
				mult *= 1.0 + m.value
			Modifier.ModOp.OVERRIDE:
				forced = m.value
	if forced != null:
		return float(forced)
	return (base_value + flat) * (1.0 + add) * mult

## Lines for a skill gem that is NOT socketed yet (base values only).
static func gem_lines(def: SkillGemDefinition) -> Array[String]:
	var out: Array[String] = []
	out.append("Mana Cost: %s" % num(def.base_mana_cost))
	var effectiveness := apply_mods(def.stat_modifiers, StatTypes.Stat.SKILL_DAMAGE_MULT, 1.0)
	out.append("Damage Effectiveness: %d%%" % roundi(effectiveness * 100.0))
	out.append_array(_base_flag_lines(def.base_flags))
	return out


## What a support gem does, one line per effect.
static func support_lines(def: SupportGemDefinition) -> Array[String]:
	var out: Array[String] = []
	if def.mana_cost_increase != 0.0:
		out.append("%d%% %s Mana Cost" % [roundi(absf(def.mana_cost_increase) * 100.0),
			"more" if def.mana_cost_increase > 0.0 else "less"])
	for m in def.stat_modifiers:
		out.append(_mod_text(m))
	for key in def.flag_modifiers:
		out.append(_flag_text(str(key), float(def.flag_modifiers[key])))
	if def.animation_override != "":
		out.append("Uses the %s animation" % def.animation_override)
	return out


static func _mod_text(m: Modifier) -> String:
	var label: String = STAT_LABELS.get(m.stat, str(StatTypes.Stat.find_key(m.stat)).capitalize())
	var pct := "%d" % roundi(absf(m.value) * 100.0)
	match m.op:
		Modifier.ModOp.PERCENT_MULT:
			return "%s%% %s %s" % [pct, "more" if m.value >= 0.0 else "less", label]
		Modifier.ModOp.PERCENT_ADD:
			return "%s%% %s %s" % [pct, "increased" if m.value >= 0.0 else "reduced", label]
	return "%+.1f %s" % [m.value, label]


static func _flag_text(key: String, v: float) -> String:
	match key:
		"arc_angle":
			return "%+d° Arc" % roundi(v)
		"range":
			return "%+.1f Range" % v
	return "%s %+.1f" % [key.capitalize(), v]


static func _base_flag_lines(flags: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if float(flags.get("arc_angle", 0.0)) > 0.0:
		out.append("Arc: %d°" % roundi(flags["arc_angle"]))
	if float(flags.get("range", 0.0)) > 0.0:
		out.append("Range: %.1f" % float(flags["range"]))
	return out
