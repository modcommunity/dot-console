@tool
class_name DotConsoleConfig
extends DotConfig

## Everything about the console a player or an operator can change.
##
## A settings screen for it is free, because dot-ui generates one from any [DotConfig] —
## and the key binding in particular belongs in a settings screen rather than in an
## export, which is what [member open_action] is for.

@export_group("Opening it")

## The [InputMap] action that toggles the console, when the project defines one.
##
## Checked first. A game with a rebinder — dot-ui ships one — wants the console's key to
## be rebindable like every other, and an action is the only thing a rebinder can see.
@export var open_action: StringName = &"dot_console_toggle"

## The physical key used when no action is defined. Godot's [enum Key] values.
##
## [b]Physical, not the character.[/b] The console key is the one under Escape, and on a
## German keyboard that key produces `^`, on a French one `²`, and on a UK one `` ` ``.
## Binding the character means the console cannot be opened at all on most of Europe, and
## the player's only clue is that nothing happens. Binding the position gives everybody
## the same key in the same place.
@export var open_physical_key: int = KEY_QUOTELEFT

## A second key, for the keyboards where the first one is awkward. Zero for none.
@export var alternate_physical_key: int = 0

## Whether Escape closes it. On, and it does not also fall through to a pause menu.
@export var escape_closes: bool = true

@export_group("Behaviour")

## Lines of scrollback kept. Bounded on purpose; see [DotConsoleBuffer].
@export_range(16, 100000, 1) var scrollback_lines: int = 2048

## Lines of input history kept.
@export_range(4, 10000, 1) var history_lines: int = 128

## Chat prefixes a console line may start with, which are stripped before it runs.
##
## [b]The console has never needed one, and now it forgives one.[/b] The same commands are
## typable in both places — a server with `sv_chat_commands` on takes `/map surf_beginner`
## in the chat box — and the finger that learned the prefix there does not unlearn it on
## the way to the console. Without this, `/map` is an unknown command called "/map" and the
## suggester offers "map", which is a riddle rather than an answer.
##
## Only ever stripped from the FRONT of the whole line, and only when something follows it:
## a lone "/" stays as typed, and a statement separator never gains one. Empty the array
## for a console whose own commands start with a slash.
@export var chat_command_prefixes: PackedStringArray = PackedStringArray(["/", "!"])

## Whether to echo the line that was typed above its output.
##
## On: a console that shows output with no prompt is unreadable the moment two commands
## produce one line each. Secrets are redacted on the way in regardless — see
## [DotConsoleLine].
@export var echo_input: bool = true

## Whether to mirror everything [DotLog] emits into the scrollback.
##
## The single most useful thing a console does, and off by default anyway: a dedicated
## server at DEBUG produces more lines per second than a player can read, and a console
## that is a wall of noise is a console nobody opens. A game turns it on for the levels it
## wants.
@export var mirror_log: bool = false

## The lowest [DotLog] level mirrored when [member mirror_log] is on.
@export_enum("trace", "debug", "info", "warn", "error") var mirror_from: int = 2

## Whether the game keeps running while the console is open.
##
## On. Pausing is tempting and wrong: half of what a console is for is watching something
## while you change it, and a console that pauses cannot be used to debug movement, a
## match clock or anything else that only misbehaves while it runs.
@export var runs_while_open: bool = true

@export_group("Appearance")

## How much of the screen height the console covers, as a fraction.
@export_range(0.1, 1.0, 0.01) var height_fraction: float = 0.45

## Seconds the open and close animation takes. Zero snaps.
@export_range(0.0, 2.0, 0.01) var slide_seconds: float = 0.12

## Background opacity. Deliberately not fully opaque: seeing what the game is doing
## behind the console is half the point of having one.
@export_range(0.0, 1.0, 0.01) var background_opacity: float = 0.88

@export_range(6, 48, 1) var font_size: int = 14


func env_prefix() -> String:
	return "DOT_CONSOLE_"


func cli_prefix() -> String:
	return "--console-"


func validate() -> DotResult:
	if open_action == &"" and open_physical_key == 0:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"the console has no way to be opened",
			"set open_action, open_physical_key, or open it from code"
		)
	return DotResult.success(null)
