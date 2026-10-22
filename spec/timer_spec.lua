package.path = "./?.lua;" .. package.path

local timer = require("timer")

local function new()
  return timer.new()
end

local function near(actual, expected, epsilon)
  epsilon = epsilon or 1e-9
  assert.is_true(
    math.abs(actual - expected) <= epsilon,
    ("expected %.12f to be within %.12f of %.12f"):format(actual, epsilon, expected)
  )
end

local function expect_error(pattern, fn)
  local ok, err = pcall(fn)
  assert.is_false(ok)
  err = tostring(err)
  assert.is_true(err:find(pattern, 1, true) ~= nil, "expected error containing '" .. pattern .. "', got: " .. err)
end

describe("timer", function()
  local t

  before_each(function()
    t = new()
  end)

  describe("after", function()
    it("fires once after the delay", function()
      local calls = 0
      t:after(1, function()
        calls = calls + 1
      end)
      t:update(0.99)
      assert.are.equal(0, calls)
      t:update(0.02)
      assert.are.equal(1, calls)
      t:update(5)
      assert.are.equal(1, calls)
    end)

    it("fires a zero-delay timer on update(0)", function()
      local fired = false
      t:after(0, function()
        fired = true
      end)
      assert.is_false(fired)
      t:update(0)
      assert.is_true(fired)
    end)

    it("can be cancelled by handle and tag", function()
      local fired = false
      local handle = t:after(1, function()
        fired = true
      end, "a")
      assert.is_true(t:exists("a"))
      assert.is_true(t:cancel(handle))
      assert.is_false(t:exists(handle))
      t:update(2)
      assert.is_false(fired)
    end)

    it("overwrites an existing task with the same tag", function()
      local first, second = 0, 0
      t:after(1, function()
        first = first + 1
      end, "tag")
      t:after(2, function()
        second = second + 1
      end, "tag")
      t:update(1)
      assert.are.equal(0, first)
      assert.are.equal(0, second)
      t:update(1)
      assert.are.equal(1, second)
    end)

    it("keeps the old task when a replacement has invalid input", function()
      local handle = t:after(1, function() end, "tag")
      expect_error("timer.after: delay must be a finite number >= 0", function()
        t:after(-1, function() end, "tag")
      end)
      assert.is_true(t:exists(handle))
    end)

    it("supports false and numeric tags", function()
      local n = 0
      t:after(0.1, function()
        n = n + 1
      end, false)
      t:after(0.1, function()
        n = n + 1
      end, 42)
      assert.is_true(t:exists(false))
      assert.is_true(t:exists(42))
      assert.is_true(t:cancel(false))
      t:update(0.1)
      assert.are.equal(1, n)
    end)
  end)

  describe("every", function()
    it("runs count times and calls the completion callback", function()
      local calls, done = 0, false
      local handle = t:every(
        0.1,
        function()
          calls = calls + 1
        end,
        3,
        function()
          done = true
        end
      )
      t:update(0.1)
      t:update(0.1)
      t:update(0.1)
      assert.are.equal(3, calls)
      assert.is_true(done)
      assert.is_false(t:exists(handle))
    end)

    it("stops when the action returns false", function()
      local calls, done = 0, false
      t:every(
        0.1,
        function()
          calls = calls + 1
          return false
        end,
        5,
        function()
          done = true
        end
      )
      t:update(0.1)
      t:update(0.1)
      assert.are.equal(1, calls)
      assert.is_false(done)
      assert.are.equal(0, t:count())
    end)

    it("accepts a {min, max} range and keeps limits inside it", function()
      local handle = t:every({ 0.5, 1.0 }, function() end)
      assert.is_true(handle.limit >= 0.5 and handle.limit <= 1.0)
      t:update(handle.limit)
      assert.is_true(handle.limit >= 0.5 and handle.limit <= 1.0)
    end)

    it("supports a tag in the third argument", function()
      local handle = t:every(0.1, function() end, "spawner")
      assert.are.equal(handle, t.tags["spawner"])
      t:cancel("spawner")
      assert.is_false(t:exists(handle))
    end)

    it("treats count 0 as infinite", function()
      local calls = 0
      t:every(0.1, function()
        calls = calls + 1
      end, 0)
      for _ = 1, 5 do
        t:update(0.1)
      end
      assert.are.equal(5, calls)
    end)

    it("fires at most once per update", function()
      local calls = 0
      t:every(0.1, function()
        calls = calls + 1
      end)
      t:update(0.35)
      assert.are.equal(1, calls)
    end)

    it("does not call after_action when the action cancelled itself", function()
      local done = false
      t:every(
        0.1,
        function()
          t:cancel("self")
        end,
        1,
        function()
          done = true
        end,
        "self"
      )
      t:update(0.1)
      assert.is_false(done)
    end)

    it("rejects malformed ranges and invalid counts", function()
      expect_error("delay range", function()
        t:every({ 0.5 }, function() end)
      end)
      expect_error("delay range", function()
        t:every({ 1, 0.5 }, function() end)
      end)
      expect_error("count must be a finite number", function()
        t:every(1, function() end, -1)
      end)
    end)
  end)

  describe("during", function()
    it("runs once per update and calls the completion callback", function()
      local frames, done = 0, false
      local handle = t:during(0.1, function()
        frames = frames + 1
      end, function()
        done = true
      end)
      t:update(0.04)
      t:update(0.04)
      assert.are.equal(2, frames)
      assert.is_false(done)
      t:update(0.04)
      assert.are.equal(3, frames)
      assert.is_true(done)
      assert.is_false(t:exists(handle))
    end)

    it("accepts a tag in the third argument", function()
      local handle = t:during(0.1, function() end, "dur")
      assert.is_true(t:exists("dur"))
      t:update(0.1)
      assert.is_false(t:exists(handle))
    end)

    it("does not call after_action after a final-frame self-cancel", function()
      local done = false
      t:during(0.1, function()
        t:cancel("d")
      end, function()
        done = true
      end, "d")
      t:update(0.1)
      assert.is_false(done)
      assert.are.equal(0, t:count())
    end)
  end)

  describe("tween", function()
    it("interpolates, finishes exactly, and calls the completion callback", function()
      local object = { x = 0, y = 10 }
      local done = false
      local handle = t:tween(1, object, { x = 100 }, "linear", function()
        done = true
      end)
      t:update(0.25)
      near(object.x, 25)
      assert.are.equal(10, object.y)
      t:update(0.75)
      near(object.x, 100)
      assert.is_true(done)
      assert.is_false(t:exists(handle))
    end)

    it("snaps to exact endpoint values at completion", function()
      local object = { x = 0.1 }
      t:tween(1, object, { x = 0.3 }, "linear")
      t:update(1)
      assert.are.equal(0.3, object.x)
    end)

    it("completes a zero-duration tween without NaN", function()
      local object = { x = 0 }
      local done = false
      t:tween(0, object, { x = 10 }, "linear", function()
        done = true
      end)
      t:update(0)
      assert.are.equal(10, object.x)
      assert.is_true(done)
      assert.are.equal(0, t:count())
    end)

    it("supports spacing, case, and prefix aliases", function()
      local a, b, c, d = { x = 0 }, { x = 0 }, { x = 0 }, { x = 0 }
      t:tween(1, a, { x = 100 }, "quadinout")
      t:tween(1, b, { x = 100 }, "in-out-quad")
      t:tween(1, c, { x = 100 }, "easeInOutQuad")
      t:tween(1, d, { x = 100 }, "quad-in-out")
      t:update(0.25)
      -- 2 * 0.25^2 * 100 = 12.5 for quad-in-out; a linear fallback would be 25.
      near(a.x, 12.5)
      near(b.x, 12.5)
      near(c.x, 12.5)
      near(d.x, 12.5)
    end)

    it("accepts function easings", function()
      local object = { x = 0 }
      t:tween(1, object, { x = 100 }, function(v)
        return v * v
      end)
      t:update(0.5)
      near(object.x, 25)
    end)

    it("accepts registered custom easings", function()
      timer.registerEasing("test-quadratic", function(v)
        return v * v
      end)
      local object = { x = 0 }
      t:tween(1, object, { x = 100 }, "test-quadratic")
      t:update(0.5)
      near(object.x, 25)
      expect_error("already registered", function()
        timer.registerEasing("test-quadratic", function(v)
          return v
        end)
      end)
    end)

    it("rejects unknown easings at creation without cancelling the old tween", function()
      local object = { x = 0 }
      local handle = t:tween(1, object, { x = 100 }, "linear", nil, "move")
      expect_error("unknown easing", function()
        t:tween(1, object, { x = 200 }, "not-an-easing", nil, "move")
      end)
      assert.is_true(t:exists(handle))
      t:update(0.5)
      near(object.x, 50)
    end)

    it("rejects invalid durations and tables", function()
      local object = { x = 0 }
      expect_error("timer.tween: delay must be a finite number >= 0", function()
        t:tween(-1, object, { x = 1 })
      end)
      expect_error("timer.tween: delay must be a finite number >= 0", function()
        t:tween(0 / 0, object, { x = 1 })
      end)
      expect_error("target must be a table", function()
        t:tween(1, 1, { x = 1 })
      end)
      expect_error("payload must be a table", function()
        t:tween(1, object, 1)
      end)
    end)

    it("starts a same-tag replacement from the current value", function()
      local object = { x = 0 }
      t:tween(1, object, { x = 100 }, "linear", nil, "move")
      t:update(0.5)
      near(object.x, 50)
      t:tween(1, object, { x = 200 }, "linear", nil, "move")
      t:update(0.5)
      near(object.x, 125)
    end)
  end)

  describe("scripts", function()
    it("sequences waits", function()
      local log = {}
      local script = t:script(function(wait)
        log[#log + 1] = "start"
        wait(1)
        log[#log + 1] = "one"
        wait(0.5)
        log[#log + 1] = "two"
      end)
      assert.are.same({ "start" }, log)
      t:update(0.5)
      assert.are.same({ "start" }, log)
      t:update(0.5)
      assert.are.same({ "start", "one" }, log)
      t:update(0.5)
      assert.are.same({ "start", "one", "two" }, log)
      assert.is_false(t:exists(script))
    end)

    it("defers wait(0) until the next update", function()
      local log = {}
      t:script(function(wait)
        log[#log + 1] = "before"
        wait(0)
        log[#log + 1] = "after"
      end)
      assert.are.same({ "before" }, log)
      t:update(0)
      assert.are.same({ "before", "after" }, log)
    end)

    it("propagates synchronous errors", function()
      local ok, err = pcall(function()
        t:script(function()
          error("sync boom")
        end)
      end)
      assert.is_false(ok)
      assert.is_true(tostring(err):find("sync boom", 1, true) ~= nil)
      assert.are.equal(0, t:count())
    end)

    it("propagates asynchronous errors and cleans up the script", function()
      local script = t:script(function(wait)
        wait(0.1)
        error("async boom")
      end, "broken")
      local ok, err = pcall(function()
        t:update(0.1)
      end)
      assert.is_false(ok)
      assert.is_true(tostring(err):find("async boom", 1, true) ~= nil)
      assert.is_false(t:exists(script))
      assert.is_false(t:exists("broken"))
      assert.are.equal(0, t:count())
    end)

    it("rejects invalid waits", function()
      expect_error("timer.script wait: delay must be a finite number >= 0", function()
        t:script(function(wait)
          wait()
        end)
      end)
      expect_error("timer.script wait: delay must be a finite number >= 0", function()
        t:script(function(wait)
          wait("soon")
        end)
      end)
      expect_error("wait() expects a finite number", function()
        t:script(function()
          coroutine.yield(nil)
        end)
      end)
    end)

    it("can be cancelled through a tagless handle", function()
      local fired = false
      local script = t:script(function(wait)
        wait(1)
        fired = true
      end)
      assert.is_true(t:exists(script))
      assert.is_true(t:cancel(script))
      t:update(2)
      assert.is_false(fired)
      assert.is_false(t:exists(script))
    end)

    it("can be paused and resumed through a handle", function()
      local fired = false
      local script = t:script(function(wait)
        wait(1)
        fired = true
      end)
      assert.is_true(t:pause(script))
      assert.is_true(t:isPaused(script))
      t:update(5)
      assert.is_false(fired)
      assert.is_true(t:resume(script))
      t:update(1)
      assert.is_true(fired)
    end)

    it("does not put internal waits into the public tag namespace", function()
      t:script(function(wait)
        wait(1)
      end, "cutscene")
      assert.is_true(t:exists("cutscene"))
      assert.is_nil(t.tags["cutscene"])
      assert.is_not_nil(t.scripts["cutscene"])
    end)

    it("is replaced cleanly by a same-tag timer", function()
      local script = t:script(function(wait)
        wait(5)
      end, "shared")
      local fired = false
      t:after(1, function()
        fired = true
      end, "shared")
      assert.is_false(t:exists(script))
      assert.is_true(t:exists("shared"))
      t:update(1)
      assert.is_true(fired)
    end)

    it("is cleared together with the rest of the pool", function()
      local fired = false
      local script = t:script(function(wait)
        wait(1)
        fired = true
      end)
      t:clear()
      t:update(10)
      assert.is_false(fired)
      assert.is_false(t:exists(script))
      assert.are.equal(0, t:count())
    end)
  end)

  describe("positional compatibility", function()
    it("accepts the full v1-style signatures", function()
      local every_calls, every_done = 0, false
      t:every(
        0.1,
        function()
          every_calls = every_calls + 1
        end,
        2,
        function()
          every_done = true
        end,
        "e"
      )
      t:update(0.1)
      t:update(0.1)
      assert.are.equal(2, every_calls)
      assert.is_true(every_done)
      assert.is_false(t:exists("e"))

      local during_done = false
      t:during(0.1, function() end, function()
        during_done = true
      end, "d")
      t:update(0.1)
      assert.is_true(during_done)
      assert.is_false(t:exists("d"))

      local object = { x = 0 }
      local tween_done = false
      t:tween(0.1, object, { x = 1 }, "linear", function()
        tween_done = true
      end, "tw")
      t:update(0.1)
      assert.is_true(tween_done)
      assert.are.equal(1, object.x)
      assert.is_false(t:exists("tw"))
    end)
  end)

  describe("pool management", function()
    it("keeps the old init module as a compatibility shim", function()
      assert.are.equal(timer, require("init"))
    end)

    it("does not let a stale handle clear a newer same-tag task", function()
      local old = t:after(1, function() end, "shared")
      local new_handle = t:after(2, function() end, "shared")
      t:cancel(old)
      assert.is_true(t:exists(new_handle))
      assert.are.equal(new_handle, t.tags["shared"])
    end)

    it("does not operate on handles from another pool", function()
      local other = new()
      local handle = t:after(1, function() end)
      local script = t:script(function(wait)
        wait(1)
      end)

      assert.is_false(other:cancel(handle))
      assert.is_false(other:pause(handle))
      assert.is_false(other:resume(handle))
      assert.is_false(other:exists(handle))
      assert.is_nil(other:remaining(handle))
      assert.is_false(other:isPaused(handle))
      assert.is_false(other:cancel(script))
      assert.is_false(other:exists(script))

      assert.are.equal(2, t:count())
      assert.are.equal(0, other:count())
      assert.is_true(t:exists(handle))
      assert.is_true(t:exists(script))
    end)

    it("rejects NaN tags and handles", function()
      expect_error("tag cannot be NaN", function()
        t:after(1, function() end, 0 / 0)
      end)
      assert.is_false(t:cancel(0 / 0))
      assert.is_false(t:pause(0 / 0))
      assert.is_false(t:exists(0 / 0))
      assert.is_nil(t:remaining(0 / 0))
    end)

    it("pauseAll in a callback stops later tasks in the same frame", function()
      local order = {}
      t:after(1, function()
        order[#order + 1] = "a"
        t:pauseAll()
      end)
      t:after(1, function()
        order[#order + 1] = "b"
      end)
      t:update(1)
      assert.are.same({ "a" }, order)
      t:resumeAll()
      t:update(1)
      assert.are.same({ "a", "b" }, order)
    end)

    it("runs same-frame callbacks in registration order", function()
      local order = {}
      for i = 1, 3 do
        t:after(1, function()
          order[#order + 1] = i
        end)
      end
      t:update(1)
      assert.are.same({ 1, 2, 3 }, order)
    end)

    it("keeps independent pools isolated", function()
      local other = new()
      local a, b = 0, 0
      t:after(1, function()
        a = a + 1
      end)
      other:after(1, function()
        b = b + 1
      end)
      t:update(1)
      assert.are.equal(1, a)
      assert.are.equal(0, b)
      other:clear()
      t:clear()
    end)

    it("pauses and resumes a task by tag", function()
      local fired = false
      t:after(1, function()
        fired = true
      end, "p")
      t:update(0.5)
      assert.is_true(t:pause("p"))
      t:update(10)
      assert.is_false(fired)
      assert.is_true(t:resume("p"))
      t:update(0.5)
      assert.is_true(fired)
    end)

    it("supports a pool-wide time scale", function()
      local fired = false
      t:after(1, function()
        fired = true
      end)
      t:setTimeScale(0.5)
      t:update(1)
      assert.is_false(fired)
      t:update(1)
      assert.is_true(fired)
    end)

    it("supports pauseAll and resumeAll", function()
      local fired = false
      t:after(1, function()
        fired = true
      end)
      t:pauseAll()
      assert.is_true(t:isPaused())
      t:update(5)
      assert.is_false(fired)
      t:resumeAll()
      assert.is_false(t:isPaused())
      t:update(1)
      assert.is_true(fired)
    end)

    it("reports remaining time and existence", function()
      local handle = t:after(1, function() end)
      t:update(0.25)
      near(t:remaining(handle), 0.75)
      assert.is_true(t:exists(handle))
      t:update(0.75)
      assert.is_false(t:exists(handle))
      assert.is_nil(t:remaining(handle))
    end)

    it("clear cancels callbacks scheduled later in the same frame", function()
      local log = {}
      t:after(1, function()
        log[#log + 1] = "a"
        t:clear()
      end)
      t:after(1, function()
        log[#log + 1] = "b"
      end)
      t:update(1)
      assert.are.same({ "a" }, log)
    end)

    it("returns false for unknown handles", function()
      assert.is_false(t:cancel("missing"))
      assert.is_false(t:pause("missing"))
      assert.is_false(t:resume("missing"))
      assert.is_false(t:exists("missing"))
      assert.is_nil(t:remaining("missing"))
    end)

    it("validates update dt and time scale", function()
      expect_error("dt must be a finite number >= 0", function()
        t:update(-1)
      end)
      expect_error("dt must be a finite number >= 0", function()
        t:update(0 / 0)
      end)
      expect_error("scale must be a finite number >= 0", function()
        t:setTimeScale(-1)
      end)
    end)
  end)
end)
