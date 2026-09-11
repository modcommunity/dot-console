class_name DotConsoleLocal
extends DotConsoleSource

## The client's own commands and variables.
##
## Deliberately small. This is not a command system competing with a server's — it exists
## because a handful of things genuinely belong to the machine the player is sitting at,
## and must work with no server in the process: a volume, a sensitivity, a key bind, a
## screenshot, `quit`.
##
## [codeblock]
## local.add_command(&"screenshot", "Save a screenshot", func(args): ...)
## local.bind_setting(&"sensitivity", settings)   # reads and writes dot-settings
## [/codeblock]
##
## [b]It takes its variables from wherever they live rather than holding them.[/b]
## [method bind_setting] wires a name straight through to anything with
## [code]get_value[/code] and [code]set_value[/code] — dot-settings, in every deployment
## that has it — so there is one copy of a setting and not two that drift. A console that
## keeps its own copy of the volume is a console that shows the wrong volume.

## Something ran and produced output.
signal output(text: String, level: int)

const CHANNEL := "console"

var _commands: Dictionary = {}
var _vars: Dictionary = {}


## A command: a name, a help line and [code](args: PackedStringArray) -> Variant[/code].
##
## The callable may return a [DotResult], a [String], a [PackedStringArray] or nothing;
## all four are turned into output. Returning nothing is the common case and must not look
## like a failure.
func add_command(name: StringName, help: String, fn: Callable) -> DotConsoleLocal:
	_commands[String(name).to_lower()] = {"help": help, "fn": fn}
	return self


## A variable backed by a getter and a setter.
##
## [code]get_fn: () -> Variant[/code], [code]set_fn: (Variant) -> Variant[/code] where the
## return is a [DotResult] or anything.
func add_var(
	name: StringName, help: String, get_fn: Callable, set_fn: Callable = Callable()
) -> DotConsoleLocal:
	_vars[String(name).to_lower()] = {"help": help, "get": get_fn, "set": set_fn}
	return self


## Wires a name straight to a settings object, without naming its class.
##
## [param settings] is anything with [code]get_value(key)[/code] and
## [code]set_value(key, value)[/code] — dot-settings' manager, duck-typed, so this addon
## keeps its single dependency. Returns false when the object cannot answer, rather than
## registering a variable that errors the first time somebody types it.
func bind_setting(key: StringName, settings: Object, help: String = "") -> bool:
	if settings == null:
		return false
	if not settings.has_method("get_value") or not settings.has_method("set_value"):
		return false
	add_var(
		key,
		help if help != "" else "a game setting",
		func() -> Variant: return settings.call("get_value", key),
		func(v: Variant) -> Variant: return settings.call("set_value", key, v)
	)
	return true


func claims(name: String) -> bool:
	var n := name.to_lower()
	return _commands.has(n) or _vars.has(n)


func execute(line: String) -> DotResult:
	var parts := DotConsoleLine.split_line(line)
	if parts.is_empty():
		return DotResult.success("")
	var name := parts[0].to_lower()
	var args := parts.slice(1)

	if _vars.has(name):
		return _run_var(name, args)
	if not _commands.has(name):
		return DotResult.fail(DotError.CODE_INVALID, "unknown command '%s'" % name)

	var entry: Dictionary = _commands[name]
	var fn: Callable = entry["fn"]
	if not fn.is_valid():
		return DotResult.fail(DotError.CODE_STATE, "'%s' has nothing behind it" % name)

	var out: Variant = fn.call(PackedStringArray(args))
	if out is DotResult:
		return out
	if out == null:
		return DotResult.success("")
	return DotResult.success(out)


func _run_var(name: String, args: PackedStringArray) -> DotResult:
	var entry: Dictionary = _vars[name]
	var getter: Callable = entry["get"]
	if args.is_empty():
		var current: Variant = getter.call() if getter.is_valid() else null
		return DotResult.success('%s = "%s"' % [name, str(current)])

	var setter: Callable = entry["set"]
	if not setter.is_valid():
		return DotResult.fail(DotError.CODE_FORBIDDEN, "'%s' cannot be changed here" % name)

	var res: Variant = setter.call(" ".join(args) if args.size() > 1 else args[0])
	if res is DotResult and not (res as DotResult).ok:
		return res
	var now: Variant = getter.call() if getter.is_valid() else null
	return DotResult.success('%s = "%s"' % [name, str(now)])


func complete(partial: String, limit: int = 24) -> PackedStringArray:
	var out := PackedStringArray()
	var p := partial.to_lower()
	for n in names():
		if n.begins_with(p):
			out.append(n)
			if out.size() >= limit:
				break
	return out


func names() -> PackedStringArray:
	var out := PackedStringArray()
	for k in _commands.keys():
		out.append(String(k))
	for k in _vars.keys():
		out.append(String(k))
	out.sort()
	return out


func help_for(name: String) -> String:
	var n := name.to_lower()
	if _commands.has(n):
		return str((_commands[n] as Dictionary).get("help", ""))
	if _vars.has(n):
		return str((_vars[n] as Dictionary).get("help", ""))
	return ""


func source_name() -> String:
	return "local"
