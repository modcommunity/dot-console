# Design

## Why this is not a second command system

dot-server has `DotConsole`, `DotConCommand`, `DotConVar`, permissions, aliases, `exec`, completion and about nine hundred lines of built-in commands. Writing that again for the client would be two copies of one system, this family's most repeated bug. (The names also collide: `class_name` is global and `DotConsole` was taken.)

So the split is: **dot-server's console is the machine that decides; dot-console is the person typing.** One has permissions and no screen; the other has a key, a caret and no authority. `DotConsoleBridge` joins them by duck typing (`execute`, `complete`, `command_names`, `cvar_names`) so neither names the other. `DotConsoleLocal` is about ninety lines, for the client's own handful.

## Three things that are easy to get wrong

**The key is a position, not a character.** `open_physical_key` is `KEY_QUOTELEFT` as a **physical** keycode: the key under Escape, which produces `` ` `` on a UK layout, `^` on a German one, `²` on a French one and `@` on some Nordic ones. Binding the character makes the console unopenable across most of Europe, with no symptom. `open_action` is checked first so a rebinder can move it, and falls through to the physical key when the project defines no such action.

**Input is handled in `_input`, not `_unhandled_input`.** A console has to open when a screen stack has already swallowed input, because "the interface is stuck" is one of the things a console exists to investigate. For the same reason the panel does not use dot-ui: a console built on the thing being debugged is broken at the moment it is needed.

**A password typed into a console has been published.** `DotConsoleLine.redact` matches on the **command name**, because a password does not look like anything. It keeps the name (so the player and a support person can see which command it was) and replaces the arguments with a fixed number of asterisks, because length is information too. Redaction happens before the echo **and** before the history; an unredacted history puts the password back on screen on the next Up arrow. Same reasoning as `DotConfig.sensitive_keys()`.

## Decisions

- **A remote source cannot list commands on demand.** Asking a server on every Tab freezes the game on every Tab. `DotConsoleRemote.learn_names` is how a client that was told the list once (at signon, in a small message) teaches it; until then Tab offers nothing.
- **`DotConsoleBridge` caches its name list**: `claims()` runs on every keystroke. `invalidate()` is what a module load or a game change calls.
- **An unprefixed remote source claims everything, last.** Order is precedence; a remote source added last catches what nothing local claimed, which is right for a client whose console is the server's. `DotConsoleRemote.prefix` is for the other shape (only `rcon <line>` goes over the wire), because an unprefixed remote console has shut down dedicated servers with a `quit` meant for a client.
- **It does not pause the game** (`runs_while_open` defaults to true): half of what a console is for is watching something while you change it.
- **A statement that fails does not stop the ones after it**: `map dm_atrium; say hello` with a bad map still says hello, as dot-server's console does.
- **The suggester uses a bounded edit distance**, with a prefix match kept as a special case worth zero. The commonest typo (`mastervolume` for `master_volume`) shares no leading substring, so a prefix suggester was empty exactly when needed.
- **`DotConsoleBuffer.new(n)` holds exactly n lines** (floored at 1). A capacity that is not the number given reads as a bug in the ring.
- **Log mirroring is off by default** (`mirror_log`): a dedicated server at DEBUG produces more lines than a player can read.
- **No theme**: this ships a `StyleBoxFlat` built in code and nothing else, dot-ui's rule.

## Argument completion

The panel asks the sources once the input contains a space; a source with nothing to say answers with nothing and the box is left alone. dot-server's console (players, games) and dot-log (its subcommands and level names) answer. A remote source cannot, and offering command names in an argument position is worse than nothing.

- **`lstrip`, never `strip_edges`.** A trailing space is the difference between completing the command already typed and completing its first argument; `strip_edges()` makes `kick ` complete to `kick` for ever.
- **Candidates are whole lines**, because `_complete()` replaces the input box with the one it picked; an argument-only candidate would take the command word with it. The hint line strips the words every candidate agrees on, so three players read `Alice  Amber  Bob`.

The other half of this seam is dot-server's `DotConsole.complete()` delegating to `DotConCommand.completer`.
