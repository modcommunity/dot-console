extends RefCounted

## dot-console's API level. The rule for bumping it is on [DotAddonApi].
##
## LEVEL rises by one for anything a game could call that did not exist before. OLDEST is
## raised to LEVEL when something a game could have called is removed or changes meaning,
## because every pack built before that no longer compiles against this addon.

# 1: everything before this file existed (DotConsoleController, DotConsolePanel,
#    DotConsoleLocal, DotConsoleBridge, DotConsoleRemote, DotConsoleLine, DotConsoleBuffer,
#    DotConsoleConfig).
# 2: DotConsoleKit; DotConsolePanel is_open(), close() and closed.
# 3: DotConsoleKit.add_self_mute(local): the `sm` command, in local_source.
const LEVEL := 3
const OLDEST := 1
