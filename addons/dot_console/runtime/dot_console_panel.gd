class_name DotConsolePanel
extends Control

## The console on screen. Built in code, themed by nothing, drawn by the engine.
##
## Ships no art and no [Theme], for dot-ui's reason. It also does not depend on dot-ui,
## and that is not an oversight: **a console has to work when the interface does not.**
## Half of what one is for is finding out why a screen stack is stuck, a mouse mode is
## wrong or a menu will not close, and a console built on the thing being debugged is a
## console that is broken at exactly the moment it is needed.
##
## [codeblock]
## var panel := DotConsolePanel.new()
## panel.controller = console
## add_child(panel)          # to a CanvasLayer, above everything
## [/codeblock]
##
## [b]Every offset is set explicitly.[/b] [method Control.set_anchors_preset] does NOT set
## offsets, and this family has shipped 0 × 0 [Control]s twice — dot-ui had five of them,
## and every screen it ever hosted was zero-sized unless a host happened to size it. The
## symptom is nothing on screen while every property reads correctly, which no assertion
## catches: only a rendered frame does. `set_anchors_and_offsets_preset` is the spelling
## that works and it is used everywhere below.

const CHANNEL := "console"

@export var controller: DotConsoleController = null

## Lines drawn. More than this is in the buffer and reachable by scrolling.
@export_range(4, 500, 1) var visible_lines: int = 200

var _root: PanelContainer = null
var _output: RichTextLabel = null
var _input: LineEdit = null
var _hint: Label = null
var _target_y := 0.0
var _current_y := 0.0


func _ready() -> void:
	# The panel is the whole screen; the console is a strip inside it that slides. Doing
	# it the other way -- animating the panel itself -- fights every anchor.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# The controller's reason, on the drawing half: `runs_while_open = false` pauses the
	# tree, and a paused Control neither animates nor handles the input that would type
	# into it. A console that pauses the game has to be exempt from that pause, or opening
	# it is indistinguishable from a freeze.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	if controller != null:
		_bind(controller)
	_apply_visible(false, true)


func _build() -> void:
	var cfg := controller.config if controller != null else DotConsoleConfig.new()

	_root = PanelContainer.new()
	_root.name = "ConsoleRoot"
	# Anchored to the top, sized as a fraction of the screen. Offsets explicitly, not a
	# preset: a preset leaves them at zero and the whole console lays out inside nothing.
	_root.anchor_left = 0.0
	_root.anchor_right = 1.0
	_root.anchor_top = 0.0
	_root.anchor_bottom = 0.0
	_root.offset_left = 0.0
	_root.offset_right = 0.0
	_root.offset_top = 0.0
	_root.offset_bottom = 0.0
	_root.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, cfg.background_opacity)
	style.border_color = Color(0.30, 0.34, 0.40, 0.9)
	style.border_width_bottom = 2
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	_root.add_theme_stylebox_override("panel", style)
	add_child(_root)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	_root.add_child(column)

	_output = RichTextLabel.new()
	_output.scroll_following = true
	_output.bbcode_enabled = true
	_output.selection_enabled = true
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.add_theme_font_size_override("normal_font_size", cfg.font_size)
	_output.add_theme_font_size_override("mono_font_size", cfg.font_size)
	column.add_child(_output)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", maxi(8, cfg.font_size - 2))
	_hint.add_theme_color_override("font_color", Color(0.55, 0.60, 0.68))
	_hint.visible = false
	column.add_child(_hint)

	var row := HBoxContainer.new()
	column.add_child(row)

	var prompt := Label.new()
	prompt.text = "]"
	prompt.add_theme_font_size_override("font_size", cfg.font_size)
	row.add_child(prompt)

	_input = LineEdit.new()
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.add_theme_font_size_override("font_size", cfg.font_size)
	_input.caret_blink = true
	# Godot's own history would fight the controller's, and the controller's is the one
	# with the rules -- adjacent duplicates suppressed, the draft kept.
	_input.context_menu_enabled = false
	_input.text_submitted.connect(_on_submitted)
	_input.gui_input.connect(_on_input_key)
	row.add_child(_input)


func _bind(c: DotConsoleController) -> void:
	c.line_appended.connect(_on_line)
	c.visibility_changed.connect(func(open: bool) -> void: _apply_visible(open, false))
	_redraw()


# --- Drawing ----------------------------------------------------------------

func _on_line(_text: String, _level: int) -> void:
	# Redrawing the whole tail rather than appending: a line can arrive while the console
	# is closed, the buffer is a ring that drops from the front, and an append-only view
	# of a ring is a view that grows for ever.
	if visible:
		_redraw()


func _redraw() -> void:
	if controller == null or _output == null:
		return
	_output.clear()
	for entry in controller.buffer.tail(visible_lines):
		_output.append_text("%s\n" % _decorate(str(entry["text"]), int(entry["level"])))


func _decorate(text: String, level: int) -> String:
	var escaped := text.replace("[", "[lb]")
	match level:
		DotConsoleBuffer.Level.ERROR:
			return "[color=#ff6b6b]%s[/color]" % escaped
		DotConsoleBuffer.Level.WARN:
			return "[color=#ffc857]%s[/color]" % escaped
		DotConsoleBuffer.Level.ECHO:
			return "[color=#8fd3ff]%s[/color]" % escaped
		DotConsoleBuffer.Level.DEBUG, DotConsoleBuffer.Level.TRACE:
			return "[color=#8b95a5]%s[/color]" % escaped
		_:
			return escaped


func _apply_visible(open: bool, immediate: bool) -> void:
	var cfg := controller.config if controller != null else DotConsoleConfig.new()
	var height := size.y * cfg.height_fraction
	_root.offset_bottom = height
	_target_y = 0.0 if open else -height

	if immediate or cfg.slide_seconds <= 0.0:
		_current_y = _target_y
		_root.position.y = _current_y
	set_process(true)

	visible = open or absf(_current_y - _target_y) > 0.5
	if open:
		_redraw()
		# Deferred: the LineEdit cannot take focus in the same frame it becomes visible,
		# and a console that opens without the caret in it is a console you have to click.
		_input.call_deferred("grab_focus")
		_input.clear()
	else:
		_input.release_focus()


func _process(delta: float) -> void:
	var cfg := controller.config if controller != null else DotConsoleConfig.new()
	if is_equal_approx(_current_y, _target_y):
		visible = _target_y >= 0.0
		set_process(false)
		return
	var speed := (absf(_root.offset_bottom) / maxf(cfg.slide_seconds, 0.001)) * delta
	_current_y = move_toward(_current_y, _target_y, speed)
	_root.position.y = _current_y
	visible = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _root != null and controller != null:
		_apply_visible(controller.is_open(), true)


# --- Input ------------------------------------------------------------------

func _on_submitted(text: String) -> void:
	if controller == null:
		return
	controller.submit(text)
	_input.clear()
	_hint.visible = false
	_redraw()


func _on_input_key(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or controller == null:
		return

	match key.keycode:
		KEY_UP:
			_input.text = controller.buffer.previous(_input.text)
			_input.caret_column = _input.text.length()
			accept_event()
		KEY_DOWN:
			_input.text = controller.buffer.next()
			_input.caret_column = _input.text.length()
			accept_event()
		KEY_TAB:
			_complete()
			accept_event()
		KEY_PAGEUP:
			_output.get_v_scroll_bar().value -= _output.size.y * 0.8
			accept_event()
		KEY_PAGEDOWN:
			_output.get_v_scroll_bar().value += _output.size.y * 0.8
			accept_event()


func _complete() -> void:
	var partial := _input.text.strip_edges()
	if partial.contains(" "):
		# Argument completion belongs to whoever knows what the argument means, and only
		# some sources do. Offering nothing is honest; offering command names in an
		# argument position is worse than offering nothing.
		return
	var candidates := controller.complete(partial)
	if candidates.is_empty():
		_hint.visible = false
		return
	if candidates.size() == 1:
		_input.text = candidates[0] + " "
		_input.caret_column = _input.text.length()
		_hint.visible = false
		return

	# Fill in as far as every candidate agrees, then show the rest. What a shell does, and
	# its absence is what makes a homemade console feel homemade.
	var prefix := controller.common_prefix(candidates)
	if prefix.length() > partial.length():
		_input.text = prefix
		_input.caret_column = _input.text.length()
	_hint.text = "  ".join(candidates)
	_hint.visible = true


## Whether the console currently wants the keyboard.
##
## What a game asks before reading movement keys. Without it, opening the console and
## typing `noclip` walks the player forward — which is the single most reported bug in
## every game that ships a console and forgets this.
func has_keyboard_focus() -> bool:
	return visible and _input != null and _input.has_focus()
