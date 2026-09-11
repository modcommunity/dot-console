# dot-console

The player's console: a key, a line, a history, and a bridge to whatever can run it.

**The distributable is `addons/dot_console/`.** It requires [dot-core](../dot-core), a separate repository, and nothing else — in particular not dot-server, which it bridges to by duck typing, and not dot-ui.

```bash
ln -s ../../dot-core/addons/dot_core addons/dot_core
```

## Why this is not a second command system

dot-server has `DotConsole`, `DotConCommand`, `DotConVar`, permissions, aliases, `exec`, completion and about nine hundred lines of built-in commands. The temptation here was to write that again for the client. **Two copies of one system is this family's most repeated bug**, and it has now happened to `setup.sh`, `tools/check.sh`, `tools/package_check.sh`, both bootstrap scripts and a vendoring list.

The names also collide outright: `class_name` is global in Godot and these install side by side, so `DotConsole` was taken before this addon existed. That is a symptom, not the reason — but it is a good one.

So the split is: **dot-server's console is the machine that decides; dot-console is the person typing.** One has permissions and no screen; the other has a key, a caret and no authority at all. `DotConsoleBridge` joins them by duck typing (`execute`, `complete`, `command_names`, `cvar_names`) so neither names the other.

## The three things that are easy to get wrong

### 1. The key is a position, not a character

`open_physical_key` is `KEY_QUOTELEFT` as a **physical** keycode. The console key is the one under Escape; it produces `` ` `` on a UK layout, `^` on a German one, `²` on a French one and `@` on some Nordic ones. Binding the character means the console cannot be opened across most of Europe and nothing at all happens when the player presses it — a bug with no symptom, reported as "the console does not work on my machine".

`open_action` is checked first so dot-ui's rebinder can move it, and falls through to the physical key when the project defines no such action, which is what an addon dropped into a project with no `InputMap` entries has to do.

### 2. Input is handled in `_input`, not `_unhandled_input`

Deliberate, and the opposite of what a well-behaved node does. A console has to open **when a screen stack has already swallowed input**, because "the interface is stuck" is one of the things a console exists to investigate. `_unhandled_input` would make it unopenable in exactly that case.

It is also why the panel does not use dot-ui. A console built on the thing being debugged is broken at the moment it is needed.

### 3. A password typed into a console has been published

`DotConsoleLine.redact` matches on the **command name**, because a password does not look like anything. It keeps the name — so a player can see they typed it and a support person can see which command failed — and replaces the arguments with a fixed number of asterisks, because the length is information too. The redaction happens before the echo *and* before the history: an un-redacted history puts the password back on screen on the next Up arrow, in front of whoever is watching.

Same reasoning as `DotConfig.sensitive_keys()`, and a console is the third place a credential gets typed, with the widest audience of the three.

## What building it found

Three failures on the first run of the suite, and two of them are traps already in this tree's own list:

- **A GDScript lambda captures locals by value**, so a test whose setter assigned to a captured `float` reported a failure for a setter that ran perfectly. Written wrong here on the first pass despite being documented. The fixture captures an `Array` now, which is the prescribed shape.
- **`_reset_cursor()` cleared the draft before it was returned.** Walking down off the end of the history gave back the empty string instead of what the player had been typing. The symptom is a console that eats your half-typed line the moment you touch an arrow key, which reads as a focus bug rather than an ordering one.
- **A silently raised capacity.** `DotConsoleBuffer.new(8)` gave you sixteen lines, because the constructor floored the value at a comfortable minimum. A console whose capacity is not the number it was given is one whose check reads as a bug in the ring. Floored at 1 now.

## The pieces

| | |
| --- | --- |
| `DotConsoleSource` | Anything a line can be sent to. `claims`, `execute`, `complete`, `names`. |
| `DotConsoleLocal` | The client's own commands and variables. `bind_setting` wires one straight through to dot-settings by duck typing, so there is one copy of a value and not two. |
| `DotConsoleBridge` | Wraps an existing console. The file that stops this being a second command system. |
| `DotConsoleRemote` | A `send_fn` to a wire. Deliberately the least capable source. |
| `DotConsoleLine` | Splitting, statements, and redaction. One pass over one string. |
| `DotConsoleBuffer` | Scrollback and history. Both rings. |
| `DotConsoleConfig` | The key, the sizes, the colours. A `DotConfig`, so dot-ui generates the screen. |
| `DotConsoleController` | Everything, with no `Control` in it. |
| `DotConsolePanel` | A `Control` that draws what the controller says. |

## Decisions

### A remote source cannot complete, and says so

A source that asks a server what its commands are called on every Tab freezes the game on every Tab. `DotConsoleRemote.learn_names` is how a client that was told the list once — at signon, in a small message — teaches it. Until that happens Tab offers nothing, which is honest.

`DotConsoleBridge` caches its name list for the same reason: `claims()` runs on every keystroke and a console with four hundred commands rebuilding and sorting that often is measurable. `invalidate()` is what a module load or a game change calls.

### An unprefixed remote source claims everything, last

Order is precedence, and a remote source added last catches what nothing local claimed. That is right for a client whose console *is* the server's. `DotConsoleRemote.prefix` is for the other shape — only `rcon <line>` goes over the wire — and it exists because an unprefixed remote console has shut down more than one dedicated server with a `quit` somebody meant for their own client.

### It does not pause the game

`runs_while_open` defaults to true. Pausing is tempting and wrong: half of what a console is for is watching something while you change it, and a console that pauses cannot debug movement, a match clock, or anything else that only misbehaves while it runs.

### A statement that fails does not stop the ones after it

`map dm_atrium; say hello` with a bad map name should still say hello. That is what every operator typing a setup line expects, and it matches dot-server's own console.

## Things deliberately not here

- **A command system.** See above. `DotConsoleLocal` is about ninety lines and is for the client's own handful.
- **A theme.** dot-ui's rule, and one of its own: this ships a `StyleBoxFlat` built in code and nothing else.
- **Argument completion.** It needs a source that knows what an argument means. dot-server's console has that and offers it through `complete()`; a remote one cannot, and offering command names in an argument position is worse than offering nothing.
- **Log mirroring on by default.** `mirror_log` is off. A dedicated server at DEBUG produces more lines per second than a player can read, and a console that is a wall of noise is one nobody opens.

## Validating

```bash
godot --headless --path . --import
find . -name '*.gd' -not -path './.godot/*' | while read f; do
    godot --headless --path . --check-only --script "res://${f#./}"
done
timeout 120 godot --headless --path . res://examples/console_selftest.tscn
```

8 sections, 77 checks. The last section builds a real `DotConsolePanel` and asserts it has a **size**, because `set_anchors_preset` does not set offsets and this family has shipped 0 × 0 `Control`s twice with every property reading correctly. That is the only half an assertion can reach; the rest wants a screenshot.

`CHECKS` is a total as well as a section count. A script error inside a test aborts *that test*, not the run — dot-settings proved it, reporting "0 failed" and exiting 0 with eight checks missing — and the section counter cannot see it because the section had already announced itself.
