class_name DialogueParser
extends RefCounted
## Turns the text format into: { label: [ entries ] }
## Entry types: line, choice, jump, act.

static func parse(source: String) -> Dictionary:
	var nodes: Dictionary = {}
	var current: Array = []
	var speaker_re := RegEx.new()
	speaker_re.compile("^([A-Za-z0-9_ ]{1,24}):\\s+(.+)$")

	for raw in source.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue

		if line.begins_with("~"):
			current = []
			nodes[line.substr(1).strip_edges()] = current
			continue
		if nodes.is_empty():
			push_warning("Dialogue: text before the first '~ label' ignored: %s" % line)
			continue

		if line.begins_with("@"):
			var jp := line.substr(1).rsplit("->", true, 1)
			if jp.size() == 2:
				current.append({"t": "jump", "cond": jp[0].strip_edges(), "goto": jp[1].strip_edges()})
		elif line.begins_with("->"):
			current.append({"t": "jump", "cond": "", "goto": line.substr(2).strip_edges()})
		elif line.begins_with(">"):
			var words := line.substr(1).strip_edges().split(" ", false)
			if words.size() > 0:
				current.append({"t": "act", "name": words[0], "args": words.slice(1)})
		elif line.begins_with("*"):
			var body := line.substr(1).strip_edges()
			var cond := ""
			if body.begins_with("["):
				var end_br := body.find("]")
				if end_br > 0:
					cond = body.substr(1, end_br - 1).strip_edges()
					body = body.substr(end_br + 1).strip_edges()
			var target := "end"
			var cp := body.rsplit("->", true, 1)
			if cp.size() == 2:
				body = cp[0].strip_edges()
				target = cp[1].strip_edges()
			current.append({"t": "choice", "text": body, "cond": cond, "goto": target})
		else:
			var m := speaker_re.search(line)
			if m:
				current.append({"t": "line", "speaker": m.get_string(1).strip_edges(), "text": m.get_string(2)})
			else:
				current.append({"t": "line", "speaker": "", "text": line})
	return nodes
