# Timer

A small, dependency-free scheduler and tweening library for Lua, LÖVE, and LÖVR.

Current release: **2.0.0** ([changelog](CHANGELOG.md)).

Timer v2 keeps the familiar positional API from v1 while tightening correctness:
invalid values fail at the call site, callbacks run in a deterministic order, and
coroutine scripts now have a real lifecycle. See [MIGRATION.md](MIGRATION.md) if
you are upgrading an existing project.

## Features

- **Global or local pools** — use the module-level instance for prototypes, or
  create independent pools with `timer.new()`.
- **Tags and handles** — cancel, pause, or replace tasks by reference or by a
  per-pool tag.
- **Schedulers** — one-shot delays, repeating intervals (with random ranges and
  execution limits), per-frame windows, and table tweens.
- **Coroutine scripts** — write sequential events with `wait(seconds)`, cancel or
  pause them through a handle, and get real error tracebacks.
- **Deterministic ordering** — same-frame callbacks run in registration order.
- **Normalised easing lookup** — `quadinout`, `in-out-quad`, `easeInOutQuad`, and
  `backOut` all resolve to the same functions; custom easings can be registered.
- **Runtime controls** — per-task pause, pool-wide pause, and time scaling.
- **No dependencies** — a single Lua file compatible with Lua 5.1+, LuaJIT,
  LÖVE, and LÖVR.

## Compatibility

- Lua 5.1, 5.2, 5.3, 5.4, and LuaJIT.
- LÖVE and LÖVR: call `timer.update(dt)` from your update loop.
- The library itself does not call any engine APIs.

## Installation

Copy `timer.lua` into your project and require it:

```lua
local timer = require 'timer'
```

`init.lua` is a compatibility shim for projects that used to
`require 'init'`. It simply forwards to `timer.lua`, so vendoring both files is
enough for an incremental upgrade. New code should require `'timer'`.

## Quick start

```lua
local timer = require 'timer'

function lovr.load()
  timer.after(3, function()
    print("three seconds later")
  end)

  timer.every(0.5, function()
    print("tick")
  end, "heartbeat")

  timer.tween(1, player, { x = 10 }, "quadout", function()
    print("arrived")
  end, "player_move")
end

function lovr.update(dt)
  timer.update(dt)
end
```

### Independent pools

Tags are scoped to a pool. Tie a pool to a scene or entity lifecycle to avoid
global tag collisions:

```lua
local Timer = require 'timer'
local effects = Timer.new()

effects:after(0.15, function() flash = false end, "flash")
effects:update(dt)
effects:clear() -- discard everything when the scene unloads
```

## API

All durations are in seconds. `dt` must be finite and non-negative. Inputs are
validated when a task is created, so invalid values fail at the call site instead
of crashing later inside `update`.

### Core

#### `timer.update(dt)`

Advances the global pool once per frame. Tasks are processed in registration
order. Tasks registered during the update start on the next update.

#### `timer.new()`

Creates an independent pool. Use colon calls on the returned object:

```lua
local pool = timer.new()
pool:update(dt)
```

#### `timer.cancel(handle_or_tag)`

Cancels a task or script by handle or tag. Returns `true` if something was
cancelled.

#### `timer.pause(handle_or_tag)` / `timer.resume(handle_or_tag)`

Pauses or resumes a task or script. A paused task keeps its tag and its
accumulated time. Both return a boolean.

#### `timer.isPaused([handle_or_tag])`

With no argument, reports whether the whole pool is paused. With a handle or tag,
reports whether that object is paused (a pool-wide pause also counts).

#### `timer.exists(handle_or_tag)`

Returns `true` while the task or script is active.

#### `timer.remaining(handle_or_tag)`

Returns seconds until the next event, or `nil` if the object is gone. For
`every` this is time to the next tick; for scripts it is the current wait.

#### `timer.count()`

Returns the number of active scheduled tasks, including internal script waits.

#### `timer.clear()`

Cancels every task, script, and tag in the pool. Task and script handles remain
safe to call but become inert.

#### `timer.setTimeScale(scale)` / `timer.getTimeScale()`

Changes a pool-wide multiplier. `1` is normal speed, `0.5` is slow motion, and
`0` freezes time while still allowing zero-duration work to complete. The scale
must be finite and non-negative.

#### `timer.pauseAll()` / `timer.resumeAll()`

Freeze or unfreeze the entire pool without changing individual task pause flags.

### Scheduling

#### `timer.after(delay, action, [tag])`

Runs `action` once after `delay` seconds. Returns a task handle.

#### `timer.every(delay, action, [count], [after_action], [tag])`

Runs `action` repeatedly. `delay` may be a number or a `{min, max}` array for a
fresh random interval each cycle. `count` is the maximum number of executions;
`0` or `nil` means forever. `after_action` runs when `count` is exhausted, not
when `action` returns `false`. Returning `false` from `action` stops the loop.

For convenience, `timer.every(delay, action, "tag")` is accepted and treated as
an infinite loop with that tag.

`every` fires at most once per `update`: a long frame does not replay missed
ticks. This avoids a spiral of death but means the effective rate can lag under
heavy load.

#### `timer.during(delay, action, [after_action], [tag])`

Calls `action(dt)` once per update for `delay` seconds, then calls
`after_action`. The final call receives the full (scaled) frame `dt`, so movement
can overshoot the exact duration by one frame. `timer.during(delay, action, "tag")`
is accepted as a convenience.

#### `timer.tween(delay, target, payload, [method], [after_action], [tag])`

Interpolates numeric fields from their current values to `payload`, then calls
`after_action`. `target` and `payload` must be tables. `method` may be a name
string or a function `(t) -> number`; it defaults to `"linear"`. A zero-duration
tween applies its final values on the next update. Unknown easing names raise an
error at creation.

A new tween with the same tag replaces the old one and starts from the values
the old tween had reached. Two untagged tweens writing the same fields will
fight each other; give them distinct tags or drive the value with a single tween.

#### `timer.script(f, [tag])`

Runs `f(wait)` as a coroutine. `wait(seconds)` yields until the delay elapses and
requires a finite non-negative number. The first part of the function runs
immediately until its first `wait`.

```lua
local script = timer.script(function(wait)
  wait(1)
  timer.tween(0.5, banner, { alpha = 1 }, "quadout")
  wait(0.5)
  banner.visible = false
end, "intro")

timer.pause(script)
timer.resume(script)
timer.cancel(script)
```

Scripts are registered under their tag while running. Registering another timer
or script with the same tag replaces the script. Internal waits are private,
untagged tasks tracked by the script, so they never cancel unrelated user tasks.

Errors inside a script are re-thrown with a traceback — from `timer.script` for
errors before the first `wait`, and from `update` for later errors. `wait()` with
a missing or invalid delay is an error instead of a silently stalled coroutine.
The returned script handle can be passed to
`cancel`, `pause`, `resume`, `exists`, `remaining`, and `isPaused`.

### Tags, handles, and ordering

- Tags may be any non-nil Lua value that is a valid table key; NaN is rejected.
  Each pool has its own tag namespace.
- A tag can refer to one timer or script at a time. Creating a new tagged task
  with an existing tag cancels the previous owner.
- In `every`, a number in the third position is always a `count`. Pass a numeric
  tag in the fifth position; string, table, boolean, and function tags can use
  the convenience third position.
- Handles returned by `after`, `every`, `during`, `tween`, and `script` are also
  accepted by control functions.
- Same-frame callbacks run in registration order. Do not rely on any previous
  hash-table order; v1 had no ordering guarantee.
- Cancelling a task from inside its own callback prevents its completion callback
  from running. This also applies to `every` when its count is exhausted.

### Easing

Built-in families: `linear`, `quad`, `cubic`, `sine`, `expo`, and `back`, with
`in`, `out`, and `inout` variants. Names are case-insensitive and ignore
non-letter characters, and the direction may appear before or after the family:

```lua
timer.tween(1, object, { x = 10 }, "quadinout")
timer.tween(1, object, { x = 10 }, "in-out-quad")
timer.tween(1, object, { x = 10 }, "easeInOutQuad")
timer.tween(1, object, { x = 10 }, "backOut")
timer.tween(1, object, { x = 10 }, function(t) return t * t end)
```

Register reusable custom easings:

```lua
timer.registerEasing("smoothstep", function(t)
  return t * t * (3 - 2 * t)
end)

timer.tween(1, object, { x = 10 }, "smoothstep")
```

### Errors and edge cases

- `update` requires a finite `dt >= 0`.
- Delays must be finite and non-negative; `every` ranges must satisfy
  `0 <= min <= max`.
- `count` must be a finite number `>= 0` or `nil`.
- Unknown easings and malformed tables raise immediately.
- A user callback error propagates out of `update`; callbacks later in that
  frame do not run. The pool remains usable on the next update.
- Do not call `update` recursively from a callback; advance the pool from a
  single frame loop.
- `timer.after(0, ...)`, `timer.during(0, ...)`, zero-duration tweens, and
  `wait(0)` complete on the next `update` call rather than synchronously.
- Completion callbacks run after the task has been removed and its tag cleared,
  so they may safely register a new task with the same tag.

## Migration from v1

The complete upgrade guide is in [MIGRATION.md](MIGRATION.md); release notes are
in [CHANGELOG.md](CHANGELOG.md). The main changes:

- The canonical module is `timer.lua`; `require 'init'` still works through the
  shim.
- Invalid durations, easing names, and callbacks now raise at creation.
- Script errors and invalid waits are no longer swallowed.
- Script/public-tag collisions are fixed; internal waits are private tasks.
- Completion callbacks do not run after self-cancellation.
- Callback order is now insertion order.

## Development

Install the test and lint tools with `luarocks install busted` and
`luarocks install luacheck`; install [StyLua](https://github.com/JohnnyMorganz/StyLua)
for formatting.

```sh
busted spec
busted --lua=luajit spec
busted --lua=lua5.2 spec
busted --lua=lua5.3 spec
busted --lua=lua5.4 spec
```

`make test`, `make test-all`, `make lint`, and `make fmt` are provided as
shortcuts. The LÖVR demo can be run with `lovr .` from the repository root.

## Credits

The original design is inspired by [HUMP](https://github.com/vrld/hump)'s timer
by Matthias Richter. See [LICENSE](LICENSE) for the license covering this
project and [NOTICE](NOTICE) for upstream attribution.
