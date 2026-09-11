class_name DotConsoleSource
extends RefCounted

## Something a console line can be sent to.
##
## [b]dot-console is a console, not a command system.[/b] That is the whole architectural
## decision and it is worth being blunt about, because the obvious alternative is to build
## a second command registry beside dot-server's — and dot-server already has `DotConsole`,
## `DotConCommand`, `DotConVar`, permissions, aliases, config execution and completion,
## all of which have been shipping for months.
##
## Two copies of a command system is this family's most repeated bug wearing its most
## convincing disguise. So: a source is anything that can take a line and answer, and this
## addon owns the key, the line editing, the history, the scrollback and the drawing.
##
## Three ship:
##
## - [DotConsoleLocal] — a small registry for the commands that genuinely are the client's:
##   a volume, a key bind, a screenshot. A client must be able to do those with no server
##   in the process at all.
## - [DotConsoleBridge] — wraps any object with [code]execute[/code] and
##   [code]complete[/code], which is dot-server's console exactly, reached by duck typing
##   so this addon never names it.
## - [DotConsoleRemote] — a [Callable] that puts the line on a wire, for RCON or for a
##   chat command. It cannot complete and says so rather than pretending.
##
## The manager asks each source in order and the first one that claims the name handles it.

## Whether this source has a command or cvar called [param name].
##
## Asked before [method execute] so an unknown name can be reported once, by the manager,
## rather than once per source. It is also what lets a local `volume` shadow a server's,
## which is the correct precedence: a client's own settings are the client's.
func claims(_name: String) -> bool:
	return false


## Runs one line. The line is already split into a name and arguments by the caller.
func execute(_line: String) -> DotResult:
	return DotResult.fail(DotError.CODE_UNSUPPORTED, "this source cannot execute")


## Completions for a partial line. Empty is a legitimate answer.
##
## [b]Must not block.[/b] It runs on the keystroke, and a source that asks a server what
## its commands are called is a source that freezes the game on every Tab. A remote source
## caches what it was told at connect time or answers nothing.
func complete(_partial: String, _limit: int = 24) -> PackedStringArray:
	return PackedStringArray()


## Every name this source knows, for help and for the manager's own completion.
func names() -> PackedStringArray:
	return PackedStringArray()


## One line of help for [param name], or the empty string.
func help_for(_name: String) -> String:
	return ""


func source_name() -> String:
	return "none"
