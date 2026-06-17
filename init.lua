---@class TimerTask
---@field type string The type of task (after, every, during, tween)
---@field time number The current accumulated time
---@field limit number The time limit/delay configured
---@field action? function The main function to be executed
---@field after_action? function The function to be executed upon completion (for during/every/tween)
---@field target? table The target table of the tween
---@field payload? table The processed start/target values of the tween
---@field easing? function The easing function
---@field tag? any The unique identification tag
---@field count? number Maximum number of iterations remaining (for every)
---@field range? table The {min, max} table for randomized intervals (for every)

---@class TimerInstance
---@field tasks table<TimerTask, boolean>
---@field tags table<any, TimerTask>
local Timer = {}; Timer.__index = Timer

-- Fast O(1) dictionary for tween easings
local easings = {
  linear = function(t) return t end,

  -- Quad
  quadin = function(t) return t * t end,
  quadout = function(t) return t * (2 - t) end,
  quadinout = function(t) return t < 0.5 and 2 * t * t or -1 + (4 - 2 * t) * t end,

  -- Cubic
  cubicin = function(t) return t * t * t end,
  cubicout = function(t) t = t - 1; return t * t * t + 1 end,
  cubicinout = function(t) t = t * 2; if t < 1 then return 0.5 * t * t * t end; t = t - 2; return 0.5 * (2 + t * t * t) end,

  -- Sine
  sinein = function(t) return 1 - math.cos(t * math.pi / 2) end,
  sineout = function(t) return math.sin(t * math.pi / 2) end,
  sineinout = function(t) return -0.5 * (math.cos(math.pi * t) - 1) end,

  -- Expo
  expoin = function(t) return t == 0 and 0 or 2^(10 * (t - 1)) end,
  expoout = function(t) return t == 1 and 1 or 1 - 2^(-10 * t) end,
  expoinout = function(t)
    if t == 0 then return 0 end
    if t == 1 then return 1 end
    t = t * 2
    if t < 1 then return 0.5 * 2^(10 * (t - 1)) end
    return 0.5 * (2 - 2^(-10 * (t - 1)))
  end,

  -- Back
  backin = function(t) local s = 1.70158; return t * t * ((s + 1) * t - s) end,
  backout = function(t) local s = 1.70158; t = t - 1; return t * t * ((s + 1) * t + s) + 1 end,
  backinout = function(t)
    local s = 1.70158 * 1.525
    t = t * 2
    if t < 1 then return 0.5 * (t * t * ((s + 1) * t - s)) end
    t = t - 2
    return 0.5 * (t * t * ((s + 1) * t + s) + 2)
  end
}

--- Instantiates a new local timer pool
---@return TimerInstance
function Timer.new()
  return setmetatable({
    tasks = {},
    tags = {}
  }, Timer)
end

---@param dt number Frame delta time
function Timer:update(dt)
  -- Iterate over a copy to allow safe removal/addition during the loop
  local to_update = {}
  for task in pairs(self.tasks) do to_update[task] = true end

  for task in pairs(to_update) do
    if self.tasks[task] then
      -- Only update if the task is NOT paused
      if not task.paused then
        task.time = task.time + dt

        if task.type == "after" then
          if task.time >= task.limit then
            self:cancel(task)
            task.action()
          end
        elseif task.type == "every" then
          if task.time >= task.limit then
            task.time = task.time - task.limit

            -- Recalculate randomized interval limit if range is present
            if task.range then
              task.limit = math.random() * (task.range[2] - task.range[1]) + task.range[1]
            end

            local continue_loop = task.action()

            if task.count then
              task.count = task.count - 1
              if task.count <= 0 then
                self:cancel(task)
                if task.after_action then
                  task.after_action()
                end
                continue_loop = false
              end
            end

            if continue_loop == false then
              self:cancel(task)
            end
          end
        elseif task.type == "during" then
          task.action(dt)
          if task.time >= task.limit then
            self:cancel(task)
            if task.after_action then
              task.after_action()
            end
          end
        elseif task.type == "tween" then
          local t = math.min(task.time / task.limit, 1)
          local e = task.easing(t)
          for key, vals in pairs(task.payload) do
            task.target[key] = vals.start + (vals.target - vals.start) * e
          end
          if t == 1 then
            self:cancel(task)
            if task.after_action then
              task.after_action()
            end
          end
        end
      end
    end
  end
end

--- Cancels an active timer by its tag or task reference
---@param handle_or_tag any Can be a string tag or the timer table itself
function Timer:cancel(handle_or_tag)
  if not handle_or_tag then return end
  local task = self.tags[handle_or_tag] or handle_or_tag
  if self.tasks[task] then
    self.tasks[task] = nil
    if task.tag then
      self.tags[task.tag] = nil
    end
  end
end

--- Clears all active timers and tags in this pool
function Timer:clear()
  self.tasks = {}
  self.tags = {}
end

--- Pauses an active timer or animation by its tag or reference
---@param handle_or_tag any
function Timer:pause(handle_or_tag)
  if not handle_or_tag then return end
  local task = self.tags[handle_or_tag] or handle_or_tag
  if self.tasks[task] then
    task.paused = true
  end
end

--- Resumes a paused timer or animation by its tag or reference
---@param handle_or_tag any
function Timer:resume(handle_or_tag)
  if not handle_or_tag then return end
  local task = self.tags[handle_or_tag] or handle_or_tag
  if self.tasks[task] then
    task.paused = false
  end
end

--- Executes a function once after a specified delay
---@param delay number
---@param action function
---@param tag? any
---@return TimerTask
function Timer:after(delay, action, tag)
  if tag then self:cancel(tag) end
  local task = { type = "after", time = 0, limit = delay, action = action, tag = tag }
  self.tasks[task] = true
  if tag then self.tags[tag] = task end
  return task
end

--- Executes a function repeatedly at set intervals
---@param delay number|table Can be a fixed number or a {min, max} table range
---@param action function
---@param count? number Maximum execution cycles before terminating
---@param after_action? function Callback executed when count reaches zero
---@param tag? any
---@return TimerTask
function Timer:every(delay, action, count, after_action, tag)
  -- Shift arguments if 'count' or 'after_action' are omitted but 'tag' is supplied as a string/object
  if type(count) == "string" or type(count) == "table" then
    tag = count
    count = nil
    after_action = nil
  elseif type(after_action) == "string" or type(after_action) == "table" then
    tag = after_action
    after_action = nil
  end

  if tag then self:cancel(tag) end

  local initial_delay = 0
  local range_data = nil

  if type(delay) == "table" then
    range_data = delay
    initial_delay = math.random() * (delay[2] - delay[1]) + delay[1]
  else
    initial_delay = delay
  end

  local task = {
    type = "every",
    time = 0,
    limit = initial_delay,
    action = action,
    count = count and count > 0 and count or nil,
    after_action = after_action,
    range = range_data,
    tag = tag
  }

  self.tasks[task] = true
  if tag then self.tags[tag] = task end
  return task
end

--- Executes a function every frame for a specified duration
---@param delay number
---@param action function
---@param after_action? function
---@param tag? any
---@return TimerTask
function Timer:during(delay, action, after_action, tag)
  if tag then self:cancel(tag) end
  local task = { type = "during", time = 0, limit = delay, action = action, after_action = after_action, tag = tag }
  self.tasks[task] = true
  if tag then self.tags[tag] = task end
  return task
end

--- Smoothly interpolates values in a table over time
---@param delay number
---@param target table The table containing the values to animate
---@param payload table The desired final values
---@param method? string E.g., 'linear', 'quadout', 'quadinout'
---@param after_action? function
---@param tag? any
---@return TimerTask
function Timer:tween(delay, target, payload, method, after_action, tag)
  if tag then self:cancel(tag) end

  local parsed_payload = {}
  for k, v in pairs(payload) do
    parsed_payload[k] = { start = target[k] or 0, target = v }
  end

  local task = {
    type = "tween",
    time = 0,
    limit = delay,
    target = target,
    payload = parsed_payload,
    easing = easings[method or "linear"] or easings.linear,
    after_action = after_action,
    tag = tag
  }

  self.tasks[task] = true
  if tag then self.tags[tag] = task end
  return task
end

--- Runs a coroutine providing a custom 'wait' function for sequencing
---@param f function Function using wait(delay)
---@param tag? any
function Timer:script(f, tag)
  if tag then self:cancel(tag) end

  local co

  -- This is the 'wait' function injected into the coroutine
  local function wait(delay)
    return coroutine.yield(delay)
  end

  co = coroutine.create(f)

  local function step()
    -- Pass the 'wait' function as an argument on resume to fill the f(wait) parameter
    local ok, delay_time = coroutine.resume(co, wait)

    if ok and delay_time and coroutine.status(co) ~= "dead" then
      self:after(delay_time, step, tag)
    end
  end

  step()
end

-------------------------------------------------------------------------------
-- Global Instance (Module Export)
-------------------------------------------------------------------------------

---@class TimerModule
local default_timer = Timer.new()
local M = {}

--- Allows instantiating independent local timer pools
M.new = Timer.new

--- The main update loop. Place this inside lovr.update(dt) in main.lua
---@param dt number
function M.update(dt) return default_timer:update(dt) end

--- Clears all active global timers and tags
function M.clear() return default_timer:clear() end

--- Cancels an active global timer by its tag or reference
---@param handle_or_tag any
function M.cancel(handle_or_tag) return default_timer:cancel(handle_or_tag) end

--- Pauses an active global timer or animation by its tag or reference
---@param handle_or_tag any
function M.pause(handle_or_tag) return default_timer:pause(handle_or_tag) end

--- Resumes a paused global timer or animation by its tag or reference
---@param handle_or_tag any
function M.resume(handle_or_tag) return default_timer:resume(handle_or_tag) end

--- Executes a function once after a specified delay
---@param delay number
---@param action function
---@param tag? any
---@return TimerTask
function M.after(delay, action, tag) return default_timer:after(delay, action, tag) end

--- Executes a function repeatedly at set intervals
---@param delay number|table
---@param action function
---@param count? number
---@param after_action? function
---@param tag? any
---@return TimerTask
function M.every(delay, action, count, after_action, tag) return default_timer:every(delay, action, count, after_action, tag) end

--- Executes a function every frame for a specified duration
---@param delay number
---@param action function
---@param after_action? function
---@param tag? any
---@return TimerTask
function M.during(delay, action, after_action, tag) return default_timer:during(delay, action, after_action, tag) end

--- Smoothly interpolates values in a table over time
---@param delay number
---@param target table
---@param payload table
---@param method? string
---@param after_action? function
---@param tag? any
---@return TimerTask
function M.tween(delay, target, payload, method, after_action, tag) return default_timer:tween(delay, target, payload, method, after_action, tag) end

--- Runs a coroutine providing a custom 'wait' function for sequencing
---@param f function
---@param tag? any
function M.script(f, tag) return default_timer:script(f, tag) end

return M
