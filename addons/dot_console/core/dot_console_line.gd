@tool
class_name DotConsoleLine
extends RefCounted

## Splitting a console line, and hiding the half of it that is a secret.
##
## Two jobs, in one place, because they are the same pass over the same string.

## Commands whose arguments must never appear in the scrollback.
##
## [b]A console that echoes what you typed puts your RCON password in the scrollback, in
## the log, and in the screenshot somebody posts to ask why the server will not start.[/b]
## This family already refuses secrets from the environment and argv for the same reason
## — [method DotConfig.sensitive_keys] — and a console is the third place a credential is
## typed, with the widest audience of the three.
##
## Matched on the command name, not on the argument, because a password does not look like
## anything.
const DEFAULT_SECRET_COMMANDS: Array[String] = [
	"rcon_password",
	"sv_password",
	"password",
	"connect_password",
	"login",
	"auth_token",
	"setpass",
]


## Splits a line into a command and its arguments, honouring double quotes.
##
## Quotes matter more here than anywhere else in this family: a chat command, a map name
## with a space in it and a `bind` whose second argument is itself a command all arrive
## through this one function.
static func split_line(line: String) -> PackedStringArray:
	var out := PackedStringArray()
	var current := ""
	var in_quotes := false
	var has_current := false

	for i in range(line.length()):
		var c := line[i]
		if c == '"':
			in_quotes = not in_quotes
			# An empty pair of quotes is a real, empty argument -- `bind x ""` clears a
			# binding -- so the flag has to be separate from the length of the buffer.
			has_current = true
			continue
		if (c == " " or c == "\t") and not in_quotes:
			if has_current:
				out.append(current)
				current = ""
				has_current = false
			continue
		current += c
		has_current = true

	if has_current:
		out.append(current)
	return out


## Splits a line into its statements on unquoted semicolons.
##
## `bind f "say hi; say bye"` is one bind whose argument contains a semicolon, and
## splitting on every semicolon is how that becomes two broken commands.
static func split_statements(line: String) -> PackedStringArray:
	var out := PackedStringArray()
	var current := ""
	var in_quotes := false
	for i in range(line.length()):
		var c := line[i]
		if c == '"':
			in_quotes = not in_quotes
		if c == ";" and not in_quotes:
			if not current.strip_edges().is_empty():
				out.append(current.strip_edges())
			current = ""
			continue
		current += c
	if not current.strip_edges().is_empty():
		out.append(current.strip_edges())
	return out


## The line as it is safe to show, log and screenshot.
##
## The command name survives, so a player can see that they typed it and a support person
## can see which command failed. Everything after it becomes asterisks of a fixed width,
## because the length of a password is information too.
##
## [b]Per statement, and wherever the command sits in it.[/b] Matching only the line's first
## word let `say hi; rcon_password hunter2` and `rcon rcon_password hunter2` (a remote
## source's prefix in front) through whole, into the echo and the history.
static func redact(line: String, secret_commands: Array[String] = DEFAULT_SECRET_COMMANDS) -> String:
	return _cut_secrets(line, secret_commands, " ********")


## The line as it is safe to keep in the history: [method redact] without the asterisks, so
## the Up arrow brings back the command and never a value (a recalled `********` would set it).
static func without_secrets(line: String, secret_commands: Array[String] = DEFAULT_SECRET_COMMANDS) -> String:
	return _cut_secrets(line, secret_commands, "")


## Whether [param line] carries something that must not be echoed: a statement in which a
## secret command is followed by anything.
static func is_secret(line: String, secret_commands: Array[String] = DEFAULT_SECRET_COMMANDS) -> bool:
	for statement in split_statements(line):
		if _secret_at(split_line(statement), secret_commands) >= 0:
			return true
	return false


## The index of the first secret command in [param parts] that has an argument after it, or -1.
static func _secret_at(parts: PackedStringArray, secret_commands: Array[String]) -> int:
	for i in range(parts.size() - 1):
		if secret_commands.has(parts[i].to_lower()):
			return i
	return -1


## [param line] unchanged when nothing in it is secret; otherwise rebuilt statement by
## statement, each secret one cut after its command name and [param mask] put in its place.
static func _cut_secrets(line: String, secret_commands: Array[String], mask: String) -> String:
	if not is_secret(line, secret_commands):
		return line
	var out := PackedStringArray()
	for statement in split_statements(line):
		var parts := split_line(statement)
		var at := _secret_at(parts, secret_commands)
		if at < 0:
			out.append(statement)
			continue
		var kept := PackedStringArray()
		for i in range(at + 1):
			kept.append('"%s"' % parts[i] if parts[i].contains(" ") or parts[i].is_empty() else parts[i])
		out.append(" ".join(kept) + mask)
	return "; ".join(out)
