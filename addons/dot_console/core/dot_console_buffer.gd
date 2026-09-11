class_name DotConsoleBuffer
extends RefCounted

## The scrollback and the input history. Bounded, both of them.
##
## [b]An unbounded console buffer is a memory leak with a plausible name.[/b] A dedicated
## server logging a line per tick fills it in an afternoon, and the symptom is a process
## that grows until it is killed — with the console, the thing you would open to find out
## why, being the cause.
##
## So both are rings. `capacity` lines of scrollback, `history_capacity` lines of input,
## and the oldest goes when a new one arrives.

enum Level { TRACE, DEBUG, INFO, WARN, ERROR, ECHO }

const LEVEL_NAMES: Array[String] = ["trace", "debug", "info", "warn", "error", "echo"]

var capacity: int = 2048
var history_capacity: int = 128

var _lines: Array[Dictionary] = []
var _history: PackedStringArray = PackedStringArray()
var _history_cursor: int = -1
var _draft: String = ""


func _init(p_capacity: int = 2048, p_history: int = 128) -> void:
	# Floored at one rather than at some comfortable minimum. A caller that asks for eight
	# lines and silently gets sixteen has a console whose capacity is not what it says, and
	# the check that catches it reads as a bug in the ring.
	capacity = maxi(1, p_capacity)
	history_capacity = maxi(1, p_history)


# --- Scrollback -------------------------------------------------------------

func append(text: String, level: Level = Level.INFO) -> void:
	for one in text.split("\n"):
		_lines.append({
			"text": one,
			"level": int(level),
			"at": Time.get_ticks_msec(),
		})
	while _lines.size() > capacity:
		_lines.remove_at(0)


func append_lines(lines: PackedStringArray, level: Level = Level.INFO) -> void:
	for l in lines:
		append(l, level)


## Appends the outcome of a command, choosing the level from the result.
func append_result(res: DotResult) -> void:
	if res == null:
		return
	if not res.ok:
		append("%s: %s" % [res.code(), res.error.message], Level.ERROR)
		if res.error.detail != "":
			append("  %s" % res.error.detail, Level.ERROR)
		return
	var v: Variant = res.value_or(null)
	if v == null:
		return
	if v is PackedStringArray:
		append_lines(v, Level.INFO)
	elif v is Array:
		for item in v:
			append(str(item), Level.INFO)
	elif not DotValue.is_blank(v):
		append(str(v), Level.INFO)


func line_count() -> int:
	return _lines.size()


## The last [param count] lines at or above [param min_level].
##
## Filtering here rather than in a view: the view asks for what it can draw and gets it,
## so a console that is one line tall does not build two thousand labels.
func tail(count: int, min_level: Level = Level.TRACE, contains: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var needle := contains.to_lower()
	for i in range(_lines.size() - 1, -1, -1):
		var l := _lines[i]
		if int(l["level"]) < int(min_level):
			continue
		if needle != "" and not str(l["text"]).to_lower().contains(needle):
			continue
		out.push_front(l)
		if out.size() >= count:
			break
	return out


func clear() -> void:
	_lines.clear()


## Every line as plain text, for a bug report or a `condump`.
func to_text(min_level: Level = Level.TRACE) -> String:
	var out := PackedStringArray()
	for l in _lines:
		if int(l["level"]) >= int(min_level):
			out.append(str(l["text"]))
	return "\n".join(out)


# --- History ----------------------------------------------------------------

## Records a line the player submitted.
##
## [b]A repeat of the immediately previous line is not recorded.[/b] Pressing Up after
## running the same command three times should go back to the command before it, not
## three steps through one. Non-adjacent repeats are kept, because those are a real
## sequence somebody is cycling through.
func remember(line: String) -> void:
	var trimmed := line.strip_edges()
	if trimmed.is_empty():
		return
	if _history.size() > 0 and _history[_history.size() - 1] == trimmed:
		_reset_cursor()
		return
	_history.append(trimmed)
	while _history.size() > history_capacity:
		_history.remove_at(0)
	_reset_cursor()


## The previous entry, going back. [param draft] is what is in the box right now.
##
## The draft is kept so that walking all the way back down returns what the player was
## typing before they reached for the history — which is the behaviour of every shell, and
## its absence is the thing that makes a console feel homemade.
func previous(draft: String) -> String:
	if _history.is_empty():
		return draft
	if _history_cursor < 0:
		_draft = draft
		_history_cursor = _history.size() - 1
	else:
		_history_cursor = maxi(0, _history_cursor - 1)
	return _history[_history_cursor]


func next() -> String:
	if _history_cursor < 0:
		return _draft
	_history_cursor += 1
	if _history_cursor >= _history.size():
		# Read before resetting. _reset_cursor() clears the draft, so returning _draft
		# after calling it hands back the empty string -- and the symptom is a console
		# that eats what you were typing the moment you touch the arrow keys, which reads
		# as a focus bug rather than as an ordering one.
		var draft := _draft
		_reset_cursor()
		return draft
	return _history[_history_cursor]


func history() -> PackedStringArray:
	return _history.duplicate()


func _reset_cursor() -> void:
	_history_cursor = -1
	_draft = ""


func describe_lines() -> PackedStringArray:
	return PackedStringArray([
		"buffer: %d/%d lines, %d/%d history" % [
			_lines.size(), capacity, _history.size(), history_capacity
		],
	])
