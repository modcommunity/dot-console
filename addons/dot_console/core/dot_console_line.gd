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
static func redact(line: String, secret_commands: Array[String] = DEFAULT_SECRET_COMMANDS) -> String:
	var parts := split_line(line)
	if parts.size() < 2:
		return line
	if not secret_commands.has(parts[0].to_lower()):
		return line
	return "%s ********" % parts[0]


## Whether [param line] carries something that must not be echoed.
static func is_secret(line: String, secret_commands: Array[String] = DEFAULT_SECRET_COMMANDS) -> bool:
	var parts := split_line(line)
	return parts.size() >= 2 and secret_commands.has(parts[0].to_lower())
