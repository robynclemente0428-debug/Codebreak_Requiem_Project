class_name TutorialObjective
extends Objective
## A tutorial step that may already be done when the quest starts: the weapon is already
## equipped, a gem is already socketed, or a skill is already on the key. QuestManager.start()
## credits these, so BASIC TRAINING never waits for an action the player has no reason to repeat.


func already_met(player: Node) -> bool:
	match kind:
		"equip_slot":
			var eq: EquipmentComponent = player.get("equipment")
			return eq != null and eq.get_equipped(int(target)) != null
		"socket_skill":
			var skills: SkillComponent = player.get("skills")
			if skills == null:
				return false
			for s in skills.sockets:
				if s.gem != null:
					return true
		"bind_skill":
			var skills: SkillComponent = player.get("skills")
			return skills != null and skills.bindings.has(StringName(target))
	return false
