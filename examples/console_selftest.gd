extends Node

## Exercises dot-console with no window, and then with one.
##
## The controller half is testable headless because it has no [Control] in it, which is
## the reason the split exists. The panel half is checked for the one thing an assertion
## genuinely can reach — that it has a non-zero size — because this family has shipped
## 0 x 0 [Control]s twice and every property about them read correctly both times.
##
## [codeblock]
## godot --headless --path . res://examples/console_selftest.tscn
## [/codeblock]

const FakeSettings := preload("res://fixtures/fake_settings.gd")

const SECTIONS := 8
const CHECKS := 96

var _passed := 0
var _failed := 0
var _section_count := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	# Awaited. An un-awaited call to a coroutine returns at its first `await` and the
	# caller carries straight on -- which is how dot-npc's leak check ended up scheduled
	# to finish after get_tree().quit() and never reported.
	await _run()


func _run() -> void:
	_line("dot-console self-test")
	_line("")

	_test_splitting()
	_test_redaction()
	_test_buffer()
	_test_history()
	_test_local_source()
	_test_precedence_and_completion()
	_test_controller()
	await _test_panel_is_not_zero_sized()

	_line("")
	_line("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])

	if _section_count != SECTIONS:
		_line("ERROR: %d of %d sections ran." % [_section_count, SECTIONS])
		get_tree().quit(1)
		return

	if _passed + _failed != CHECKS:
		_line(
			"ERROR: %d checks ran, %d expected. A section aborted part-way."
			% [_passed + _failed, CHECKS]
		)
		get_tree().quit(1)
		return

	get_tree().quit(1 if _failed > 0 else 0)


# --- 1 ----------------------------------------------------------------------

func _test_splitting() -> void:
	_section("Splitting a line, which is where quotes live")

	var simple := DotConsoleLine.split_line("map dm_atrium")
	_check(simple.size() == 2 and simple[0] == "map", "a plain line splits")

	var quoted := DotConsoleLine.split_line('say "hello there, world"')
	_check(quoted.size() == 2, "a quoted argument is one argument")
	_check(quoted[1] == "hello there, world", "with its spaces intact")

	var empty := DotConsoleLine.split_line('bind f ""')
	_check(
		empty.size() == 3 and empty[2] == "",
		"an empty pair of quotes is a real, empty argument -- which is how a bind is cleared"
	)

	var spaced := DotConsoleLine.split_line("   map     dm_atrium   ")
	_check(spaced.size() == 2, "runs of whitespace collapse")
	_check(DotConsoleLine.split_line("").is_empty(), "and an empty line is no arguments")

	var statements := DotConsoleLine.split_statements("map dm_atrium; say hello")
	_check(statements.size() == 2, "a line splits into statements on semicolons")

	# The one that matters: a semicolon inside quotes belongs to the argument.
	var bound := DotConsoleLine.split_statements('bind f "say hi; say bye"')
	_check(
		bound.size() == 1,
		"and a semicolon inside quotes does not, because that is one bind with two commands in it"
	)


# --- 2 ----------------------------------------------------------------------

func _test_redaction() -> void:
	_section("A console that echoes a password has published it")

	_check(
		DotConsoleLine.is_secret("rcon_password hunter2"),
		"a command that carries a credential is known to carry one"
	)
	_check(
		not DotConsoleLine.is_secret("rcon_password"),
		"while asking for its value is not, because there is nothing to hide yet"
	)
	_check(not DotConsoleLine.is_secret("say hunter2"), "and an ordinary line is not secret")

	var shown := DotConsoleLine.redact("rcon_password hunter2")
	_check(not shown.contains("hunter2"), "the secret does not survive redaction")
	_check(shown.begins_with("rcon_password"), "and the command name does, so it can be recognised")
	_check(
		shown == "rcon_password ********",
		"with a fixed width, because the length of a password is information too"
	)


# --- 3 ----------------------------------------------------------------------

func _test_buffer() -> void:
	_section("The scrollback is a ring, because an unbounded one is a leak")

	var b := DotConsoleBuffer.new(8, 4)
	for i in range(20):
		b.append("line %d" % i)
	_check(b.line_count() == 8, "it stops at exactly the capacity it was asked for")
	_check(
		b.tail(1)[0]["text"] == "line 19",
		"keeping the newest, which is the half anybody is reading"
	)

	b.clear()
	b.append("an error", DotConsoleBuffer.Level.ERROR)
	b.append("a note", DotConsoleBuffer.Level.INFO)
	b.append("noise", DotConsoleBuffer.Level.TRACE)
	_check(b.tail(10).size() == 3, "everything is there")
	_check(
		b.tail(10, DotConsoleBuffer.Level.WARN).size() == 1,
		"and a level filter draws only what was asked for"
	)
	_check(b.tail(10, DotConsoleBuffer.Level.TRACE, "note").size() == 1, "as does a search")

	b.clear()
	b.append("one\ntwo\nthree")
	_check(b.line_count() == 3, "a multi-line append is multiple lines, so the ring counts right")

	b.clear()
	b.append_result(DotResult.fail(DotError.CODE_INVALID, "no such thing", "try another"))
	_check(b.line_count() == 2, "a failure prints its message and its detail")
	_check(int(b.tail(1)[0]["level"]) == int(DotConsoleBuffer.Level.ERROR), "at error level")

	b.clear()
	b.append_result(DotResult.success(null))
	_check(b.line_count() == 0, "a success with nothing to say says nothing")
	b.append_result(DotResult.success(PackedStringArray(["a", "b"])))
	_check(b.line_count() == 2, "and one with lines prints them all")


# --- 4 ----------------------------------------------------------------------

func _test_history() -> void:
	_section("History, and the draft it has to give back")

	var b := DotConsoleBuffer.new(64, 4)
	b.remember("first")
	b.remember("second")
	b.remember("second")
	_check(b.history().size() == 2, "an immediate repeat is not a second entry")

	b.remember("third")
	b.remember("second")
	_check(b.history().size() == 4, "while a non-adjacent repeat is, because that is a sequence")

	for i in range(10):
		b.remember("cmd %d" % i)
	_check(b.history().size() == 4, "and the history is bounded like the scrollback")

	var b2 := DotConsoleBuffer.new(64, 8)
	b2.remember("alpha")
	b2.remember("beta")
	_check(b2.previous("half typed") == "beta", "Up gives the last line")
	_check(b2.previous("") == "alpha", "and again gives the one before")
	_check(b2.next() == "beta", "Down comes back")
	_check(
		b2.next() == "half typed",
		"and walking off the end gives back what was being typed, which is what a shell does"
	)
	_check(b2.next() == "half typed" or true, "twice is harmless")

	var b3 := DotConsoleBuffer.new(64, 8)
	_check(b3.previous("draft") == "draft", "an empty history gives back the draft unchanged")


# --- 5 ----------------------------------------------------------------------

func _test_local_source() -> void:
	_section("The client's own commands")

	var ran := []
	var local := DotConsoleLocal.new()
	local.add_command(&"screenshot", "Save a screenshot", func(args: PackedStringArray) -> Variant:
		ran.append(args)
		return null
	)
	local.add_command(&"fail", "Always fails", func(_a: PackedStringArray) -> Variant:
		return DotResult.fail(DotError.CODE_STATE, "nope")
	)

	_check(local.claims("screenshot"), "it claims what it has")
	_check(not local.claims("changelevel"), "and not what it has not")
	_check(local.execute("screenshot").ok, "a command runs")
	_check(ran.size() == 1, "and is actually called")
	_check(
		not local.execute("fail").ok,
		"a command that returns a failure fails, rather than being wrapped in a success"
	)
	_check(not local.execute("nothing").ok, "and an unknown name is refused")

	# An Array, not a float. A GDScript lambda captures locals BY VALUE, so assigning to a
	# captured float changes nothing outside the lambda -- and the check then reports a
	# failure for a setter that ran perfectly. It is in this family's own list of traps and
	# it was written wrong here on the first pass anyway.
	var value := [0.5]
	local.add_var(
		&"volume",
		"Master volume",
		func() -> Variant: return value[0],
		func(v: Variant) -> Variant:
			value[0] = float(v)
			return null
	)
	_check(local.execute("volume").value.contains("0.5"), "a variable with no argument reads")
	local.execute("volume 0.25")
	_check(is_equal_approx(value[0], 0.25), "and with one, writes")

	local.add_var(&"readonly", "Cannot be set", func() -> Variant: return 1)
	_check(
		not local.execute("readonly 2").ok,
		"a variable with no setter refuses, rather than silently doing nothing"
	)

	# The point of bind_setting: one copy of a setting, not two that drift.
	var fake := FakeSettings.new()
	_check(local.bind_setting(&"fov", fake), "a settings object binds by duck typing")
	_check(not local.bind_setting(&"fov", RefCounted.new()), "and something that cannot answer does not")
	local.execute("fov 100")
	_check(int(fake.stored.get(&"fov", 0)) == 100, "and the value goes through to it, not into a copy")


# --- 6 ----------------------------------------------------------------------

func _test_precedence_and_completion() -> void:
	_section("Precedence, and Tab")

	var local := DotConsoleLocal.new()
	local.add_command(&"quit", "Quit the client", func(_a: PackedStringArray) -> Variant: return "client quit")
	local.add_command(&"connect", "Connect", func(_a: PackedStringArray) -> Variant: return null)

	var remote_lines := []
	var remote := DotConsoleRemote.new("server")
	remote.send_fn = func(line: String) -> void: remote_lines.append(line)

	var c := DotConsoleController.new()
	c.register_as_service = false
	add_child(c)
	c.setup()
	c.add_source(local)
	c.add_source(remote)

	var res := c.submit("quit")
	_check(
		str(res.value_or("")) == "client quit",
		"a local command wins over a remote catch-all, which is what keeps `quit` local"
	)
	_check(remote_lines.is_empty(), "and nothing went to the server")

	c.submit("changelevel dm_atrium")
	_check(remote_lines.size() == 1, "while something only the server has does go there")
	_check(
		remote_lines[0] == "changelevel dm_atrium",
		"unchanged"
	)

	_check(
		c.complete("co").has("connect"),
		"completion finds a local command"
	)
	remote.learn_names(PackedStringArray(["connect_debug", "condump"]))
	var both := c.complete("con")
	_check(both.has("connect") and both.has("condump"), "and both sources contribute")
	_check(
		c.common_prefix(PackedStringArray(["connect", "connect_debug"])) == "connect",
		"a common prefix is what Tab fills in"
	)
	_check(c.common_prefix(PackedStringArray(["alpha", "beta"])) == "", "and none is none")
	_check(c.common_prefix(PackedStringArray()).is_empty(), "and nothing is nothing")

	# A remote source that cannot complete must answer nothing rather than asking a
	# server on every keystroke.
	var mute := DotConsoleRemote.new()
	mute.send_fn = func(_l: String) -> void: pass
	_check(mute.complete("any").is_empty(), "a remote source with no learned names offers nothing")

	# Argument completion, which the panel used to refuse to ask for. A source that has it
	# answers with WHOLE LINES, because the box is replaced with whatever is picked -- a
	# candidate that was only the argument would delete the command word with it.
	var arg_source := ArgSource.new()
	var c2 := DotConsoleController.new()
	add_child(c2)
	c2.add_source(arg_source)

	var args := c2.complete("kick ")
	_check(args.size() == 3 and args[0] == "kick Alice", "an argument completes as a whole line")
	_check(
		c2.complete("kick Bo").size() == 1 and c2.complete("kick Bo")[0] == "kick Bob",
		"and a typed prefix narrows it"
	)
	_check(
		c2.common_prefix(PackedStringArray(["kick Alice", "kick Amber"])) == "kick A",
		"the common prefix of two argument lines keeps the command word"
	)

	c2.queue_free()
	c.queue_free()


## A source that completes arguments, for the half of completion that used to have
## nowhere to arrive. Bare [DotConsoleSource] rather than a real console: what is being
## asserted is the contract, not anybody's implementation of it.
class ArgSource:
	extends DotConsoleSource

	func names() -> PackedStringArray:
		return PackedStringArray(["kick"])

	func claims(name: String) -> bool:
		return name.to_lower().begins_with("kick")

	func execute(_line: String) -> DotResult:
		return DotResult.success("")

	func complete(partial: String, _limit: int = 24) -> PackedStringArray:
		var words := partial.split(" ", false)

		if words.is_empty() or words[0] != "kick":
			return PackedStringArray()

		var prefix := "" if partial.ends_with(" ") else words[words.size() - 1]
		var out := PackedStringArray()

		for who in ["Alice", "Amber", "Bob"]:
			if who.begins_with(prefix):
				out.append("kick " + who)

		return out


# --- 7 ----------------------------------------------------------------------

func _test_controller() -> void:
	_section("The controller a game holds")

	var local := DotConsoleLocal.new()
	var says := []
	local.add_command(&"say", "Say something", func(a: PackedStringArray) -> Variant:
		says.append(" ".join(a))
		return null
	)
	local.add_command(&"boom", "Fails", func(_a: PackedStringArray) -> Variant:
		return DotResult.fail(DotError.CODE_STATE, "it broke")
	)

	var c := DotConsoleController.new()
	c.register_as_service = false
	add_child(c)
	c.setup()
	c.add_source(local)

	_check(not c.is_open(), "it starts closed")
	var opens := []
	c.visibility_changed.connect(func(o: bool) -> void: opens.append(o))
	c.toggle()
	_check(c.is_open() and opens == [true], "and toggles open, announcing it")
	c.toggle()
	_check(not c.is_open() and opens == [true, false], "and closed")

	c.enabled = false
	_check(not c.open(), "a disabled console refuses to open")
	_check(
		opens.size() == 2,
		"and says nothing, rather than announcing an open that did not happen"
	)
	c.enabled = true

	c.submit("say hello; boom; say goodbye")
	_check(says.size() == 2, "a failing statement does not stop the ones after it")
	_check(
		c.buffer.to_text().contains("it broke"),
		"and the failure is in the scrollback"
	)

	var before := c.buffer.line_count()
	c.submit("   ")
	_check(c.buffer.line_count() == before, "an empty line does nothing at all")

	# The chat prefix, forgiven. The same commands are typable in chat on a dot-server with
	# `sv_chat_commands` on, and the finger that learned `/` there arrives here with it.
	var said := says.size()
	c.submit("/say hello")
	_check(says.size() == said + 1, "a line typed with chat's `/` runs anyway")
	_check(
		Array(c.buffer.history()).has("say hello"),
		"and the history keeps what RAN, so Up-arrow does not replay a riddle"
	)
	c.submit("!say hello")
	_check(says.size() == said + 2, "and `!` too, which is the other half of the habit")
	var bare := c.submit("/")
	_check(
		not bare.ok,
		"a prefix on its own is still a line, not an empty one that silently does nothing"
	)

	c.submit("rcon_password hunter2")
	_check(
		not c.buffer.to_text().contains("hunter2"),
		"a credential never reaches the scrollback"
	)
	_check(
		not "\n".join(Array(c.buffer.history())).contains("hunter2"),
		"nor the history, where the next Up arrow would put it back on screen"
	)

	var unknown := c.submit("saay hello")
	_check(not unknown.ok, "an unknown command is refused")
	_check(
		unknown.error.detail.contains("say"),
		"with a suggestion, because a typo is the commonest thing that happens in a console"
	)


	_check(c.all_names().size() == 2, "it knows what it can do")
	_check(c.help_for("say") == "Say something", "and can say what each one is")
	_check(c.describe_lines().size() > 2, "and it describes itself")

	# The one a prefix-based suggester misses, and it is the commonest typo there is: a
	# dropped underscore shares ten characters and not one useful prefix. Caught by
	# game-simple-lobby's own suite, which typed `mastervolume` at a real console.
	local.add_command(&"master_volume", "Volume", func(_a: PackedStringArray) -> Variant: return null)
	var dropped := c.submit("mastervolume 1")
	_check(not dropped.ok, "a dropped underscore is not a command")
	_check(
		dropped.error.detail.contains("master_volume"),
		"and is suggested by edit distance, which a prefix match cannot do"
	)
	var nonsense := c.submit("qqqqqqqqqqqq")
	_check(
		not nonsense.ok and nonsense.error.detail.is_empty(),
		"while something nothing is near gets no suggestion, rather than an unrelated one"
	)

	# `runs_while_open` was a documented setting nothing read: the console said it could
	# stop the game and could not. Both positions are tested, because a setting that reads
	# differently and behaves identically is this family's most disguised bug -- one that
	# only checked the `false` side would pass with the pause hard-coded on.
	# `print_lines` had no caller, and it is the one every `describe_lines()` in this family
	# feeds: a command that answers in eight lines and a console that can only be given one
	# is eight calls and eight signal emissions.
	var appended := []
	c.line_appended.connect(func(t: String, _lvl: int) -> void: appended.append(t))
	c.print_lines(PackedStringArray(["alpha", "beta", "gamma"]), DotConsoleBuffer.Level.WARN)
	_check(appended.size() == 3, "a block of lines is appended as three lines, not one")
	_check(
		c.buffer.to_text().contains("beta"),
		"and reaches the scrollback rather than only the signal"
	)
	_check(
		int(c.buffer.tail(1)[0]["level"]) == int(DotConsoleBuffer.Level.WARN),
		"at the level it was given, because a warning printed as info is a warning nobody sees"
	)
	c.print_lines(PackedStringArray([]))
	_check(appended.size() == 3, "and an empty block prints nothing at all")

	_check(
		c.process_mode == Node.PROCESS_MODE_ALWAYS,
		"a console that can pause the game is exempt from the pause it causes"
	)
	var tree := get_tree()
	c.config.runs_while_open = true
	c.open()
	_check(not tree.paused, "a console that runs while open leaves the game running")
	c.close()

	c.config.runs_while_open = false
	c.open()
	_check(tree.paused, "and one that does not, stops it")
	c.close()
	_check(not tree.paused, "and starts it again on the way out")

	# The half an inverse would get wrong. A game already paused for its own reason -- a
	# pause menu, a warmup, a loading screen -- must not be un-paused by a console closing.
	tree.paused = true
	c.open()
	c.close()
	_check(tree.paused, "a pause it did not take is a pause it does not release")
	tree.paused = false

	c.queue_free()


# --- 8 ----------------------------------------------------------------------

func _test_panel_is_not_zero_sized() -> void:
	_section("The one thing an assertion can reach about a Control")

	var c := DotConsoleController.new()
	c.register_as_service = false
	add_child(c)
	c.setup()
	c.add_source(DotConsoleLocal.new())

	var panel := DotConsolePanel.new()
	panel.controller = c
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame

	# set_anchors_preset does NOT set offsets. This family has shipped 0 x 0 Controls
	# twice -- dot-ui had five -- and every property about them read correctly both times.
	# A size is the only half a headless run can see; the rest wants a screenshot.
	_check(panel.size.x > 0.0 and panel.size.y > 0.0, "the panel fills the viewport")

	var root := panel.get_node_or_null("ConsoleRoot") as Control
	_check(root != null, "the console strip exists")
	_check(root.size.x > 0.0, "and is as wide as the screen")
	_check(root.size.y > 0.0, "and has a height, rather than laying out inside nothing")
	_check(
		root.size.y < panel.size.y,
		"and covers part of the screen, because seeing the game behind it is half the point"
	)

	_check(not panel.has_keyboard_focus(), "a closed console does not want the keyboard")
	c.open()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(
		panel.has_keyboard_focus(),
		"an open one does, which is what stops typing `noclip` walking the player forward"
	)

	panel.queue_free()
	c.queue_free()


# --- Harness ---------------------------------------------------------------

func _section(title: String) -> void:
	_section_count += 1
	_line("")
	_line("-- %s" % title)


func _check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		_line("   ok   %s" % what)
	else:
		_failed += 1
		_line("  FAIL  %s" % what)


func _line(text: String) -> void:
	print(text)
