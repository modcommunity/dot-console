class_name DotConsoleKit
extends RefCounted

## The console a game client builds, built in one call: the key, the panel, `help`,
## `clear`, `settings`, every setting by its own name, and the server's console when one
## is running in this process.
##
## [codeblock]
## console = DotConsoleKit.build(self, settings_manager, menu)
## # ` opens it; `net_stat 2`, `master_volume 0.5`, `help`
## [/codeblock]
##
## [b]Why one call.[/b] Four games wrote this by hand (~60 lines each, the same lines) and
## the other nine had no console at all, so a command that is a setting — `net_stat` — was
## something a player could type in four games out of thirteen. A setting bound here is a
## command in every game that calls this, with nothing else to add when a setting is new.
##
## [b]Every argument is duck-typed.[/b] [param settings] is anything with `get_value`,
## `set_value` and a `schema` with `keys()`/`find()` (dot-settings' manager); [param menu]
## is anything with `add_overlay(control)` and `overlay_opened()` (dot-menu's [code]DotMenu
## [/code]). This addon keeps its one dependency.
##
## [b]Registered with the menu as one of its overlays[/b], when there is a menu: so the
## game's "something is open" hook — which already stops movement and frees the pointer
## for the menu — does the same for the console. Without it, every key typed into the
## console would also walk the player, because an input sampler polls the keyboard and a
## line edit having focus does not stop that.

const CHANNEL := "console"


## Builds the console under [param host] and returns its controller. The panel is on a
## CanvasLayer of [param layer], over the menu (110) and the chat (100): a console that can
## be covered is not one you can debug a stuck screen with.
static func build(
	host: Node, settings: Object = null, menu: Object = null, layer: int = 128
) -> DotConsoleController:
	var console := DotConsoleController.new()
	console.name = "Console"
	console.config = DotConsoleConfig.new()
	console.config.mirror_log = true
	console.config.mirror_from = DotLog.Level.INFO
	host.add_child(console)

	var res := console.setup()
	if not res.ok:
		DotLog.warn(CHANNEL, "no console", {"why": res.error.message})

	console.add_source(local_source(console, settings))

	# Unprefixed and last, so it catches what this client did not claim -- the family's
	# default (see DotConsoleRemote's note on prefixes for when that is wrong).
	var server: Object = DotRegistry.get_service(&"dot_server")
	if server != null and server.get("console") != null:
		console.add_source(DotConsoleBridge.wrap(server.get("console"), "server"))

	var canvas := CanvasLayer.new()
	canvas.name = "ConsoleLayer"
	canvas.layer = layer
	host.add_child(canvas)

	var panel := DotConsolePanel.new()
	panel.name = "ConsolePanel"
	panel.controller = console
	canvas.add_child(panel)

	if menu != null and menu.has_method(&"add_overlay"):
		menu.call(&"add_overlay", panel)
		if menu.has_method(&"overlay_opened"):
			console.visibility_changed.connect(func(open: bool) -> void:
				if open:
					menu.call(&"overlay_opened"))

	return console


## The registry name and the script of the player's own block list (dot-chat's
## `DotChatSelfMute`), reached by name and path so this addon keeps its one dependency.
const SELF_MUTE_SERVICE := &"dot_self_mute"
const SELF_MUTE_SCRIPT := "res://addons/dot_chat/runtime/dot_chat_self_mute.gd"


## `sm`, the player's own block list: `sm` lists who is here, `sm <number|name|#userid>`
## mutes or unmutes their chat and voice on this client only. Added when dot-chat is in the
## build; the same list the chat box's `!sm` runs. False when there is no list to run.
static func add_self_mute(local: DotConsoleLocal) -> bool:
	if DotRegistry.get_service(SELF_MUTE_SERVICE) == null and not ResourceLoader.exists(SELF_MUTE_SCRIPT):
		return false
	local.add_command(&"sm", "Self mute: sm lists players; sm <number|name|#userid> mutes or unmutes their chat and voice for you only",
		func(args: PackedStringArray) -> Variant:
			var mutes := _self_mute()
			if mutes == null or not mutes.has_method(&"run"):
				return "There is no block list in this build."
			return mutes.call(&"run", args)
	)
	return true


static func _self_mute() -> Object:
	var found: Object = DotRegistry.get_service(SELF_MUTE_SERVICE)
	if found != null or not ResourceLoader.exists(SELF_MUTE_SCRIPT):
		return found
	var script: Variant = load(SELF_MUTE_SCRIPT)
	if not (script is Script):
		return null
	var shared: Variant = (script as Script).call(&"shared")
	return shared if shared is Object else null


## `help`, `clear`, `settings`, `sm`, and every setting [param settings] declares, by its own
## name. The part of [method build] a game with its own panel can still use.
static func local_source(console: DotConsoleController, settings: Object = null) -> DotConsoleLocal:
	var local := DotConsoleLocal.new()
	local.add_command(&"help", "List what this client can do", func(_a: PackedStringArray) -> Variant:
		var lines := PackedStringArray(["Client commands:"])
		for n in console.all_names():
			lines.append("  %-22s %s" % [n, console.help_for(n)])
		return lines
	)
	local.add_command(&"clear", "Empty the scrollback", func(_a: PackedStringArray) -> Variant:
		console.buffer.clear()
		return null
	)
	add_self_mute(local)
	if settings == null:
		return local
	if settings.has_method(&"describe_lines"):
		local.add_command(&"settings", "Show every setting", func(_a: PackedStringArray) -> Variant:
			return settings.call(&"describe_lines")
		)
	var schema: Object = settings.get(&"schema")
	if schema != null and schema.has_method(&"keys"):
		for key: StringName in schema.call(&"keys"):
			var def: Object = schema.call(&"find", key) if schema.has_method(&"find") else null
			var help := str(def.get(&"description")) if def != null and def.get(&"description") != null else ""
			var _bound := local.bind_setting(key, settings, help)
	return local
