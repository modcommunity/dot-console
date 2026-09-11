class_name DotConsoleController
extends Node

## The console's whole behaviour, with no [Control] anywhere in it.
##
## [b]The split is what makes a headless suite possible.[/b] Same rule as dot-spectate's
## "computes a transform and touches no camera": the controller owns the sources, the
## scrollback, the history, the completion and the key, and [DotConsolePanel] draws
## whatever it says. A suite drives the controller directly and never opens a window.
##
## [codeblock]
## var console := DotConsoleController.new()
## console.add_source(local)                      # the client's own commands
## console.add_source(DotConsoleBridge.wrap(server_console))  # duck-typed, unnamed
## add_child(console)
## console.setup()
##
## console.submit("volume 0.4")
## [/codeblock]

const SERVICE := &"dot_console"
const CHANNEL := "console"

## The console opened or closed.
signal visibility_changed(open: bool)

## A line was added to the scrollback. What a panel redraws on.
signal line_appended(text: String, level: int)

## A line was submitted, after redaction. Cancellable by nobody — the hook is for a game
## that wants to log or forward it, not for one that wants to veto it.
signal submitted(line: String)

@export var config: DotConsoleConfig = null

@export var register_as_service: bool = true

## Whether this console may be opened at all.
##
## A shipped build usually wants it behind a flag or a developer entitlement. Off means
## the key does nothing and [method open] refuses — not that the key silently opens
## nothing, which is how a console ends up in a release build.
@export var enabled: bool = true

var buffer: DotConsoleBuffer = null

var _sources: Array[DotConsoleSource] = []
var _open := false
var _log_sink := Callable()


func _init() -> void:
	if config == null:
		config = DotConsoleConfig.new()
	buffer = DotConsoleBuffer.new()


func setup() -> DotResult:
	if config == null:
		config = DotConsoleConfig.new()
	var res := config.validate()
	if not res.ok:
		return res.wrap("console config")

	buffer.capacity = config.scrollback_lines
	buffer.history_capacity = config.history_lines

	if config.mirror_log:
		_attach_log_mirror()

	if register_as_service:
		DotRegistry.register(SERVICE, self)

	# Input is handled here rather than in the panel, and unhandled-input is deliberately
	# not used: the console has to open when a screen stack has swallowed input, because
	# "the interface is broken" is one of the things a console exists to investigate.
	set_process_input(true)
	return DotResult.success(null)


func _exit_tree() -> void:
	_detach_log_mirror()
	if register_as_service:
		DotRegistry.unregister_instance(SERVICE, self)


# --- Sources ----------------------------------------------------------------

## Adds a source. Order is precedence: the first that claims a name handles it.
##
## A local source added first shadows a server's command of the same name, which is the
## right way round — a client's own `volume` is the client's.
func add_source(source: DotConsoleSource) -> void:
	if source != null and not _sources.has(source):
		_sources.append(source)


func remove_source(source: DotConsoleSource) -> void:
	_sources.erase(source)


func sources() -> Array[DotConsoleSource]:
	return _sources.duplicate()


# --- Running a line ---------------------------------------------------------

## Runs a line, echoing and recording it.
##
## Statements separated by unquoted semicolons run in order and a failure does not stop
## the rest: `map dm_atrium; say hello` with a bad map name should still say hello, which
## is what every operator typing a setup line expects.
func submit(line: String) -> DotResult:
	var trimmed := line.strip_edges()
	if trimmed.is_empty():
		return DotResult.success("")

	# Redacted before anything sees it, including the history. A password in the history
	# comes back on the next Up arrow, in front of whoever is watching.
	var shown := DotConsoleLine.redact(trimmed)
	if config.echo_input:
		_append("] %s" % shown, DotConsoleBuffer.Level.ECHO)
	if DotConsoleLine.is_secret(trimmed):
		buffer.remember(DotConsoleLine.split_line(trimmed)[0])
	else:
		buffer.remember(trimmed)
	submitted.emit(shown)

	var last := DotResult.success("")
	for statement in DotConsoleLine.split_statements(trimmed):
		last = _run_one(statement)
		buffer.append_result(last)
	return last


func _run_one(statement: String) -> DotResult:
	var parts := DotConsoleLine.split_line(statement)
	if parts.is_empty():
		return DotResult.success("")
	var name := parts[0].to_lower()

	for s in _sources:
		if s.claims(name):
			return s.execute(statement)

	# Nothing claimed it. A suggestion is worth more than the refusal: a mistyped command
	# is the single most common thing that happens in a console.
	var near := _suggest(name)
	if near.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "unknown command '%s'" % name)
	return DotResult.fail(
		DotError.CODE_INVALID, "unknown command '%s'" % name, "did you mean: %s" % ", ".join(near)
	)


func _suggest(partial: String, limit: int = 3) -> PackedStringArray:
	var out := PackedStringArray()
	for n in all_names():
		if n.begins_with(partial.substr(0, maxi(1, partial.length() - 2))):
			out.append(n)
			if out.size() >= limit:
				break
	return out


# --- Completion -------------------------------------------------------------

## Completions for what is in the input box.
##
## Only the first word is completed. Completing an argument needs the source to know what
## the command's arguments mean, which dot-server's console does and a remote one cannot,
## so it is asked for rather than assumed: a source that has argument completion offers it
## through its own [method DotConsoleSource.complete].
func complete(partial: String, limit: int = 24) -> PackedStringArray:
	var seen := {}
	var out := PackedStringArray()
	for s in _sources:
		for c in s.complete(partial, limit):
			if seen.has(c):
				continue
			seen[c] = true
			out.append(c)
			if out.size() >= limit:
				return out
	return out


## The longest prefix every completion shares, for a Tab that fills in as far as it can.
##
## What a shell does, and its absence is why a homemade console makes you type the whole
## thing when there is only one match.
func common_prefix(candidates: PackedStringArray) -> String:
	if candidates.is_empty():
		return ""
	var prefix: String = candidates[0]
	for c in candidates:
		while not c.begins_with(prefix) and not prefix.is_empty():
			prefix = prefix.substr(0, prefix.length() - 1)
	return prefix


func all_names() -> PackedStringArray:
	var seen := {}
	var out := PackedStringArray()
	for s in _sources:
		for n in s.names():
			if not seen.has(n):
				seen[n] = true
				out.append(n)
	out.sort()
	return out


func help_for(name: String) -> String:
	for s in _sources:
		var h := s.help_for(name)
		if h != "":
			return h
	return ""


# --- Visibility -------------------------------------------------------------

func is_open() -> bool:
	return _open


func open() -> bool:
	if not enabled or _open:
		return false
	_open = true
	visibility_changed.emit(true)
	return true


func close() -> void:
	if not _open:
		return
	_open = false
	visibility_changed.emit(false)


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func _input(event: InputEvent) -> void:
	if not enabled:
		return

	# An action first, so a rebinder can move it. A project with no such action falls
	# through to the physical key, which is what an addon dropped into a project with no
	# InputMap entries has to do.
	if config.open_action != &"" and InputMap.has_action(config.open_action):
		if event.is_action_pressed(config.open_action):
			toggle()
			get_viewport().set_input_as_handled()
			return

	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return

	# physical_keycode, not keycode. The console key is the one under Escape, and the
	# character it produces is different on most of Europe -- binding the character means
	# the console cannot be opened at all there, with nothing to show for it.
	var physical := key.physical_keycode
	if physical == config.open_physical_key or (
		config.alternate_physical_key != 0 and physical == config.alternate_physical_key
	):
		toggle()
		get_viewport().set_input_as_handled()
		return

	if _open and config.escape_closes and physical == KEY_ESCAPE:
		close()
		# Handled, so it does not also open a pause menu behind the console.
		get_viewport().set_input_as_handled()


# --- Output -----------------------------------------------------------------

func print_line(text: String, level: DotConsoleBuffer.Level = DotConsoleBuffer.Level.INFO) -> void:
	_append(text, level)


func print_lines(
	lines: PackedStringArray, level: DotConsoleBuffer.Level = DotConsoleBuffer.Level.INFO
) -> void:
	for l in lines:
		_append(l, level)


func _append(text: String, level: DotConsoleBuffer.Level) -> void:
	buffer.append(text, level)
	line_appended.emit(text, int(level))


func _attach_log_mirror() -> void:
	if not _log_sink.is_valid():
		_log_sink = _on_log_record
		DotLog.add_sink(_log_sink)


func _detach_log_mirror() -> void:
	if _log_sink.is_valid():
		DotLog.remove_sink(_log_sink)
		_log_sink = Callable()


func _on_log_record(record: Dictionary) -> void:
	var level := int(record.get("level", 2))
	if level < config.mirror_from:
		return
	# Mapped rather than shared: DotLog's levels and the buffer's are two enums that
	# happen to line up today, and a console that colours an error as a trace because one
	# of them gained a level is the kind of coupling that is free to avoid.
	var mapped := DotConsoleBuffer.Level.INFO
	match level:
		0:
			mapped = DotConsoleBuffer.Level.TRACE
		1:
			mapped = DotConsoleBuffer.Level.DEBUG
		2:
			mapped = DotConsoleBuffer.Level.INFO
		3:
			mapped = DotConsoleBuffer.Level.WARN
		_:
			mapped = DotConsoleBuffer.Level.ERROR
	_append(DotLog.format_line(record), mapped)


# --- Reporting --------------------------------------------------------------

func describe() -> Dictionary:
	var names := PackedStringArray()
	for s in _sources:
		names.append(s.source_name())
	return {
		"open": _open,
		"enabled": enabled,
		"sources": Array(names),
		"commands": all_names().size(),
		"lines": buffer.line_count(),
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("dot-console  %s" % ("open" if _open else "closed"))
	out.append("  enabled  %s" % enabled)
	for s in _sources:
		out.append("  source   %-12s %d names" % [s.source_name(), s.names().size()])
	out.append_array(buffer.describe_lines())
	return out
