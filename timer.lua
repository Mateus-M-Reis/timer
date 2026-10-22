---Timer: a small, dependency-free scheduler and tweening library.
---
---Version 2 keeps the v1 positional API while making invalid input fail at the
---call site, giving scripts a real lifecycle, and providing deterministic
---callback ordering.
---
---See README.md for usage and MIGRATION.md for the v1 -> v2 transition.

---@class TimerTask
---@field type "after"|"every"|"during"|"tween"
---@field time number Current accumulated time, in seconds.
---@field limit number Delay/interval/duration, in seconds.
---@field action? function User callback for after/every/during.
---@field after_action? function Completion callback.
---@field target? table Tween target table.
---@field payload? table Prepared tween start/target values.
---@field easing? function Resolved easing function.
---@field tag? any Public tag.
---@field count? number Remaining every() executions.
---@field range? number[] Random interval range.
---@field paused? boolean Individual pause flag.
---@field active boolean False once cancelled or completed.
---@field owner TimerInstance Pool that owns this task.

---@class TimerScript
---@field kind "script"
---@field co thread
---@field tag? any
---@field wait_task? TimerTask
---@field paused boolean
---@field cancelled boolean
---@field done boolean
---@field owner TimerInstance

---@class TimerInstance
---@field tasks TimerTask[] Insertion-ordered task array.
---@field tags table<any, TimerTask>
---@field scripts table<any, TimerScript>
---@field all_scripts table<TimerScript, boolean>
---@field active_count integer
---@field time_scale number
---@field paused boolean

local Timer = {}
Timer.__index = Timer

local VERSION = "2.0.0"

-------------------------------------------------------------------------------
-- Validation helpers
-------------------------------------------------------------------------------

---@param n any
---@return boolean
local function isFinite(n)
  return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

---@param delay any
---@param name string
---@param allow_range? boolean
local function checkDelay(delay, name, allow_range)
  if allow_range and type(delay) == "table" then
    local min, max = delay[1], delay[2]
    assert(
      isFinite(min) and isFinite(max) and min >= 0 and max >= min,
      name .. ": delay range must be {min, max} with finite 0 <= min <= max",
      3
    )
    return
  end

  assert(isFinite(delay) and delay >= 0, name .. ": delay must be a finite number >= 0", 3)
end

---@param fn any
---@param name string
local function checkAction(fn, name)
  assert(type(fn) == "function", name .. ": action must be a function", 3)
end

---@param fn any
---@param name string
local function checkOptionalAction(fn, name)
  assert(fn == nil or type(fn) == "function", name .. ": completion callback must be a function or nil", 3)
end

---NaN is not a valid Lua table key, so reject it as a tag.
---@param tag any
local function checkTag(tag)
  assert(tag == nil or tag == tag, "timer: tag cannot be NaN", 3)
end

---@param range number[]
---@return number
local function randomInRange(range)
  return range[1] + math.random() * (range[2] - range[1])
end

-------------------------------------------------------------------------------
-- Easing functions
-------------------------------------------------------------------------------

local easings = {
  linear = function(t)
    return t
  end,

  -- Quad
  quadin = function(t)
    return t * t
  end,
  quadout = function(t)
    return t * (2 - t)
  end,
  quadinout = function(t)
    return t < 0.5 and 2 * t * t or -1 + (4 - 2 * t) * t
  end,

  -- Cubic
  cubicin = function(t)
    return t * t * t
  end,
  cubicout = function(t)
    t = t - 1
    return t * t * t + 1
  end,
  cubicinout = function(t)
    t = t * 2
    if t < 1 then
      return 0.5 * t * t * t
    end
    t = t - 2
    return 0.5 * (2 + t * t * t)
  end,

  -- Sine
  sinein = function(t)
    return 1 - math.cos(t * math.pi / 2)
  end,
  sineout = function(t)
    return math.sin(t * math.pi / 2)
  end,
  sineinout = function(t)
    return -0.5 * (math.cos(math.pi * t) - 1)
  end,

  -- Expo
  expoin = function(t)
    return t == 0 and 0 or 2 ^ (10 * (t - 1))
  end,
  expoout = function(t)
    return t == 1 and 1 or 1 - 2 ^ (-10 * t)
  end,
  expoinout = function(t)
    if t == 0 then
      return 0
    end
    if t == 1 then
      return 1
    end
    t = t * 2
    if t < 1 then
      return 0.5 * 2 ^ (10 * (t - 1))
    end
    return 0.5 * (2 - 2 ^ (-10 * (t - 1)))
  end,

  -- Back
  backin = function(t)
    local s = 1.70158
    return t * t * ((s + 1) * t - s)
  end,
  backout = function(t)
    local s = 1.70158
    t = t - 1
    return t * t * ((s + 1) * t + s) + 1
  end,
  backinout = function(t)
    local s = 1.70158 * 1.525
    t = t * 2
    if t < 1 then
      return 0.5 * (t * t * ((s + 1) * t - s))
    end
    t = t - 2
    return 0.5 * (t * t * ((s + 1) * t + s) + 2)
  end,
}

-- Normalised aliases, rebuilt when a custom easing is registered.
-- Examples: "in-out-quad", "InOutQuad", "easeInOutQuad" -> "quadinout".
local easing_aliases = {}

local function rebuildEasingAliases()
  easing_aliases = {}
  for name in pairs(easings) do
    easing_aliases[name] = name
    local family, mode = name:match("^(.-)(inout)$")
    if not family then
      family, mode = name:match("^(.-)(in)$")
    end
    if not family then
      family, mode = name:match("^(.-)(out)$")
    end
    if family and family ~= "" then
      easing_aliases[mode .. family] = name
      easing_aliases["ease" .. mode .. family] = name
    end
  end
end

rebuildEasingAliases()

---@param method? string|function
---@return function
local function resolveEasing(method)
  if type(method) == "function" then
    return method
  end
  if method == nil then
    return easings.linear
  end
  if type(method) ~= "string" then
    error("timer.tween: easing must be a string or function, got " .. type(method), 3)
  end

  local key = method:lower():gsub("[^%a]", "")
  local canonical = easing_aliases[key]
  local fn = easings[key] or (canonical and easings[canonical])
  if not fn then
    error("timer.tween: unknown easing '" .. tostring(method) .. "'", 3)
  end
  return fn
end

---Registers a custom easing name. The name is normalised the same way as
---built-in names ("in-out-quad" and "quadinout" are equivalent).
---@param name string
---@param fn fun(t: number): number
function Timer.registerEasing(name, fn)
  assert(type(name) == "string" and name ~= "", "timer.registerEasing: name must be a non-empty string", 2)
  assert(type(fn) == "function", "timer.registerEasing: fn must be a function", 2)

  local key = name:lower():gsub("[^%a]", "")
  assert(key ~= "", "timer.registerEasing: name must contain letters", 2)
  local canonical = easing_aliases[key]
  assert(
    easings[key] == nil and (canonical == nil or easings[canonical] == nil),
    "timer.registerEasing: '" .. name .. "' is already registered",
    2
  )

  easings[key] = fn
  rebuildEasingAliases()
  return fn
end

-------------------------------------------------------------------------------
-- Internal task/script management
-------------------------------------------------------------------------------

---@param self TimerInstance
---@param task TimerTask
---@return TimerTask
local function appendTask(self, task)
  task.time = 0
  task.active = true
  task.paused = false
  task.owner = self
  self.tasks[#self.tasks + 1] = task
  self.active_count = self.active_count + 1
  if task.tag ~= nil then
    self.tags[task.tag] = task
  end
  return task
end

---@param self TimerInstance
---@param task any
---@return boolean cancelled
local function cancelTask(self, task)
  if type(task) ~= "table" or task.owner ~= self or task.active ~= true then
    return false
  end

  task.active = false
  self.active_count = self.active_count - 1
  if task.tag ~= nil and self.tags[task.tag] == task then
    self.tags[task.tag] = nil
  end
  return true
end

---@param self TimerInstance
---@param script TimerScript
local function detachScript(self, script)
  if script.done then
    return
  end

  script.done = true
  script.wait_task = nil
  self.all_scripts[script] = nil
  if script.tag ~= nil and self.scripts[script.tag] == script then
    self.scripts[script.tag] = nil
  end
end

---@param self TimerInstance
---@param script TimerScript
---@return boolean cancelled
local function cancelScript(self, script)
  if script.owner ~= self or script.done or script.cancelled then
    return false
  end

  script.cancelled = true
  local wait_task = script.wait_task
  script.wait_task = nil
  if wait_task then
    cancelTask(self, wait_task)
  end
  detachScript(self, script)
  return true
end

---@param script TimerScript
---@return boolean
local function pauseScript(script)
  if script.done or script.cancelled then
    return false
  end

  script.paused = true
  if script.wait_task and script.wait_task.active then
    script.wait_task.paused = true
  end
  return true
end

---@param script TimerScript
---@return boolean
local function resumeScript(script)
  if script.done or script.cancelled then
    return false
  end

  script.paused = false
  if script.wait_task and script.wait_task.active then
    script.wait_task.paused = false
  end
  return true
end

---Resolves a public tag or handle to a task/script table.
---@param self TimerInstance
---@param handle_or_tag any
---@return any
local function findTarget(self, handle_or_tag)
  if handle_or_tag == nil or handle_or_tag ~= handle_or_tag then
    return nil
  end

  local target = self.tags[handle_or_tag]
  if target then
    return target
  end

  target = self.scripts[handle_or_tag]
  if target then
    return target
  end

  return handle_or_tag
end

-------------------------------------------------------------------------------
-- Instance construction and update loop
-------------------------------------------------------------------------------

---Creates an independent timer pool.
---@return TimerInstance
function Timer.new()
  return setmetatable({
    tasks = {},
    tags = {},
    scripts = {},
    all_scripts = {},
    active_count = 0,
    time_scale = 1,
    paused = false,
  }, Timer)
end

---Advances every active task. Tasks cancelled/added by callbacks are handled
---safely; callbacks run in registration order for tasks present at frame start.
---@param dt number Delta time in seconds (finite and >= 0).
function Timer:update(dt)
  assert(isFinite(dt) and dt >= 0, "timer.update: dt must be a finite number >= 0", 2)
  if self.paused then
    return
  end

  local scaled_dt = dt * self.time_scale
  local tasks = self.tasks
  local count = #tasks

  -- `count` is captured now so tasks registered during callbacks start next frame.
  for i = 1, count do
    -- pauseAll() from an earlier callback should stop the remainder of this frame.
    if self.paused then
      break
    end

    local task = tasks[i]
    if task.active and not task.paused then
      task.time = task.time + scaled_dt

      if task.type == "after" then
        if task.time >= task.limit then
          cancelTask(self, task)
          task.action()
        end
      elseif task.type == "every" then
        if task.time >= task.limit then
          task.time = task.time - task.limit
          if task.range then
            task.limit = randomInRange(task.range)
          end

          local continue_loop = task.action()

          -- The action may have cancelled itself, cleared the pool, or replaced
          -- its tag. In those cases its completion logic must not run.
          if task.active then
            if task.count then
              task.count = task.count - 1
              if task.count <= 0 then
                cancelTask(self, task)
                if task.after_action then
                  task.after_action()
                end
                continue_loop = false
              end
            end

            if continue_loop == false then
              cancelTask(self, task)
            end
          end
        end
      elseif task.type == "during" then
        task.action(scaled_dt)
        if task.active and task.time >= task.limit then
          cancelTask(self, task)
          if task.after_action then
            task.after_action()
          end
        end
      elseif task.type == "tween" then
        -- A zero-duration tween completes on its first update. Avoid 0/0,
        -- which produces NaN on PUC Lua and is runtime-dependent elsewhere.
        local t = task.limit > 0 and math.min(task.time / task.limit, 1) or 1
        if t == 1 then
          -- Snap to the requested endpoints, avoiding floating-point residue.
          for key, values in pairs(task.payload) do
            task.target[key] = values.target
          end
          cancelTask(self, task)
          if task.after_action then
            task.after_action()
          end
        else
          local e = task.easing(t)
          for key, values in pairs(task.payload) do
            task.target[key] = values.start + (values.target - values.start) * e
          end
        end
      end
    end
  end

  -- Compact tombstones without paying an O(n) rebuild every frame.
  local total = #self.tasks
  local dead = total - self.active_count
  if dead > 0 and (self.active_count == 0 or dead >= 64 or dead * 2 >= total) then
    local active_tasks = {}
    for i = 1, total do
      local task = self.tasks[i]
      if task.active then
        active_tasks[#active_tasks + 1] = task
      end
    end
    self.tasks = active_tasks
  end
end

-------------------------------------------------------------------------------
-- Core management
-------------------------------------------------------------------------------

---Cancels a task/script by tag or handle.
---@param handle_or_tag any
---@return boolean cancelled
function Timer:cancel(handle_or_tag)
  local target = findTarget(self, handle_or_tag)
  if type(target) ~= "table" then
    return false
  end
  if target.kind == "script" then
    return cancelScript(self, target)
  end
  return cancelTask(self, target)
end

---Pauses a task/script by tag or handle.
---@param handle_or_tag any
---@return boolean paused
function Timer:pause(handle_or_tag)
  local target = findTarget(self, handle_or_tag)
  if type(target) ~= "table" then
    return false
  end
  if target.kind == "script" then
    if target.owner ~= self then
      return false
    end
    return pauseScript(target)
  end
  if target.owner ~= self or not target.active then
    return false
  end
  target.paused = true
  return true
end

---Resumes a task/script by tag or handle.
---@param handle_or_tag any
---@return boolean resumed
function Timer:resume(handle_or_tag)
  local target = findTarget(self, handle_or_tag)
  if type(target) ~= "table" then
    return false
  end
  if target.kind == "script" then
    if target.owner ~= self then
      return false
    end
    return resumeScript(target)
  end
  if target.owner ~= self or not target.active then
    return false
  end
  target.paused = false
  return true
end

---Returns whether a pool (no argument) or a specific task/script is paused.
---@param handle_or_tag? any
---@return boolean
function Timer:isPaused(handle_or_tag)
  if handle_or_tag == nil then
    return self.paused
  end

  local target = findTarget(self, handle_or_tag)
  if type(target) ~= "table" then
    return false
  end
  if target.kind == "script" then
    if target.owner ~= self or target.done or target.cancelled then
      return false
    end
    return self.paused or target.paused
  end
  if target.owner ~= self or not target.active then
    return false
  end
  return self.paused or target.paused
end

---Returns whether a task/script is still active.
---@param handle_or_tag any
---@return boolean
function Timer:exists(handle_or_tag)
  local target = findTarget(self, handle_or_tag)
  if type(target) ~= "table" then
    return false
  end
  if target.kind == "script" then
    return target.owner == self and not target.done and not target.cancelled
  end
  return target.owner == self and target.active == true
end

---Returns seconds left for the next event of a task/script, or nil.
---For scripts this is the remaining wait; for `every` it is time to the next tick.
---@param handle_or_tag any
---@return number?
function Timer:remaining(handle_or_tag)
  local target = findTarget(self, handle_or_tag)
  if type(target) ~= "table" then
    return nil
  end

  if target.kind == "script" then
    if target.owner ~= self then
      return nil
    end
    target = target.wait_task
  end
  if type(target) ~= "table" or target.owner ~= self or not target.active then
    return nil
  end

  local remaining = target.limit - target.time
  return remaining > 0 and remaining or 0
end

---Number of active scheduled tasks (including internal script waits).
---@return integer
function Timer:count()
  return self.active_count
end

---Clears every task, tag, and script in this pool.
function Timer:clear()
  local tasks = self.tasks
  for i = 1, #tasks do
    tasks[i].active = false
  end

  for script in pairs(self.all_scripts) do
    script.cancelled = true
    script.done = true
    script.wait_task = nil
  end

  self.tasks = {}
  self.tags = {}
  self.scripts = {}
  self.all_scripts = {}
  self.active_count = 0
end

---Sets a pool-wide time multiplier. 1 is normal speed, 0 freezes time.
---@param scale number
function Timer:setTimeScale(scale)
  assert(isFinite(scale) and scale >= 0, "timer.setTimeScale: scale must be a finite number >= 0", 2)
  self.time_scale = scale
  return true
end

---@return number
function Timer:getTimeScale()
  return self.time_scale
end

---Freezes the whole pool without touching individual task pause flags.
function Timer:pauseAll()
  self.paused = true
  return true
end

---Undoes pauseAll().
function Timer:resumeAll()
  self.paused = false
  return true
end

-------------------------------------------------------------------------------
-- Scheduling
-------------------------------------------------------------------------------

---Runs a callback once after `delay` seconds.
---@param delay number
---@param action fun()
---@param tag? any
---@return TimerTask
function Timer:after(delay, action, tag)
  checkDelay(delay, "timer.after")
  checkAction(action, "timer.after")
  checkTag(tag)
  if tag ~= nil then
    self:cancel(tag)
  end

  return appendTask(self, {
    type = "after",
    limit = delay,
    action = action,
    tag = tag,
  })
end

---Runs a callback every `delay` seconds (optionally a random {min, max} range).
---@param delay number|number[]
---@param action fun(): boolean|nil
---@param count? number Maximum executions; 0 or nil means infinite.
---@param after_action? fun() Called when count is exhausted.
---@param tag? any
---@return TimerTask
function Timer:every(delay, action, count, after_action, tag)
  -- Preserve v1's convenience form: every(delay, action, "tag").
  if count ~= nil and type(count) ~= "number" then
    tag = count
    count = nil
    after_action = nil
  elseif after_action ~= nil and type(after_action) ~= "function" then
    tag = after_action
    after_action = nil
  end

  checkDelay(delay, "timer.every", true)
  checkAction(action, "timer.every")
  checkOptionalAction(after_action, "timer.every")
  checkTag(tag)

  if count ~= nil then
    assert(
      type(count) == "number" and isFinite(count) and count >= 0,
      "timer.every: count must be a finite number >= 0 or nil",
      3
    )
  end

  local range
  local initial_delay = delay
  if type(delay) == "table" then
    range = { delay[1], delay[2] }
    initial_delay = randomInRange(range)
  end

  if tag ~= nil then
    self:cancel(tag)
  end

  return appendTask(self, {
    type = "every",
    limit = initial_delay,
    action = action,
    count = (count and count > 0) and count or nil,
    after_action = after_action,
    range = range,
    tag = tag,
  })
end

---Runs a callback every frame for `delay` seconds.
---@param delay number
---@param action fun(dt: number)
---@param after_action? fun()
---@param tag? any
---@return TimerTask
function Timer:during(delay, action, after_action, tag)
  -- Preserve the convenient during(delay, action, "tag") form.
  if after_action ~= nil and type(after_action) ~= "function" and tag == nil then
    tag = after_action
    after_action = nil
  end

  checkDelay(delay, "timer.during")
  checkAction(action, "timer.during")
  checkOptionalAction(after_action, "timer.during")
  checkTag(tag)
  if tag ~= nil then
    self:cancel(tag)
  end

  return appendTask(self, {
    type = "during",
    limit = delay,
    action = action,
    after_action = after_action,
    tag = tag,
  })
end

---Smoothly interpolates table values over `delay` seconds.
---@param delay number
---@param target table
---@param payload table<string, number>
---@param method? string|fun(t: number): number
---@param after_action? fun()
---@param tag? any
---@return TimerTask
function Timer:tween(delay, target, payload, method, after_action, tag)
  checkDelay(delay, "timer.tween")
  assert(type(target) == "table", "timer.tween: target must be a table", 3)
  assert(type(payload) == "table", "timer.tween: payload must be a table", 3)
  checkOptionalAction(after_action, "timer.tween")
  checkTag(tag)

  local easing = resolveEasing(method)
  local parsed_payload = {}
  for key, value in pairs(payload) do
    parsed_payload[key] = { start = target[key] or 0, target = value }
  end

  -- Resolve everything before cancelling an existing same-tag tween, so a bad
  -- call does not destroy a working animation.
  if tag ~= nil then
    self:cancel(tag)
  end

  return appendTask(self, {
    type = "tween",
    limit = delay,
    target = target,
    payload = parsed_payload,
    easing = easing,
    after_action = after_action,
    tag = tag,
  })
end

---Runs a coroutine with a `wait(seconds)` function.
---
---The returned script handle can be passed to cancel/pause/resume. Internal
---wait tasks are private to the script and are not registered under its public
---tag, so they cannot collide with user tasks.
---@param f fun(wait: fun(delay: number))
---@param tag? any
---@return TimerScript
function Timer:script(f, tag)
  assert(type(f) == "function", "timer.script: f must be a function", 2)
  checkTag(tag)
  if tag ~= nil then
    self:cancel(tag)
  end

  local co = coroutine.create(f)
  local script = {
    kind = "script",
    co = co,
    tag = tag,
    wait_task = nil,
    paused = false,
    cancelled = false,
    done = false,
    owner = self,
  }
  self.all_scripts[script] = true
  if tag ~= nil then
    self.scripts[tag] = script
  end

  local first_resume = true

  local function wait(delay)
    checkDelay(delay, "timer.script wait")
    return coroutine.yield(delay)
  end

  local step
  step = function()
    if script.cancelled or script.done then
      detachScript(self, script)
      return
    end

    -- The previous wait task has already been cancelled by update().
    script.wait_task = nil

    local ok, delay = coroutine.resume(co, first_resume and wait or nil)
    first_resume = false

    if not ok then
      detachScript(self, script)
      error(debug.traceback(co, tostring(delay)), 0)
    end

    if script.cancelled then
      detachScript(self, script)
      return
    end

    if coroutine.status(co) == "dead" then
      detachScript(self, script)
      return
    end

    if not isFinite(delay) or delay < 0 then
      detachScript(self, script)
      error("timer.script: wait() expects a finite number >= 0, got " .. tostring(delay), 0)
    end

    local wait_task = self:after(delay, step, nil)
    wait_task.paused = script.paused
    script.wait_task = wait_task
  end

  step()
  return script
end

-------------------------------------------------------------------------------
-- Global module instance
-------------------------------------------------------------------------------

local default_timer = Timer.new()
local M = {}

M._VERSION = VERSION
M.Timer = Timer
M.new = Timer.new
M.registerEasing = Timer.registerEasing

---@param dt number
function M.update(dt)
  return default_timer:update(dt)
end

function M.clear()
  return default_timer:clear()
end

---@param handle_or_tag any
function M.cancel(handle_or_tag)
  return default_timer:cancel(handle_or_tag)
end

---@param handle_or_tag any
function M.pause(handle_or_tag)
  return default_timer:pause(handle_or_tag)
end

---@param handle_or_tag any
function M.resume(handle_or_tag)
  return default_timer:resume(handle_or_tag)
end

---@param handle_or_tag? any
function M.isPaused(handle_or_tag)
  return default_timer:isPaused(handle_or_tag)
end

---@param handle_or_tag any
function M.exists(handle_or_tag)
  return default_timer:exists(handle_or_tag)
end

---@param handle_or_tag any
function M.remaining(handle_or_tag)
  return default_timer:remaining(handle_or_tag)
end

function M.count()
  return default_timer:count()
end

---@param scale number
function M.setTimeScale(scale)
  return default_timer:setTimeScale(scale)
end

function M.getTimeScale()
  return default_timer:getTimeScale()
end

function M.pauseAll()
  return default_timer:pauseAll()
end

function M.resumeAll()
  return default_timer:resumeAll()
end

---@param delay number
---@param action fun()
---@param tag? any
function M.after(delay, action, tag)
  return default_timer:after(delay, action, tag)
end

---@param delay number|number[]
---@param action fun(): boolean|nil
---@param count? number
---@param after_action? fun()
---@param tag? any
function M.every(delay, action, count, after_action, tag)
  return default_timer:every(delay, action, count, after_action, tag)
end

---@param delay number
---@param action fun(dt: number)
---@param after_action? fun()
---@param tag? any
function M.during(delay, action, after_action, tag)
  return default_timer:during(delay, action, after_action, tag)
end

---@param delay number
---@param target table
---@param payload table
---@param method? string|fun(t: number): number
---@param after_action? fun()
---@param tag? any
function M.tween(delay, target, payload, method, after_action, tag)
  return default_timer:tween(delay, target, payload, method, after_action, tag)
end

---@param f fun(wait: fun(delay: number))
---@param tag? any
function M.script(f, tag)
  return default_timer:script(f, tag)
end

return M
