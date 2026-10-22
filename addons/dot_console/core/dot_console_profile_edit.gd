class_name DotConsoleProfileEdit
extends RefCounted

## The `profile_edit` command: live edits to dot-core's [DotProfileRuntime], from a console.
##
## Usage: `profile_edit set <kind> <id> <key> <value>`, `reset_key <kind> <id> <key>`,
## `reset <kind> <id>`, `save <kind> <id>`. The value is typed by its look (`400`, `2.5`, `true`,
## `[1,2]` as JSON), else the text. The command only builds the request; the server decides who may
## (the admin flags), so nothing is checked here.
##
## [codeblock]
## DotConsoleProfileEdit.register(local, link.submit)   # link: dot-net's DotNetProfileLink
## DotConsoleProfileEdit.print_replies(console, link)  # shows the server's answer
## [/codeblock]

const USAGE := "profile_edit set <kind> <id> <key> <value> | reset_key <kind> <id> <key> | reset <kind> <id> | save <kind> <id>"


## Adds `profile_edit` to [param local]. [param submit] is [code](req: Dictionary) ->
## DotResult[/code], a [code]DotProfileRuntime.handle_request[/code] on a server or a
## [code]DotNetProfileLink.submit[/code] on a client.
static func register(local: DotConsoleLocal, submit: Callable, name: StringName = &"profile_edit") -> void:
	local.add_command(name, "Edit a profile live (admin): " + USAGE, func(args: PackedStringArray) -> Variant:
		var req := parse(args)
		if not req.ok:
			return req
		var res: DotResult = submit.call(req.value)
		if not res.ok:
			return res
		return "sent" if typeof(res.value) == TYPE_BOOL else "ok")


## Shows the server's answer to a request sent by a client, as console lines.
static func print_replies(console: Object, link: Object) -> void:
	if link == null or not link.has_signal(&"reply"):
		return
	link.connect(&"reply", func(ok: bool, text: String) -> void:
		console.call(&"print_line", text if ok else "profile_edit refused: " + text))


## Arguments to a request, or CODE_INVALID with the usage.
static func parse(args: PackedStringArray) -> DotResult:
	var needs := {"set": 5, "reset_key": 4, "reset": 3, "save": 3}
	if args.is_empty() or not needs.has(args[0]) or args.size() < needs[args[0]]:
		return DotResult.fail(DotError.CODE_INVALID, "usage: " + USAGE)
	var key := args[3] if args[0] == "set" or args[0] == "reset_key" else ""
	var value: Variant = parse_value(" ".join(args.slice(4))) if args[0] == "set" else null
	return DotResult.success(DotProfileRuntime.make_request(args[0], args[1], args[2], key, value))


## `400` is an int, `2.5` a float, `true` a bool, `[..]`/`{..}` JSON, anything else the text.
static func parse_value(raw: String) -> Variant:
	if raw.is_valid_int():
		return raw.to_int()
	if raw.is_valid_float():
		return raw.to_float()
	if raw == "true" or raw == "false":
		return raw == "true"
	if raw.begins_with("[") or raw.begins_with("{"):
		var parsed: Variant = JSON.parse_string(raw)
		if parsed != null:
			return parsed
	return raw
