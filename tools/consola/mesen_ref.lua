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
-- N8_INPUT_FILE: un byte por fotograma (máscara del Nano: bit 0 = A ... bit 7 = Derecha), por ejemplo una
-- película TAS convertida con tas.py; el byte k es la entrada del fotograma k. Se suma al guion N8_SCRIPT.
local NOMBRES = { "a", "b", "select", "start", "up", "down", "left", "right" }
local entrada = nil
local rutaEntrada = os.getenv("N8_INPUT_FILE")
local desfaseEntrada = tonumber(os.getenv("N8_INPUT_OFFSET") or "0")   -- byte de la entrada = fotograma + desfase
if rutaEntrada and rutaEntrada ~= "" then
    local f = io.open(rutaEntrada, "rb")
    entrada = f:read("a")
    f:close()
end

local function scriptInput(n)
    local set = {}
    for _, t in ipairs(script) do
        if n >= t[1] and n <= t[2] then
            for k, v in pairs(t[3]) do set[k] = v end
            break
        end
    end
    local k = n + desfaseEntrada
    if entrada and k >= 0 and k < #entrada then
        local b = string.byte(entrada, k + 1)
        for i = 0, 7 do
            if (b >> i) & 1 == 1 then set[NOMBRES[i + 1]] = true end
        end
    end
    return set
end

local frame = 0
local polls = {}       -- fotograma -> número de pulsos de LATCH

-- Mesen2 lanza inputPolled una vez por fotograma en una línea fija de la PPU, lea o no el juego el mando: sirve para
-- dar la entrada del guion, pero no para saber cuándo lee. Eso lo dice el pulso de LATCH (escritura en $4016 con el
-- bit 0 de 0 a 1), que es justo lo que cuenta el Nano en la consola. (Punch-Out!! no hace LATCH en su intro: con
-- inputPolled salía p0 = 1 y la consola iba ~9 s desfasada; 2026-11-11.)
emu.addEventCallback(function()
    emu.setInput(scriptInput(frame), 0, 0)
end, emu.eventType.inputPolled)

local latch = 0
emu.addMemoryCallback(function(addr, value)
    local b = value & 1
    if b == 1 and latch == 0 then polls[frame] = (polls[frame] or 0) + 1 end
    latch = b
end, emu.callbackType.write, 0x4016)

-- N8_PEEK: direcciones de la CPU separadas por comas; al terminar se escriben sus valores en peek.txt (para
-- comprobar si una película TAS sincroniza: mundo y nivel de SMB1, etc.).
local function writePeek()
    local lista = os.getenv("N8_PEEK") or ""
    if lista == "" then return end
    local f = io.open(shotDir .. "/peek.txt", "w")
    for a in string.gmatch(lista, "[^,]+") do
        local addr = tonumber(a)
        f:write(string.format("%04X %d\n", addr, emu.read(addr, emu.memType.nesDebug, false)))
    end
    f:close()
end

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
        writePeek()
        writePolls()
        emu.stop(0)
    end
end, emu.eventType.endFrame)
