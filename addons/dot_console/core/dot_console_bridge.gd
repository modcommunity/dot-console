class_name DotConsoleBridge
extends DotConsoleSource

## Wraps anything that can already run a command line, without naming its class.
##
## [b]This is the file that stops dot-console being a second command system.[/b]
## dot-server's console has commands, cvars, permissions, aliases, config execution and
## argument completion, and has had them for months. Naming `DotConsole` here would make
## dot-server a hard dependency, which the family's rules forbid; re-implementing it would
## be two copies of one system, which is this family's most repeated bug.
##
## So: duck typing. Anything with [code]execute(line)[/code] is a target, anything that
## also has [code]complete(partial, limit)[/code] can complete, and anything with
## [code]command_names()[/code] / [code]cvar_names()[/code] can list. Each is probed once,
## at construction, and what is missing is simply not offered.
##
## [codeblock]
## var server_console := DotRegistry.get_service(&"dot_server")
## console.add_source(DotConsoleBridge.wrap(server_console.console))
## [/codeblock]

var _target: Object = null
var _label := "bridge"
var _can_execute := false
var _can_complete := false
var _name_methods: PackedStringArray = PackedStringArray()
var _cached_names: PackedStringArray = PackedStringArray()
var _names_fresh := false


static func wrap(target: Object, label: String = "") -> DotConsoleBridge:
	# Not this class's own name. A script that names itself in an expression, loaded after
	# its base, cuts Godot 4.7.2's exit teardown short and leaks every script loaded before
	# it. See docs/gdscript-hazards.md, "A script that names itself".
	var b := new()
	b._bind(target, label)
	return b


func _bind(target: Object, label: String) -> void:
	_target = target
	_label = label if label != "" else "bridge"
	if target == null:
		return
	_can_execute = target.has_method("execute")
	_can_complete = target.has_method("complete")
	for m in ["command_names", "cvar_names", "names"]:
		if target.has_method(m):
			_name_methods.append(m)


func valid() -> bool:
	# An object that has been freed is a real case here: a bridge outlives the server it
	# wrapped whenever a game changes. `is_instance_valid` is the check, and without it
	# the first command after a changelevel is a crash rather than a refusal.
	return _target != null and is_instance_valid(_target) and _can_execute


func claims(name: String) -> bool:
	if not valid():
		return false
	if _name_methods.is_empty():
		# It cannot tell us what it knows, so it claims everything and answers "unknown
		# command" itself. That is the right way round for a remote console: the server
		# is the authority on what the server has.
		return true
	return names().has(name.to_lower())


func execute(line: String) -> DotResult:
	if not valid():
		return DotResult.fail(
			DotError.CODE_STATE, "the console this was bridged to has gone away"
		)
	var out: Variant = _target.call("execute", line)
	if out is DotResult:
		return out
	if out == null:
		return DotResult.success("")
	return DotResult.success(out)


func complete(partial: String, limit: int = 24) -> PackedStringArray:
	if not valid():
		return PackedStringArray()
	if _can_complete:
		var out: Variant = _target.call("complete", partial, limit)
		if out is PackedStringArray:
			return out
		if out is Array:
			return PackedStringArray(out)
		return PackedStringArray()

	var result := PackedStringArray()
	for n in names():
		if n.begins_with(partial.to_lower()):
			result.append(n)
			if result.size() >= limit:
				break
	return result


func names() -> PackedStringArray:
	if _names_fresh:
		return _cached_names
	if not valid():
		return PackedStringArray()
	var out := PackedStringArray()
	for m in _name_methods:
		var got: Variant = _target.call(m)
		if got is PackedStringArray:
			out.append_array(got)
		elif got is Array:
			out.append_array(PackedStringArray(got))
	out.sort()
	_cached_names = out
	_names_fresh = true
	return out


## Forgets the cached name list.
##
## Called when the thing behind the bridge gains or loses commands — a module loading, a
## game changing. Cached in the first place because [method names] runs on every keystroke
## through [method claims], and asking a console with four hundred commands to rebuild and
## sort its list that often is measurable.
func invalidate() -> void:
	_names_fresh = false
	_cached_names = PackedStringArray()


func help_for(name: String) -> String:
	if not valid() or not _target.has_method("find_command"):
		return ""
	var cmd: Variant = _target.call("find_command", name)
	if cmd == null or not (cmd is Object):
		return ""
	var obj := cmd as Object
	if obj.has_method("describe_line"):
		return str(obj.call("describe_line"))
	return ""


func source_name() -> String:
	return _label
