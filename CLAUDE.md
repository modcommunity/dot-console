# dot-console

The player's console: a key, a line, a history, and a bridge to whatever can run it. **dot-server's console is the machine that decides; dot-console is the person typing**: it has a key and a caret and no authority, and it is not a second command system.

**The distributable is `addons/dot_console/`.** It requires [dot-core](../dot-core) and nothing else: not dot-server, which it bridges to by duck typing, and not dot-ui.

```bash
ln -s ../../dot-core/addons/dot_core addons/dot_core
```

Read the family [CLAUDE.md](../../CLAUDE.md) first.

## Read before

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | the key, input handling, redaction, sources and precedence, completion, suggestions |
| [docs/console-kit.md](docs/console-kit.md) | `DotConsoleKit`, or wiring a console into a game |
| [docs/history.md](docs/history.md) | what the suite and real typing found |

## The pieces

| Class | What |
| --- | --- |
| `DotConsoleSource` | anything a line can be sent to: `claims`, `execute`, `complete`, `names` |
| `DotConsoleLocal` | the client's own commands and variables; `bind_setting` wires one straight through to dot-settings by duck typing, so there is one copy of a value |
| `DotConsoleBridge` | wraps an existing console (dot-server's); the file that stops this being a second command system |
| `DotConsoleRemote` | a `send_fn` to a wire; deliberately the least capable source |
| `DotConsoleLine` | splitting, statements and redaction, one pass over one string |
| `DotConsoleBuffer` | scrollback and history, both rings |
| `DotConsoleConfig` | the key, sizes and colours; a `DotConfig` |
| `DotConsoleController` | everything, with no `Control` in it |
| `DotConsolePanel` | the `Control` that draws it; also `is_open`/`close`/`closed`, the shape a menu's overlay list duck-types |
| `DotConsoleKit` | the console a game client builds, in one call |

`core/` holds the sources, line, buffer and config; `runtime/` the controller, panel and kit; `examples/console_selftest.tscn` is the suite.

## Running and testing

The family's two steps ([game-dev/CLAUDE.md](../../CLAUDE.md#validating-anything)), then `timeout 120 godot --headless --path . res://examples/console_selftest.tscn`.

- **`SECTIONS` and `CHECKS` in the suite are guards**: a script error aborts one test, not the run. Update `CHECKS` in the same commit as any test you add; a guard that is always red is one nobody reads. [history](docs/history.md#the-guard-that-was-always-red)
- The last section builds a real `DotConsolePanel` and asserts it has a size, because `set_anchors_preset` does not set offsets. The rest of the panel wants a screenshot.

## Rules that bite

- The open key is a physical keycode (the key under Escape), never a character; `open_action` is checked first. [design](docs/design.md#three-things-that-are-easy-to-get-wrong)
- Input is handled in `_input`, so the console opens when a screen stack has swallowed input; the panel does not use dot-ui. [design](docs/design.md#three-things-that-are-easy-to-get-wrong)
- Redact by command name, before the echo and before the history, with a fixed number of asterisks. [design](docs/design.md#three-things-that-are-easy-to-get-wrong)
- Never re-implement a server command here; bridge it. `DotConsoleLocal` is for the client's own handful. [design](docs/design.md#why-this-is-not-a-second-command-system)
- A remote source never asks the server per keystroke; it learns names once (`learn_names`). An unprefixed remote source is added last; use `prefix` when the console is not the server's. [design](docs/design.md#decisions)
- Completion text: `lstrip`, never `strip_edges`; candidates are whole lines. [design](docs/design.md#argument-completion)
- The console does not pause the game, and a failed statement does not stop the next. [design](docs/design.md#decisions)
- In a game, register the panel as one of the menu's overlays (`DotConsoleKit` does), or typing walks the player. [kit](docs/console-kit.md)
- A test that captures a local in a lambda captures it by value: capture an `Array`. [history](docs/history.md#what-building-it-found)

## Things deliberately not here

- **A command system.** dot-server's console is the one.
- **A theme.** A `StyleBoxFlat` built in code and nothing else.
- **Log mirroring on by default.** `mirror_log` is off: a server at DEBUG is a wall of noise.

## Open items

- game-playground still builds its console by hand rather than through `DotConsoleKit` (queued as `move-arena-g2gfast-1`). [kit](docs/console-kit.md)
