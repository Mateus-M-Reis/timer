-- Compatibility shim for projects that used to `require 'init'`.
--
-- The canonical module is now `timer.lua`. Keep this file only if you need the
-- old module name; new projects should use `require 'timer'`.
return require("timer")
