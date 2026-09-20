This is the **console** asset for TMC's **Dot** collection. It adds the developer console a player opens with a key: a line, a history, tab completion, scrollback, and a bridge to whatever command system the game already has.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

## It is a console, not a command system

This is the one decision everything else follows from. dot-server already has a command system, with commands, cvars, permissions, aliases, config execution and argument completion, and has had one for months. Building a second would be two copies of one thing, which is the bug this family guards hardest against; naming dot-server's would make it a hard dependency, which the family's rules forbid.

So dot-console owns **the key, the line editing, the history, the scrollback and the drawing**, and asks *sources* to run the line. Three ship:

| | |
| --- | --- |
| `DotConsoleLocal` | The handful of things that genuinely belong to the machine the player is at: a volume, a bind, a screenshot, `quit`. Works with no server in the process. |
| `DotConsoleBridge` | Wraps anything with `execute` and `complete` by duck typing, so a server's console becomes a source without this asset naming a single type in it. |
| `DotConsoleRemote` | A `send_fn` that puts the line on a wire, for RCON or a chat command. |

Sources are asked in order, and the first that claims a name handles it, so a local `quit` quits the client rather than the dedicated server, which is a mistake worth making impossible.

## Three details that are not obvious

**The key is bound by position, not by character.** The console key is the one under Escape, and it produces `` ` `` on a UK keyboard, `^` on a German one and `²` on a French one. Binding the character means the console cannot be opened at all across most of Europe, and the player's only clue is that nothing happens. `open_physical_key` is a physical keycode, and `open_action` comes first so a rebinder can move it.

**The scrollback is a ring.** An unbounded console buffer is a memory leak with a plausible name: a dedicated server logging a line per tick fills it in an afternoon, and the console, which is the thing you would open to find out why the process is growing, is the cause.

**A password typed into a console has been published.** It goes into the scrollback, into the history where the next Up arrow puts it back on screen, and into the screenshot somebody posts to ask why their server will not start. `DotConsoleLine.redact` keeps the command name and replaces the rest with a fixed number of asterisks, because the length of a password is information too.

## The controller draws nothing

`DotConsoleController` is a `Node` with no `Control` anywhere in it: sources, scrollback, history, completion and the key. `DotConsolePanel` is a `Control` that draws whatever it says. That is what makes a headless suite possible, and it is the same rule as the spectate asset's "computes a transform and touches no camera".

The panel does not use dot-ui, and that is not an oversight: **a console has to work when the interface does not.** Half of what one is for is finding out why a screen stack is stuck or a mouse mode is wrong, and a console built on the thing being debugged is broken at the moment it is needed.

## Using it

```gdscript
var console := DotConsoleController.new()
add_child(console)
console.setup()

var local := DotConsoleLocal.new()
local.add_command(&"quit", "Quit", func(_a): get_tree().quit())
local.bind_setting(&"sensitivity", settings)      # duck-typed; one copy of the value
console.add_source(local)
console.add_source(DotConsoleBridge.wrap(server.console))   # when there is a server

var panel := DotConsolePanel.new()
panel.controller = console
canvas_layer.add_child(panel)
```

And the one line every game with a console forgets:

```gdscript
if panel.has_keyboard_focus():
    return      # otherwise typing `noclip` walks the player forward
```

## Installing

Copy `addons/dot_console/` and [`dot-core`](https://github.com/modcommunity/dot-core)'s `addons/dot_core/` into your project and enable dot-console in **Project → Project Settings → Plugins**.

## Dependencies

[dot-core](https://github.com/modcommunity/dot-core). Nothing else, and in particular not dot-server, which it bridges to by duck typing, nor dot-ui.

## Licence

MIT. See [LICENSE](LICENSE).
