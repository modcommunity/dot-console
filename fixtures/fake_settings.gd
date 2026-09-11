extends RefCounted

## A stand-in for dot-settings' manager, for the suite.
##
## No `class_name`: a fixture that declares one reserves a global identifier in every
## project that ever vendors this addon's repository, and this is a test double. It lives
## in `fixtures/` rather than `examples/` for the family's own reason -- `examples/` is
## swept by the headless runner, and a scene with no self-test in it hangs.
##
## It has `get_value` and `set_value` and nothing else, which is exactly the surface
## `DotConsoleLocal.bind_setting` duck-types against.

var stored: Dictionary = {}


func get_value(key: StringName) -> Variant:
	return stored.get(key)


func set_value(key: StringName, value: Variant) -> Variant:
	stored[key] = int(value) if str(value).is_valid_int() else value
	return null
