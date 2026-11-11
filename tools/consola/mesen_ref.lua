-- mesen_ref.lua — referencia de Mesen2 (su propio mapper) para comparar con la consola.
-- Mismo guion y mismas capturas que tools/n8sim/run_test.lua, y además apunta en qué fotogramas lee el juego el
-- mando (polls.txt). Con eso el Nano sabe en qué fotograma empieza el juego en la consola.
-- Variables de entorno:
--   N8_FRAMES   fotogramas a ejecutar
--   N8_SCRIPT   guion "ini-fin:boton+boton;..." (fotograma = fotogramas completos desde el encendido)
--   N8_SHOTS    fotogramas a capturar (PPM), separados por comas
--   N8_SHOT_DIR carpeta de salida (f00120.ppm, polls.txt)

local frames  = tonumber(os.getenv("N8_FRAMES") or "1200")
local shotDir = os.getenv("N8_SHOT_DIR") or "."
local shots = {}
for n in string.gmatch(os.getenv("N8_SHOTS") or "", "%d+") do shots[tonumber(n)] = true end

local script = {}
for a, b, btns in string.gmatch(os.getenv("N8_SCRIPT") or "", "(%d+)-(%d+):([%a%+]+)") do
    local set = {}
    for name in string.gmatch(btns, "%a+") do set[string.lower(name)] = true end
    script[#script + 1] = { tonumber(a), tonumber(b), set }
end
local function scriptInput(n)
    for _, t in ipairs(script) do
        if n >= t[1] and n <= t[2] then return t[3] end
    end
    return {}
end

local frame = 0
local polls = {}       -- fotograma -> número de lecturas

emu.addEventCallback(function()
    polls[frame] = (polls[frame] or 0) + 1
    emu.setInput(scriptInput(frame), 0, 0)
end, emu.eventType.inputPolled)

local function writePolls()
    local f = io.open(shotDir .. "/polls.txt", "w")
    for n = 0, frame do
        if polls[n] then f:write(string.format("%d %d\n", n, polls[n])) end
    end
    f:close()
end

emu.addEventCallback(function()
    frame = frame + 1
    if shots[frame] then
        local buf = emu.getScreenBuffer()
        local size = emu.getScreenSize()
        local parts = { string.format("P6\n%d %d\n255\n", size.width, size.height) }
        local chunk = {}
        for i = 1, #buf do
            local c = buf[i]
            chunk[#chunk + 1] = string.char((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF)
            if #chunk == 1024 then parts[#parts + 1] = table.concat(chunk); chunk = {} end
        end
        parts[#parts + 1] = table.concat(chunk)
        local f = io.open(string.format("%s/f%05d.ppm", shotDir, frame), "wb")
        f:write(table.concat(parts))
        f:close()
    end
    if frame >= frames then
        writePolls()
        emu.stop(0)
    end
end, emu.eventType.endFrame)
