local timer = require 'init'

-- Tabelas que representam nossos objetos de teste no espaço 3D
local box_after = { x = -2, y = 1.5, z = -3, size = 0.3, color = {1, 0, 0} }
local box_every = { x = -0.8, y = 1.5, z = -3, size = 0.3, color = {0, 1, 0} }
local box_during = { x = 0.8, y = 1.5, z = -3, size = 0.3, color = {0, 0, 1} }
local box_tween = { x = 2, y = 1.5, z = -3, size = 0.3, color = {1, 1, 0} }
local box_script = { x = 0, y = 3.0, z = -4, size = 0.4, color = {1, 0, 1} }

-- Variável para monitorar o estado do teste de TAGs por clique do usuário
local click_feedback = "Clique/Gatilho para testar as TAGS!"

function lovr.load()
  ---------------------------------------------------------------------------
  -- 1. Testando: timer.after
  ---------------------------------------------------------------------------
  -- Após 3 segundos, altera permanentemente a cor do primeiro cubo para Branco.
  timer.after(3, function()
    box_after.color = {1, 1, 1}
  end)

  ---------------------------------------------------------------------------
  -- 2. Testando: timer.every
  ---------------------------------------------------------------------------
  -- Faz o cubo verde piscar (mudando seu tamanho) a cada 0.5 segundos.
  -- Retornar false faria o HUMP timer parar o loop, mas aqui deixamos rodar.
  timer.every(0.5, function()
    if box_every.size == 0.3 then
      box_every.size = 0.1
    else
      box_every.size = 0.3
    end
  end)

  ---------------------------------------------------------------------------
  -- 3. Testando: timer.during
  ---------------------------------------------------------------------------
  -- Durante os primeiros 5 segundos do jogo, rotaciona/modifica o cubo azul 
  -- a cada frame. Ao terminar, deixa ele bem pequeno.
  box_during.angle = 0
  timer.during(5, function(dt)
    box_during.angle = box_during.angle + dt * 4
    box_during.y = 1.5 + math.sin(box_during.angle) * 0.2
  end, function()
  box_during.size = 0.1 -- Callback executado quando o tempo acaba
end)

---------------------------------------------------------------------------
-- 4. Testando: timer.tween
---------------------------------------------------------------------------
-- Move o cubo amarelo continuamente de cima para baixo usando interpolação quadout.
local function loop_tween()
  local target_y = box_tween.y == 1.5 and 0.5 or 1.5
  timer.tween(2, box_tween, { y = target_y }, 'quadout', loop_tween)
end
loop_tween()

---------------------------------------------------------------------------
-- 5. Testando: timer.script (Sequenciamento Assíncrono com Coroutines)
---------------------------------------------------------------------------
-- Controla o cubo roxo superior executando uma coreografia complexa por etapas.
timer.script(function(wait)
  while true do
    -- Etapa A: Espera 2 segundos parado
    wait(2)

    -- Etapa B: Interpola o tamanho até ficar gigante (leva 1.5 segundos)
    timer.tween(1.5, box_script, { size = 0.8 }, 'quadinout')
    wait(1.5) -- Espera o tempo exato do tween terminar

    -- Etapa C: Muda a cor para ciano instantaneamente e espera 1 segundo
    box_script.color = {0, 1, 1}
    wait(1)

    -- Etapa D: Retorna o tamanho e a cor original suavizadamente
    timer.tween(1, box_script, { size = 0.4 }, 'linear')
    wait(1)
    box_script.color = {1, 0, 1}
  end
end)
end

-- Simula o gatilho/clique para testar a substituição e proteção de TAGs do EnhancedTimer
function lovr.keypressed(key)
  -- Pressione 'space' ou qualquer tecla para simular um comando repetitivo rápido
  if key then
    click_feedback = "Gatilho disparado! Timer reiniciado sem acumular."
    box_after.size = 0.6 -- Aumenta o cubo vermelho abruptamente

    -- Usando TAGS ("reset_vermelho"): Se você apertar a tecla várias vezes seguidas,
    -- o timer anterior é cancelado automaticamente. O cubo nunca vai bugar ou ficar
    -- encolhendo antes da hora, reiniciando o delay de 1 segundo perfeitamente.
    timer.after(1, function()
      box_after.size = 0.3
      click_feedback = "Cubo resetado com sucesso via Tag!"
    end, "reset_vermelho")
  end
end

function lovr.update(dt)
  -- O ciclo principal ATUALIZA APENAS AQUI. Todos os arquivos externos (como menus)
  -- que derem require 'lib.timer' se beneficiarão do mesmo relógio global atualizado.
  timer.update(dt)
end

function lovr.draw(pass)
  -- Desenha os textos informativos flutuando no ambiente virtual
  pass:setColor(1, 1, 1)
  pass:text("Timer Module Test Showcase", 0, 2.5, -3, 0.2)
  pass:text(click_feedback, 0, 0.5, -2, 0.1)

  pass:text("after", box_after.x, box_after.y + 0.4, box_after.z, 0.1)
  pass:text("every", box_every.x, box_every.y + 0.4, box_every.z, 0.1)
  pass:text("during", box_during.x, box_during.y + 0.4, box_during.z, 0.1)
  pass:text("tween", box_tween.x, box_tween.y + 0.4, box_tween.z, 0.1)
  pass:text("script (coroutine)", box_script.x, box_script.y + 0.6, box_script.z, 0.1)

  -- Desenha o Cubo 1: After (Fica branco após 3s / Aperte uma tecla para testar Tag nele)
  pass:setColor(box_after.color[1], box_after.color[2], box_after.color[3])
  pass:cube(box_after.x, box_after.y, box_after.z, box_after.size)

  -- Desenha o Cubo 2: Every (Fica piscando de tamanho perpetuamente de 0.5s em 0.5s)
  pass:setColor(box_every.color[1], box_every.color[2], box_every.color[3])
  pass:cube(box_every.x, box_every.y, box_every.z, box_every.size)

  -- Desenha o Cubo 3: During (Rotaciona e flutua nos primeiros 5s, depois encolhe e para)
  pass:setColor(box_during.color[1], box_during.color[2], box_during.color[3])
  pass:cube(box_during.x, box_during.y, box_during.z, box_during.size, box_during.angle or 0, 0, 1, 0)

  -- Desenha o Cubo 4: Tween (Interpolação contínua de subida e descida em Y)
  pass:setColor(box_tween.color[1], box_tween.color[2], box_tween.color[3])
  pass:cube(box_tween.x, box_tween.y, box_tween.z, box_tween.size)

  -- Desenha o Cubo 5: Script (Coreografia assíncrona controlada por yields e tempos customizados)
  pass:setColor(box_script.color[1], box_script.color[2], box_script.color[3])
  pass:cube(box_script.x, box_script.y, box_script.z, box_script.size)
end
