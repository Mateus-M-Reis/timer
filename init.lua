---@class TimerTask
---@field type string O tipo da tarefa (after, every, during, tween)
---@field time number O tempo atual acumulado
---@field limit number O tempo limite/delay configurado
---@field action? function A função principal a ser executada
---@field after_action? function A função a ser executada ao terminar (para during/tween)
---@field target? table O alvo do tween
---@field payload? table Os valores processados do tween
---@field easing? function A função de suavização
---@field tag? any A tag de identificação única

---@class TimerInstance
---@field tasks table<TimerTask, boolean>
---@field tags table<any, TimerTask>
local Timer = {}; Timer.__index = Timer

-- Dicionário O(1) rápido para os easings do tween
local easings = {
  linear = function(t) return t end,

  -- Quad
  quadin = function(t) return t * t end,
  quadout = function(t) return t * (2 - t) end,
  quadinout = function(t) return t < 0.5 and 2 * t * t or -1 + (4 - 2 * t) * t end,

  -- Cubic
  cubicin = function(t) return t * t * t end,
  cubicout = function(t) t = t - 1; return t * t * t + 1 end,
  cubicinout = function(t) t = t * 2; if t < 1 then return 0.5 * t * t * t end; t = t - 2; return 0.5 * (t * t * t + 2) end,

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

--- Instancia um novo pool de timers (caso queira timers locais além do global)
---@return TimerInstance
function Timer.new()
  return setmetatable({
    tasks = {},
    tags = {}
  }, Timer)
end

---@param dt number Tempo delta do frame
function Timer:update(dt)
  -- Iteramos sobre uma cópia para permitir remoções/adições seguras durante o loop
  local to_update = {}
  for task in pairs(self.tasks) do to_update[task] = true end

  for task in pairs(to_update) do
    if self.tasks[task] then
      task.time = task.time + dt

      if task.type == "after" then
        if task.time >= task.limit then
          self:cancel(task)
          task.action()
        end
      elseif task.type == "every" then
        if task.time >= task.limit then
          task.time = task.time - task.limit
          -- Se a função retornar false, nós abortamos o loop infinito (comportamento do Hump)
          if task.action() == false then
            self:cancel(task)
          end
        end
      elseif task.type == "during" then
        task.action(dt)
        if task.time >= task.limit then
          self:cancel(task)
          if task.after_action then task.after_action() end
        end
      elseif task.type == "tween" then
        local t = math.min(task.time / task.limit, 1)
        local e = task.easing(t)
        for key, vals in pairs(task.payload) do
          task.target[key] = vals.start + (vals.target - vals.start) * e
        end
        if t == 1 then
          self:cancel(task)
          if task.after_action then task.after_action() end
        end
      end
    end
  end
end

---@param handle_or_tag any Pode ser a string da tag ou a própria tabela do timer
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

function Timer:clear()
  self.tasks = {}
  self.tags = {}
end

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

---@param delay number
---@param action function
---@param tag? any
---@return TimerTask
function Timer:every(delay, action, tag)
  if tag then self:cancel(tag) end
  local task = { type = "every", time = 0, limit = delay, action = action, tag = tag }
  self.tasks[task] = true
  if tag then self.tags[tag] = task end
  return task
end

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

---@param delay number
---@param target table Tabela que contém os valores
---@param payload table Valores finais desejados
---@param method? string Ex: 'linear', 'quadinout'
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

---@param f function Função usando coroutine.yield(delay)
---@param tag? any
function Timer:script(f, tag)
  if tag then self:cancel(tag) end
  local co = coroutine.create(f)
  local function step()
    local ok, wait = coroutine.resume(co)
    if ok and wait and coroutine.status(co) ~= "dead" then
      self:after(wait, step, tag)
    end
  end
  step()
end

-------------------------------------------------------------------------------
-- Instância Global (Exportação do Módulo)
-------------------------------------------------------------------------------

---@class TimerModule
local default_timer = Timer.new()
local M = {}

--- Permite instanciar timers locais (ex: local my_timer = timer.new())
M.new = Timer.new

--- O loop principal. Coloque no lovr.update(dt) do main.lua
---@param dt number
function M.update(dt) return default_timer:update(dt) end

--- Limpa todos os timers globais ativos
function M.clear() return default_timer:clear() end

--- Cancela um timer ativo pela tag ou referência
---@param handle_or_tag any
function M.cancel(handle_or_tag) return default_timer:cancel(handle_or_tag) end

--- Executa uma função após um delay
---@param delay number
---@param action function
---@param tag? any
---@return TimerTask
function M.after(delay, action, tag) return default_timer:after(delay, action, tag) end

--- Executa uma função repetidamente em intervalos
---@param delay number
---@param action function
---@param tag? any
---@return TimerTask
function M.every(delay, action, tag) return default_timer:every(delay, action, tag) end

--- Executa uma função todo frame durante um período de tempo
---@param delay number
---@param action function
---@param after_action? function
---@param tag? any
---@return TimerTask
function M.during(delay, action, after_action, tag) return default_timer:during(delay, action, after_action, tag) end

--- Anima valores em uma tabela de forma procedural
---@param delay number
---@param target table
---@param payload table
---@param method? string
---@param after_action? function
---@param tag? any
---@return TimerTask
function M.tween(delay, target, payload, method, after_action, tag) return default_timer:tween(delay, target, payload, method, after_action, tag) end

--- Executa uma coroutine respeitando o ciclo do timer
---@param f function
---@param tag? any
function M.script(f, tag) return default_timer:script(f, tag) end

return M
