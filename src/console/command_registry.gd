class_name CommandRegistry
extends RefCounted

var root: ConsoleCommand


func _init() -> void:
	root = ConsoleCommand.new()
	root.name = ""


func register(path: String, description: String, execute: Callable) -> ConsoleCommand:
	var parts := path.split(" ")
	var current := root
	for i in range(parts.size() - 1):
		var part := parts[i]
		if not current.subcommands.has(part):
			var cmd := ConsoleCommand.new()
			cmd.name = part
			current.subcommands[part] = cmd
		current = current.subcommands[part]
	var leaf_name := parts[-1]
	var leaf := ConsoleCommand.new()
	leaf.name = leaf_name
	leaf.description = description
	leaf.execute = execute
	current.subcommands[leaf_name] = leaf
	return leaf


func parse(input: String) -> Dictionary:
	var parts := input.strip_edges().split(" ", false)
	if parts.is_empty():
		return {"command": null, "args": [], "error": ""}

	var current := root
	var consumed := 0
	for i in range(parts.size()):
		var token := parts[i]
		if current.subcommands.has(token):
			current = current.subcommands[token]
			consumed += 1
		else:
			break

	if current.subcommands.is_empty():
		var remaining: Array[String] = []
		for j in range(consumed, parts.size()):
			remaining.append(parts[j])
		return {"command": current, "args": remaining, "error": ""}

	if consumed < parts.size():
		return {"command": null, "args": [], "error": "error: unknown command '" + input.strip_edges() + "'"}

	var available := ", ".join(current.subcommands.keys())
	return {"command": null, "args": [], "error": "incomplete: '" + input.strip_edges() + "' requires more arguments. Available: " + available}


func get_suggestions(input: String, cursor_pos: int) -> Array[String]:
	var before_cursor := input.substr(0, cursor_pos)
	var parts := before_cursor.split(" ", false)
	if parts.is_empty():
		return root.subcommands.keys()

	var current := root

	for i in range(parts.size()):
		var token := parts[i]
		if current.subcommands.has(token):
			current = current.subcommands[token]
		else:
			var matches: Array[String] = []
			for key in current.subcommands:
				if key.begins_with(token):
					matches.append(key)
			return matches

	return current.subcommands.keys()
