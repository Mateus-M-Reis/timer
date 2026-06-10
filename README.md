# Timer

A robust, lightweight, object-oriented time-management and tweening utility library optimized for LÖVE and LÖVR.

Built upon the legacy of HUMP's `timer.lua`, this version represents an architectural evolution designed to handle high-performance game loops, prevent execution collisions via tag-based cancellation, and eliminate string-parsing runtime crashes entirely.

## 🚀 Key Features

* **Object-Oriented & Global Instancing:** Use the out-of-the-box global timer for rapid prototyping, or create distinct local timer pools natively (`timer.new()`) to tie timers directly to entity lifecycles.
* **Tag-Based Control:** Overwrite active intervals or animations on the fly simply by assigning custom string tags—bypassing the need to store and track arbitrary reference handles.
* **Native Range Randomization:** Pass range arrays like `{0.2, 0.5}` directly into your execution methods to effortlessly introduce organic, non-uniform interval spacing.
* **Sequential Scripts:** Leverage Lua coroutines to write complex, asynchronous cutscenes or timed behavior trees in a single, readable block of code.
* **Zero-Crash Easing Engine:** Utilizes a pre-compiled $O(1)$ dictionary lookup matching all common string formatting styles (`quadinout`, `in-out-quad`, `backOut`, etc.).

---

## 🛠️ Quick Start

Drop `timer.lua` into your project and initialize it within your main loop. You can use the default global instance, or create a local one.

```lua
local timer = require 'lib.timer'

function lovr.update(dt)
    -- Updates all globally scheduled timers, tweens, and scripts
    timer.update(dt)
end

```

---

## 📖 API Reference

### Core Management

#### `timer.update(dt)`

Updates the active timer instance registry. It must be called once every frame inside your update loop.

* **`dt`** *(number)*: Delta time since the last frame.

#### `timer.cancel(handle_or_tag)`

Immediately halts and purges any scheduled timer, loop, tween, or script matching the specified tag identifier or handle.

* **`handle_or_tag`** *(any)*: The string tag or table reference of the task to cancel.

#### `timer.clear()`

Completely wipes clean all pending jobs, intervals, and active tweens from the instance table pool.

---

### Scheduling & Intervals

#### `timer.after(delay, action, [tag])`

Executes a callback function after a specified delay period.

* **`delay`** *(number)*: Duration to wait in seconds.
* **`action`** *(function)*: Callback executed when the timer finishes.
* **`tag`** *(any, optional)*: Identifier string/object used to uniquely track or cancel the task. If a new task is fired with an active tag, the old one is automatically discarded.

#### `timer.every(delay, action, [count], [after], [tag])`

Creates a recurring loop that fires an action sequentially.

* **`delay`** *(number | table)*: Interval in seconds. **New:** Pass a list value `{min, max}` to automatically randomize the delay time between every loop cycle.
* **`action`** *(function)*: Callback executed every interval cycle.
* **`count`** *(number, optional)*: Maximum execution count before terminating. Pass `0` or `nil` for an endless interval.
* **`after`** *(function, optional)*: Callback executed the exact moment the total execution limit is reached.
* **`tag`** *(any, optional)*: Tracking identifier.

#### `timer.during(delay, action, [after], [tag])`

Fires an update callback continuously *every frame* during an active timeframe window.

* **`delay`** *(number)*: Active timeframe duration window in seconds.
* **`action`** *(function)*: Frame-by-frame callback loop.
* **`after`** *(function, optional)*: Callback triggered once when the sequence times out.
* **`tag`** *(any, optional)*: Tracking identifier.

---

### Interpolation

#### `timer.tween(delay, target, payload, [method], [after], [tag])`

Smoothly interpolates properties within a targeted table container over an explicit timeframe.

* **`delay`** *(number)*: Animation duration window in seconds.
* **`target`** *(table)*: The reference object containing values to manipulate.
* **`payload`** *(table)*: Target state keys matched to destination numeric endpoints (e.g., `{ x = 100, y = 50 }`).
* **`method`** *(string, optional)*: Easing equation keyword. Fully supports flexible inputs (e.g., `'quadinout'`, `'in-out-quad'`, `'linear'`). Defaults to `'linear'`.
* **`after`** *(function, optional)*: Callback executed when interpolation completes.
* **`tag`** *(any, optional)*: Tracking identifier. Highly recommended for dynamic menu items or players to completely eliminate state overlaps.

---

### Asynchronous Scripts

#### `timer.script(f, [tag])`

Executes a function as a coroutine. Inside the function, you can call `coroutine.yield(seconds)` to pause the execution of the function for a specified amount of time. This is incredibly useful for writing sequential events, cutscenes, or boss attack patterns without resorting to nested `timer.after` callbacks.

* **`f`** *(function)*: The function containing the sequence to run.
* **`tag`** *(any, optional)*: Tracking identifier. Firing a new script with the same tag will safely abort the previous sequence.

**Script Example:**

```lua
timer.script(function()
    print("Sequence starting...")
    
    -- Wait for 2 seconds
    coroutine.yield(2)
    print("Two seconds have passed!")
    
    -- Animate a menu, wait for the animation to finish
    timer.tween(1.5, menu, { alpha = 1 }, 'quadinout')
    coroutine.yield(1.5)
    
    print("Sequence complete.")
end, "intro_cutscene")

```

---

## 💡 Practical Examples

### 1. Organic Spawning (Range Randomization)

Avoid artificial, uniform patterns in gameplay logic. By feeding a table range element into an ongoing interval loop, the engine recalculates boundaries organically every round:

```lua
-- Spawns an enemy at a random interval between 0.5 and 1.5 seconds.
-- Limits the total wave to 10 enemies, then calls a wave_clear function.
timer.every({0.5, 1.5}, spawn_enemy, 10, wave_clear, "spawner_loop")

```

### 2. Safeguarded Overwriting (Tagging)

Using tags eliminates the need to capture return references to handle user interaction interrupts securely:

```lua
function Player:shoot()
    -- Flash white
    self.color = {1, 1, 1}
    
    -- Automatically overwrites any existing "color_reset" timer 
    -- if the player shoots again before the 0.1s is up. No overlapping bugs!
    timer.after(0.1, function()
        self.color = {1, 0, 0}
    end, "color_reset")
end

```
