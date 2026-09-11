class_name DotConsoleRemote
extends DotConsoleSource

## A source that puts the line on a wire: RCON, a chat command, a module's own message.
##
## [codeblock]
## var remote := DotConsoleRemote.new()
## remote.send_fn = func(line: String) -> void: link.send_rcon(line)
## remote.prefix = "rcon"          # only `rcon <line>` goes this way
## console.add_source(remote)
## [/codeblock]
##
## [b]It is deliberately the least capable source.[/b] The answer comes back later, over a
## socket, into a handler that calls [method DotConsoleController.print_line] — so
## [method execute] returns "sent", not a result, and saying otherwise would be a lie the
## player reads as a command that did nothing.
##
## [b]And it cannot complete.[/b] A source that asks a server what its commands are called
## on every Tab is a source that freezes the game on every Tab; [method learn_names] is how
## a client that was told the list at connect time teaches this one, and until that
## happens Tab simply offers nothing.

## Where the line goes. [code](line: String) -> void[/code].
var send_fn: Callable = Callable()

## When set, only lines beginning with this word are sent, and the word is stripped.
##
## Empty means this source claims everything nothing else claimed, which is what a client
## whose console IS the server's console wants. A prefix is what a client with its own
## commands wants, so that `quit` quits the client rather than the server — an
## unprefixed remote console has shut down more than one dedicated server by accident.
var prefix: String = ""

var _known: PackedStringArray = PackedStringArray()
var _label := "remote"


func _init(p_label: String = "remote") -> void:
	_label = p_label


func claims(name: String) -> bool:
	if not send_fn.is_valid():
		return false
	if prefix != "":
		return name.to_lower() == prefix.to_lower()
	# Claims anything, last. The manager asks sources in order, so a local command still
	# wins -- which is the precedence that keeps `quit` local.
	return true


func execute(line: String) -> DotResult:
	if not send_fn.is_valid():
		return DotResult.fail(DotError.CODE_STATE, "nothing is connected to send this to")

	var payload := line
	if prefix != "":
		var parts := DotConsoleLine.split_line(line)
		if parts.size() < 2:
			return DotResult.fail(
				DotError.CODE_INVALID, "usage: %s <command>" % prefix
			)
		payload = line.substr(line.find(parts[1]))

	send_fn.call(payload)
	# No output. The answer arrives asynchronously and the game prints it; inventing a
	# success line here would put "ok" above a command that is about to be refused.
	return DotResult.success("")


## Teaches this source what the far end has, so Tab can offer something.
##
## Called by whatever handled the connection — a list of names is a small message a server
## can send once at signon, and asking for it per keystroke is the thing this avoids.
func learn_names(names_from_server: PackedStringArray) -> void:
	_known = names_from_server.duplicate()
	_known.sort()


func complete(partial: String, limit: int = 24) -> PackedStringArray:
	var out := PackedStringArray()
	var p := partial.to_lower()
	for n in _known:
		if n.begins_with(p):
			out.append(n)
			if out.size() >= limit:
				break
	return out


func names() -> PackedStringArray:
	return _known.duplicate()


func source_name() -> String:
	return _label
