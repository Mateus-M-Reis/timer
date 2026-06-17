local timer = require 'init'

-- Tables representing our test objects in 3D space
local box_after  = { x = -2,   y = 1.5, z = -3, size = 0.3, color = {1, 0, 0} }
local box_every  = { x = -0.8, y = 1.5, z = -3, size = 0.3, color = {0, 1, 0} }
local box_during = { x = 0.8,  y = 1.5, z = -3, size = 0.3, color = {0, 0, 1} }
local box_tween  = { x = 2,    y = 1.5, z = -3, size = 0.3, color = {1, 1, 0} }
local box_script = { x = 0,    y = 3.0, z = -4, size = 0.4, color = {1, 0, 1} }
local box_pause  = { x = -1,   y = -0.1, z = -4, size = 0.4, color = {1, 0, 0} }

-- Variable to track the state of the TAG testing via user input click
local click_feedback = "Press any key to test TAGS!"

function lovr.load()
  ---------------------------------------------------------------------------
  -- 1. Testing: timer.after
  ---------------------------------------------------------------------------
  -- After 3 seconds, permanently changes the first cube's color to White.
  timer.after(3, function()
    box_after.color = {1, 1, 1}
  end)

  ---------------------------------------------------------------------------
  -- 2. Testing: timer.every
  ---------------------------------------------------------------------------
  -- Makes the green cube blink (changing its size) every 0.5 seconds.
  -- Returning false would stop the loop, but here we let it run indefinitely.
  timer.every(0.5, function()
    if box_every.size == 0.3 then
      box_every.size = 0.1
    else
      box_every.size = 0.3
    end
  end)

  ---------------------------------------------------------------------------
  -- 3. Testing: timer.during
  ---------------------------------------------------------------------------
  -- During the first 5 seconds of the game, rotates and moves the blue cube 
  -- every frame. Upon completion, shrinks it significantly.
  box_during.angle = 0
  timer.during(5, function(dt)
    box_during.angle = box_during.angle + dt * 4
    box_during.y = 1.5 + math.sin(box_during.angle) * 0.2
  end, function()
  box_during.size = 0.1 -- Callback executed when the duration ends
end)

-- Starts the movement animation for the pause/resume test cube immediately
timer.tween(5.0, box_pause, { x = 1 }, "quadout", nil, "player_movement")

---------------------------------------------------------------------------
-- 4. Testing: timer.tween
---------------------------------------------------------------------------
-- Continuously interpolates the yellow cube up and down using quadout easing.
local function loop_tween()
  local target_y = box_tween.y == 1.5 and 0.5 or 1.5
  timer.tween(2, box_tween, { y = target_y }, 'quadout', loop_tween)
end
loop_tween()

---------------------------------------------------------------------------
-- 5. Testing: timer.script (Asynchronous Sequencing with Coroutines)
---------------------------------------------------------------------------
-- Controls the top purple cube, executing a complex multi-step choreography.
timer.script(function(wait)
  while true do
    -- Step A: Wait for 2 seconds while idle
    wait(2)

    -- Step B: Interpolate size until it becomes huge (takes 1.5 seconds)
    timer.tween(1.5, box_script, { size = 0.8 }, 'quadinout')
    wait(1.5) -- Wait exactly for the tween to finish

    -- Step C: Change color to cyan instantly and wait for 1 second
    box_script.color = {0, 1, 1}
    wait(1)

    -- Step D: Smoothly restore the original size and color
    timer.tween(1, box_script, { size = 0.4 }, 'linear')
    wait(1)
    box_script.color = {1, 0, 1}
  end
end)
end

-- Simulates a trigger/click to test tag overriding and protection in EnhancedTimer
function lovr.keypressed(key)
  -- Press 'p' or 'r' to control the pause cube animation state
  if key == "p" then
    -- Pauses the animation immediately
    timer.pause("player_movement")
    click_feedback = "Animation paused ('player_movement')"
  elseif key == "r" then
    -- Resumes the animation from where it left off
    timer.resume("player_movement")
    click_feedback = "Animation resumed ('player_movement')"
  elseif key then
    -- Any other key simulates a rapid repetitive command
    click_feedback = "Trigger fired! Timer restarted without stacking."
    box_after.size = 0.6 -- Abruptly increases the red cube size

    -- Using TAGS ("reset_red"): If you press keys multiple times in a row,
    -- the previous timer is automatically cancelled. The cube will never bug
    -- or shrink prematurely, resetting the 1-second delay perfectly.
    timer.after(1, function()
      box_after.size = 0.3
      click_feedback = "Cube successfully reset via Tag!"
    end, "reset_red")
  end
end

function lovr.update(dt)
  -- The main clock UPDATES ONLY HERE. All external files (like menus)
  -- that require 'init' will benefit from the same synchronized global clock.
  timer.update(dt)
end

function lovr.draw(pass)
  -- Draws informative texts floating in the virtual environment
  pass:setColor(1, 1, 1)
  pass:text("Timer Module Test Showcase", 0, 2.5, -3, 0.2)
  pass:text(click_feedback, 0, 0.5, -2, 0.1)

  pass:text("after", box_after.x, box_after.y + 0.4, box_after.z, 0.1)
  pass:text("every", box_every.x, box_every.y + 0.4, box_every.z, 0.1)
  pass:text("during", box_during.x, box_during.y + 0.4, box_during.z, 0.1)
  pass:text("tween", box_tween.x, box_tween.y + 0.4, box_tween.z, 0.1)
  pass:text("script (coroutine)", box_script.x, box_script.y + 0.6, box_script.z, 0.1)
  pass:text("pause/resume", box_pause.x, box_pause.y + 0.6, box_pause.z, 0.1)

  -- Draws Cube 1: After (Turns white after 3s / Press any key to test Tag on it)
  pass:setColor(box_after.color[1], box_after.color[2], box_after.color[3])
  pass:cube(box_after.x, box_after.y, box_after.z, box_after.size)

  -- Draws Cube 2: Every (Blinks by changing size perpetually every 0.5s)
  pass:setColor(box_every.color[1], box_every.color[2], box_every.color[3])
  pass:cube(box_every.x, box_every.y, box_every.z, box_every.size)

  -- Draws Cube 3: During (Rotates and floats during the first 5s, then shrinks and stops)
  pass:setColor(box_during.color[1], box_during.color[2], box_during.color[3])
  pass:cube(box_during.x, box_during.y, box_during.z, box_during.size, box_during.angle or 0, 0, 1, 0)

  -- Draws Cube 4: Tween (Continuous interpolation moving up and down in Y)
  pass:setColor(box_tween.color[1], box_tween.color[2], box_tween.color[3])
  pass:cube(box_tween.x, box_tween.y, box_tween.z, box_tween.size)

  -- Draws Cube 5: Script (Async choreography controlled by yields and custom delays)
  pass:setColor(box_script.color[1], box_script.color[2], box_script.color[3])
  pass:cube(box_script.x, box_script.y, box_script.z, box_script.size)

  -- Draws Cube 6: Pause/Resume Showcase
  pass:setColor(box_pause.color[1], box_pause.color[2], box_pause.color[3])
  pass:cube(box_pause.x, box_pause.y, box_pause.z, box_pause.size)
  pass:setColor(1, 1, 1)
end
