class_name QuestDefinition
extends Resource

@export var id: String
@export var title: String = "NEW QUEST"
@export_multiline var description: String = ""
@export var objectives: Array[Objective] = []
@export var ordered: bool = false           # true = objectives must be done in sequence
@export var prerequisite_quest_ids: Array[String] = []

@export_group("Rewards")
@export var reward_credits: int = 0
@export var reward_items: Array[ItemDefinition] = []
## The player picks one support gem as a reward, from the ones that fit their class's starting
## skill (see QuestManager.support_choices). Takes one backpack slot.
@export var reward_support_choice: bool = false
@export var next_quest: QuestDefinition      # optional chain
