class_name ExamDebrief
extends RefCounted
## Examiner Sudo's debrief after an exam run, written from what actually happened (the result
## ExamChamber builds): how it ended, how often the rule fired against how often you cast, the
## script's tier, and which grade points were missed and by how much. Dry, patient, specific.


static func lines(spec: ExamSpec, r: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var cond := spec.required_condition_label
	var fires: int = r["fires"]
	var casts: int = r["casts"]

	# How it ended
	match r["fail"]:
		"TIME OUT":
			out.append("Out of time. Your script clears the room too slowly.")
		"PROCESS TERMINATED":
			out.append("I pulled you out before they did. A rule that fires earlier keeps them off you.")
		"SPEC NOT MET":
			out.append("Your rule fired %d times. I asked for %d. Let them crowd you, or lower the threshold." \
					% [fires, spec.required_fires])
		_:
			out.append(["Passed. Barely, but passed.", "Solid work.", "Flawless. Nothing wasted."][r["grade"]])

	# The rule against the casts
	if casts >= 4 and fires > 0:
		var share := float(fires) / casts
		if share < 0.25:
			out.append("%s fired on only %d of your %d casts. The threshold may be too high for a crowd this size." \
					% [cond, fires, casts])
		elif share > 0.9:
			out.append("%s fired on %d of %d casts. A rule that always fires isn't much of a condition. A higher threshold saves it for the real crowds." \
					% [cond, fires, casts])
		else:
			out.append("%s fired on %d of %d casts. That's a rule doing its job." % [cond, fires, casts])
	elif casts > 0 and fires == 0:
		out.append("You cast %d times and %s never fired once." % [casts, cond])

	# The script itself
	match r["tier"]:
		"elegant":
			out.append("Elegant script. Three blocks or fewer.")
		"lean":
			out.append("A lean script. Cut it to three blocks and I'll call it elegant.")
		_:
			out.append("It works, but it's long. Six blocks or fewer earns a tier, and a better grade.")

	# The points it missed
	if r["passed"]:
		if not r["fast"]:
			out.append("Clear it within %d seconds for the time point." % int(spec.par_time))
		if not r["unhurt"]:
			out.append("You lost %d%% of your health. Keep it under %d%% for the last point." \
					% [roundi(r["damage"] * 100.0), roundi(spec.par_damage * 100.0)])
	return out
