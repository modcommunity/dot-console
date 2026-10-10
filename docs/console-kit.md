# DotConsoleKit

Four games (arena, g2gfast, playground, hungario) built a console by hand, the same ~60 lines each; the other nine had none, so a setting-shaped command like dot-menu's `net_stat` was something a player could type in four games of thirteen. `DotConsoleKit.build(host, settings, menu)` is those lines once: `help`, `clear`, `settings`, every key in the settings' schema bound by name (`bind_setting`, so a new setting is a new command with nothing to add), the in-process server's console unprefixed and last, and the panel on CanvasLayer 128.

**It registers the panel as one of the menu's overlays** (duck-typed `add_overlay` / `overlay_opened`; the panel answers `is_open`, `close` and emits `closed`). That is not tidiness: an input sampler polls the keyboard, and a line edit having focus does not stop `Input.is_action_pressed` — so a console that is not an overlay walks the player forward while they type `noclip`. Every game on dot-menu already stops movement and frees the pointer on the menu's "something is open", so registering is the whole fix. The four hand-built consoles do not do this; moving them onto the kit is the way to give them it.

The six minigames, mg-buses-from-hell, game-hide-n-seek, game-zombie-zone and dot-game-template call it (and link `addons/dot_console`). Suite section 9 covers it.
