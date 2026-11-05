class_name ExamSpec
extends Resource
## One rank exam, sat in Examiner Sudo's sandbox (ExamChamber). The spec card shows the brief;
## the run sends waves of test processes at the player; the result is graded and debriefed.
## One file per rank in data/exams/<rank_id>.tres.
##
## Pass:  every wave cleared within time_limit, health never under fail_health, and a rule
##        using required_condition fired at least required_fires times (or, with
##        required_stop_loop, a self-stopping loop repeated that often).
## Grade: PASS / MERIT / DISTINCTION from points:
##        the script's efficiency tier (Lean 1, Elegant 2) + cleared within par_time (1)
##        + lost no more than par_damage of max health (1).   0-1 PASS, 2-3 MERIT, 4 DISTINCTION.

@export var rank_id: String = "operator"           # Ranks.LADDER name, lower case
@export var title: String = "OPERATOR EXAM"
## What the test asks for, one line each, shown on the spec card.
@export var brief: Array[String] = []
## A condition id (ProgramCondition.type_id()) the script must use, e.g. "enemies_nearby".
@export var required_condition: String = ""
@export var required_condition_label: String = "enemies_nearby()"
@export var required_fires: int = 3
## Instead of a condition: the script needs a loop that can stop itself (a while, or a for with
## break), and each of its repeats counts as a fire.
@export var required_stop_loop := false
## Perks the sandbox lends during this exam (Ranks.PERKS flag keys), so an exam can ask for what
## its own rank unlocks: the Architect exam lends "loops".
@export var lends: Array[String] = []

@export_group("Run")
@export var time_limit: float = 75.0
@export var par_time: float = 45.0
@export var par_damage: float = 0.30               # fraction of max health
@export var fail_health: float = 0.25              # the sandbox ends the run below this
@export var wave_enemy: EnemyDefinition
@export var wave_sizes: Array[int] = [4, 6, 8]
@export var enemy_level: int = 1
@export var spawn_radius: float = 8.5

## The quest event a first pass reports ("exam_passed", rank_id): the exam quest's objective.
const PASS_EVENT := "exam_passed"
const GRADES := ["PASS", "MERIT", "DISTINCTION"]


static func load_for(rank: String) -> ExamSpec:
	var path := "res://data/exams/%s.tres" % rank
	return load(path) as ExamSpec if ResourceLoader.exists(path) else null


## 0 PASS, 1 MERIT, 2 DISTINCTION.
static func grade_of(points: int) -> int:
	return 0 if points <= 1 else (1 if points <= 3 else 2)
