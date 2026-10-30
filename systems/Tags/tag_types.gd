class_name TagTypes

## APPEND ONLY. .tres files store the integer, so never reorder or delete entries.
enum ItemTag {
	WEAPON, MELEE, RANGED, DAMAGE, ARMOUR, LIFE, SPEED, LIFE_ON_HIT,
	REGENERATION, MOVEMENT, ATTRIBUTES,
	MANA,
}
enum EnemyTag{
	MELEE, 
	RANGED, 
	DEFENSE, 
	SPEED,
	MOVEMENT,
	VAMPIRE, 
	REGENERATOR,
}
enum TagGem {
	STRIKE, 
	SLAM, 
	SPELL,
	SHOOT,
	# Describe what a skill DOES, so supports can target a kind of skill (append only):
	MELEE,
	AREA,
	PROJECTILE,
}
## Exclusivity groups: "which affixes can't coexist". A separate vocabulary from the tags above.
enum Group {
	WEAPON, MELEE, RANGED, DAMAGE, ARMOUR, 
	LIFE, SPEED, MOVEMENT, CRIT_CHANCE, CRIT_MULTIPLIER, LIFE_ON_HIT,
	MANA, SKILL_DAMAGE, STRENGTH, DEXTERITY, INTELLIGENCE, REGENERATION, MANA_REGEN,
	MANA_ON_HIT,
}

static func tag_name(tag: ItemTag) -> String:
	return str(ItemTag.find_key(tag)).to_lower()
	
static func group_name(group: Group) -> String:
	return str(Group.find_key(group)).to_lower()

static func name_of(e: Dictionary, value: int) -> String:
	return str(e.find_key(value)).to_lower()
# TagTypes.name_of(TagTypes.EnemyTag, tag)
