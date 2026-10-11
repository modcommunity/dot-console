# History

## What building it found

The first run of the suite failed three times, and two were traps already in the family's list:

- **A GDScript lambda captures locals by value**, so a test whose setter assigned to a captured `float` reported a failure for a setter that ran perfectly. The fixture captures an `Array`, the prescribed shape ([gdscript-hazards.md](../../../docs/gdscript-hazards.md)).
- **`_reset_cursor()` cleared the draft before it was returned**, so walking down off the end of the history gave back "" instead of the half-typed line. It read as a focus bug rather than an ordering one.
- **A silently raised capacity**: `DotConsoleBuffer.new(8)` gave sixteen lines.

Typing at a real console later found the prefix-only suggester empty for `mastervolume`.

## The panel never asked for argument completion

`_complete()` returned early on any space, with a comment saying argument completion belongs to whoever knows what the argument means. Right about the principle, wrong about the consequence: it never asked, so `kick ` and `log ` offered nothing on every console in the family. dot-server's half was dead too (`complete_argument` had no callers). Two halves of one feature, each correct, never introduced.

## The guard that was always red

`CHECKS` once said 89 while the suite ran 93, so every run ended `ERROR: 93 checks ran, 89 expected` and exited 1: the guard against a section aborting part-way, permanently firing about nothing. A check that is always red is one nobody reads. Update `CHECKS` in the same commit as any test you add.
