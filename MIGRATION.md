# Migrating from Timer v1 to v2

Timer v2 is intentionally source-compatible with the v1 positional API for
normal use. Most projects only need the require-path update. The rest of this
guide covers behaviour changes that can surface in edge cases, especially around
scripts, invalid input, and cancellation.

## Quick checklist

1. Prefer `require 'timer'`; keep `init.lua` only if you still need
   `require 'init'`.
2. Sanitise computed durations before passing them to the library.
3. Replace unsupported or misspelled easing names with supported aliases or a
   custom easing.
4. Audit scripts that relied on errors or `wait(nil)` being ignored.
5. Audit completion callbacks that were expected to run after self-cancellation.
6. Stop reading `timer.tasks` directly if you were doing so.
7. Run your test suite and the included `busted` specs on your Lua runtime.

## 1. Module path

The canonical implementation moved from `init.lua` to `timer.lua`.

```lua
-- v1
local timer = require 'init'

-- v2 (recommended)
local timer = require 'timer'
```

`init.lua` is now:

```lua
return require 'timer'
```

If you vendor only a single file, vendor `timer.lua`. If your project still
requires `'init'`, vendor both files. If you previously renamed `init.lua` to
`timer.lua` by hand, your require path already continues to work.

The global instance, `timer.new()`, and all method names are unchanged.

## 2. Invalid input now fails at the call site

v1 accepted values and often failed much later inside `update` with an error such
as “attempt to compare nil with number”. v2 validates at creation.

These now raise immediately:

- non-numeric, negative, NaN, or infinite delays and durations;
- invalid `{min, max}` ranges (`min > max`, missing entries, negative entries);
- non-function actions and completion callbacks;
- non-table tween targets/payloads;
- negative or non-numeric execution counts;
- unknown easing names;
- negative, NaN, or infinite `dt` in `update`;
- negative or non-numeric time scales.

Example:

```lua
-- v1: created a timer that crashed later or never fired
timer.after(remaining_time, finish)

-- v2: either fix the source, or clamp deliberately
remaining_time = math.max(0, remaining_time)
if remaining_time ~= remaining_time then
  remaining_time = 0
end
timer.after(remaining_time, finish)
```

If you have data-driven durations, add a small helper:

```lua
local function safe_duration(value, fallback)
  if type(value) ~= "number" or value ~= value or value < 0 then
    return fallback or 0
  end
  return value
end
```

This is the single most likely source of upgrade errors.

## 3. Easing names

v1 silently fell back to `linear` for any unrecognised name. v2:

- accepts all the documented v1 names;
- normalises case, dashes, underscores, and spaces;
- accepts the direction before or after the family;
- accepts a function directly;
- raises for names it cannot resolve.

All of these now resolve to the same easing:

```lua
timer.tween(1, object, { x = 10 }, "quadinout")
timer.tween(1, object, { x = 10 }, "quad-in-out")
timer.tween(1, object, { x = 10 }, "in-out-quad")
timer.tween(1, object, { x = 10 }, "easeInOutQuad")
```

`backOut`, `in-out-cubic`, `sineInOut`, and similar combinations are accepted.
Built-in families are `linear`, `quad`, `cubic`, `sine`, `expo`, and `back`.
The earlier README mentioned "all common styles"; elastic, bounce, quart, and
quint were never implemented. If you used one of those names expecting linear,
you now need to either use a built-in family or register the function:

```lua
timer.registerEasing("bounceOut", function(t)
  -- your implementation
  return t
end)
```

Function easings are also accepted directly:

```lua
timer.tween(1, object, { x = 10 }, function(t)
  return t * t
end)
```

## 4. Scripts

### Errors now propagate

v1 discarded `coroutine.resume` errors, which made a typo in a cutscene look like
a script that simply stopped. v2 re-throws them with a traceback.

```lua
timer.script(function(wait)
  wait(1)
  error("this is no longer silent")
end)

-- This now raises. If your game loop should survive callback errors, handle it
-- at the boundary:
local ok, err = xpcall(function()
  timer.update(dt)
end, debug.traceback)

if not ok then
  print(err)
  -- decide whether to clear/restart the pool
end
```

A script error removes the script and its pending wait before propagating, so
the pool remains usable on the next update.

### `wait` requires a valid duration

```lua
-- v1: silently abandoned the coroutine
wait(nil)

-- v2: raises "wait() expects a finite number >= 0"
wait(nil)

-- v2: explicit zero is valid and completes on the next update
wait(0)
```

`wait("soon")`, `wait(-1)`, `wait(0 / 0)`, and direct `coroutine.yield(nil)` are
all errors now. Use `wait(0)` when a coroutine should yield for a frame.

### Script handles

`timer.script` now returns a handle:

```lua
local intro = timer.script(function(wait)
  wait(1)
  show_banner()
end)

timer.pause(intro)
timer.resume(intro)
timer.cancel(intro)
```

Old code that ignored the return value continues to work. Scripts created
without a tag can now be cancelled or paused individually, which was impossible
in v1.

### Script tags are no longer used for internal waits

In v1, each `wait` was scheduled as a tagged `after` using the script's public
tag. This caused two bad outcomes:

- registering a same-tag timer while the script was waiting cancelled the wait
  and froze the script forever;
- the script's next wait could cancel an unrelated same-tag timer.

v2 keeps the script registered under its public tag, but internal waits are
private, untagged tasks. Consequences:

- a new timer or script with the same tag **cancels the script** (normal tag
  replacement semantics) instead of leaving a frozen coroutine;
- script waits never cancel user tasks;
- `timer.tags[script_tag]` is now `nil`; use `timer.exists(script_tag)` or
  `timer.scripts[script_tag]` if you need to inspect the owner.

If you relied on the old accidental behaviour of a same-tag timer only pausing
the wait, migrate to the explicit script handle:

```lua
-- Instead of replacing the script's tag:
timer.pause(intro_script)
```

### Script execution starts immediately

Unchanged from v1: the first section of a script runs synchronously until its
first `wait`. Errors before that first wait now propagate from the `script` call
itself.

## 5. Completion callbacks after cancellation

v1 could still call `after_action` after a task cancelled itself, particularly:

- `every` when the action cancelled itself and `count` reached zero;
- `during` when the action cancelled itself on the final frame.

v2 checks ownership after user callbacks. If the task was cancelled, cleared, or
replaced by a same-tag task inside its own callback, its completion callback does
not run.

If you depended on the callback running anyway, call it explicitly in the action:

```lua
timer.every(0.1, function()
  if finished() then
    timer.cancel("loop")
    on_finished()
    return false
  end
end, 10, on_finished, "loop")
```

Be careful not to call the completion twice. The usual fix is to let the counter
finish naturally, or to call the cleanup exactly where you cancel.

## 6. Callback order

v1 iterated a hash set, so same-frame callback order was arbitrary and could vary
after table resizes. v2 processes an insertion-ordered array.

If two timers interact, do not rely on either the old accidental order or the new
order silently: make the dependency explicit by cancelling or starting the
second task from the first task's callback.

Task registration during an update is unchanged: new tasks start on the next
update.

## 7. Zero-duration tweens and zero-delay timers

A tween with `delay = 0` now applies its final values on the next `update` call.
In v1 this was runtime-dependent: LuaJIT happened to complete it, while PUC Lua
computed `0 / 0` and could leave the target at NaN with a permanent task.

```lua
-- v2: completes on the next update, like timer.after(0)
timer.tween(0, object, { x = 100 })
```

If you need the value applied synchronously, set it directly:

```lua
object.x = 100
```

Negative, NaN, and infinite durations are rejected instead of moving the target
backwards or never completing.

## 8. `cancel`, `pause`, and `resume` return booleans

Existing call sites that ignore the return value are unaffected. New code can do:

```lua
if not timer.cancel("missing") then
  -- nothing owned that tag
end
```

Unknown tags and handles are still no-ops. `false` is now a valid tag (v1
silently treated it as untagged).

## 9. Internal `tasks` representation changed

`timer.tasks` changed from a hash set (`tasks[task] = true`) to an ordered array
of task tables. It is internal; avoid depending on it. Use the public methods:

```lua
timer.exists(tag)
timer.remaining(tag)
timer.count()
```

The `tags` and `scripts` maps remain available for debugging, but are not part of
the stable API. No public method changed argument order.

## 10. New APIs you can adopt gradually

- `timer.exists(tag_or_handle)`
- `timer.remaining(tag_or_handle)`
- `timer.count()`
- `timer.isPaused([tag_or_handle])`
- `timer.setTimeScale(scale)` / `timer.getTimeScale()`
- `timer.pauseAll()` / `timer.resumeAll()`
- `timer.registerEasing(name, fn)`
- Script handles returned by `timer.script`
- Function easings in `timer.tween`
- The convenience form `timer.during(delay, action, "tag")`

Local pools gain the same methods:

```lua
local pool = timer.new()
pool:exists("x")
pool:remaining("x")
pool:setTimeScale(0.25)
pool:pauseAll()
```

## 11. Behaviour compatibility summary

| Area | v1 behaviour | v2 behaviour |
| --- | --- | --- |
| Module path | `require 'init'` | Works via shim; `require 'timer'` preferred |
| Invalid delays | Accepted, failed later | Raise at creation |
| Unknown easing | Silent linear | Raises at creation |
| Script error | Silently ignored | Re-thrown with traceback |
| `wait(nil)` | Script silently stalls | Raises |
| Script internal waits | Share public tag | Private untagged tasks |
| Same-tag task during script wait | Freezes script | Cancels script (tag replacement) |
| Self-cancel completion callback | Could still run | Does not run |
| Callback order | Arbitrary hash order | Registration order |
| `tween(0, ...)` | Runtime-dependent | Completes next update |
| `tasks` internals | Hash set | Ordered array |
| `cancel/pause/resume` | No return | Boolean return |
| Tag `false` | Treated as untagged | Supported |

## 12. Verifying your migration

Run the library's suite on every runtime you ship:

```sh
busted spec
busted --lua=luajit spec   # LÖVE and LÖVR
busted --lua=lua5.2 spec
busted --lua=lua5.3 spec
busted --lua=lua5.4 spec
```

Then add regression tests for the call sites that used to work by accident:

- computed durations that can be zero, negative, or NaN;
- easing names loaded from data files or user settings;
- scripts that wait on values returned by gameplay code;
- callbacks that cancel their own tag;
- tags shared by scripts and ordinary timers;
- loops that depend on two timers firing in a particular order.

If you need a staged rollout, keep both `timer.lua` and the `init.lua` shim in
your project, switch new code to `require 'timer'`, and migrate the edge cases
listed above before deleting the shim.
