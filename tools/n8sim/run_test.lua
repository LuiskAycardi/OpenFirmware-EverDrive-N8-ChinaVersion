-- run_test.lua — Script del banco de pruebas N8 para el TestRunner de Mesen2.
-- Parámetros por variables de entorno:
--   N8_FRAMES      fotogramas a ejecutar (por defecto 1800 = 30 s)
--   N8_OUT         archivo donde escribir "fotograma hash" (uno por línea)
--   N8_SEED        semilla de la secuencia de botones (misma semilla = mismos botones)
--   N8_SHOTS       lista de fotogramas a capturar en PNG, separados por comas
--   N8_SHOT_DIR    carpeta para los PNG
-- La secuencia de botones es determinista: las dos ejecuciones (mapper de Mesen y nuestro
-- Verilog) reciben exactamente la misma entrada.

local frames  = tonumber(os.getenv("N8_FRAMES") or "1800")
local outPath = os.getenv("N8_OUT") or "hashes.txt"
local seed    = tonumber(os.getenv("N8_SEED") or "12345")
local shotDir = os.getenv("N8_SHOT_DIR") or "."
local shots   = {}
local dumps   = {}
for n in string.gmatch(os.getenv("N8_DUMPS") or "", "%d+") do dumps[tonumber(n)] = true end
for n in string.gmatch(os.getenv("N8_SHOTS") or "", "%d+") do shots[tonumber(n)] = true end

local stateMode = (os.getenv("N8_STATE") or "0") ~= "0"
local out = io.open(outPath, "w")
local frame = 0

-- Generador congruencial (determinista e independiente de la versión de Lua)
local rng = seed & 0x7FFFFFFF
local function rand()
    rng = (rng * 1103515245 + 12345) & 0x7FFFFFFF
    return rng
end

-- Plan de botones: arranque tranquilo, varios Start para pasar menús y luego
-- tramos de 8–40 fotogramas con combinaciones aleatorias (sin Select).
local names = { "a", "b", "start", "up", "down", "left", "right" }
local current, remaining = {}, 0
-- N8_SCRIPT (opcional): secuencia fija en lugar de la aleatoria, "ini-fin:boton+boton;..."
-- p. ej. "120-126:start;300-306:a;500-900:right+b". Fuera de los tramos no se pulsa nada.
local script = {}
for a, b, btns in string.gmatch(os.getenv("N8_SCRIPT") or "", "(%d+)-(%d+):([%a%+]+)") do
    local set = {}
    for name in string.gmatch(btns, "%a+") do set[name] = true end
    script[#script + 1] = { tonumber(a), tonumber(b), set }
end
local function scriptInput(n)
    for _, t in ipairs(script) do
        if n >= t[1] and n <= t[2] then return t[3] end
    end
    return {}
end
local function nextInput(n)
    if #script > 0 then return scriptInput(n) end
    if n < 90 then return {} end
    if n % 150 >= 90 and n % 150 < 96 and n < 900 then return { start = true } end
    if remaining <= 0 then
        current = {}
        local r = rand()
        for i, name in ipairs(names) do
            if name ~= "start" and ((r >> i) & 3) == 0 then current[name] = true end
        end
        if current.left and current.right then current.left = nil end
        if current.up and current.down then current.up = nil end
        remaining = 8 + (rand() % 33)
    end
    remaining = remaining - 1
    return current
end

emu.addEventCallback(function()
    emu.setInput(nextInput(frame), 0, 0)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
    frame = frame + 1
    local buf = emu.getScreenBuffer()
    local h = 2166136261
    for i = 1, #buf do
        h = ((h ~ buf[i]) * 16777619) & 0xFFFFFFFF
    end
    if stateMode then
        -- estado de la CPU en este fotograma: hash de la RAM interna y del OAM, ciclos y PC
        local function memHash(memType, size)
            local x = 2166136261
            for a = 0, size - 1 do x = ((x ~ emu.read(a, memType, false)) * 16777619) & 0xFFFFFFFF end
            return x
        end
        local st = emu.getState()
        if frame == 1 then
            local keys = {}
            for k, _ in pairs(st) do if string.sub(k, 1, 4) == "cpu." then keys[#keys + 1] = k end end
            table.sort(keys)
            local kf = io.open(outPath .. ".keys", "w"); kf:write(table.concat(keys, "\n")); kf:close()
        end
        out:write(string.format("%d %08x ram=%08x oam=%08x cyc=%s pc=%s\n", frame, h,
            memHash(emu.memType.nesInternalRam, 0x800), memHash(emu.memType.nesSpriteRam, 0x100),
            tostring(st["cpu.cycleCount"]), tostring(st["cpu.pc"])))
    else
        out:write(string.format("%d %08x\n", frame, h))
    end
    if shots[frame] then
        -- imagen exacta de este fotograma (el mismo búfer del hash), en PPM; difftest la pasa a PNG.
        -- (emu.takeScreenshot() devuelve el último fotograma mostrado, que puede ir atrasado)
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
    if dumps[frame] then
        -- volcado completo de RAM interna, OAM y RAM de $6000 (N8_DUMPS=lista de fotogramas)
        local f = io.open(string.format("%s/ram%05d.bin", shotDir, frame), "wb")
        local parts = {}
        for a = 0, 0x7FF do parts[#parts + 1] = string.char(emu.read(a, emu.memType.nesInternalRam, false)) end
        for a = 0, 0xFF do parts[#parts + 1] = string.char(emu.read(a, emu.memType.nesSpriteRam, false)) end
        for a = 0x6000, 0x7FFF do parts[#parts + 1] = string.char(emu.read(a, emu.memType.nesMemory, false)) end
        f:write(table.concat(parts)); f:close()
    end
    if frame >= frames then
        out:close()
        emu.stop(0)
    end
end, emu.eventType.endFrame)
