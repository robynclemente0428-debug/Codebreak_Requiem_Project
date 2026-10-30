class_name ForLoopSupport
extends RefCounted
## The For Loop gem. Loops (for / while / break) are core script blocks every skill has
## (see ProgramLoop); this gem only makes them better for the skill it is socketed with:
##   - the loop cap goes from 5 to 7 repeats per cast
##   - loop blocks cost 25% fewer points
##   - each repeat costs half the mana
## It has no script of its own: SkillProgramLimits reads these values when the gem is socketed.

const ID := "for_loop_support"
const CAP_BONUS := 2
const COST_MULT := 0.75
const MANA_MULT := 0.5
