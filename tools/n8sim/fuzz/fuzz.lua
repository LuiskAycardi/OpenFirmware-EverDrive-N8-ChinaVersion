-- fuzz.lua — Registra los pasos de la ROM sintética de romgen.py (TestRunner de Mesen2).
-- Cada vez que el programa escribe en $07FF (paso listo) guarda una línea:
--   paso dirección dato muestra(105 bytes en hex: PRG $6000-$FC00, CHR $0000-$1C00, nametables, IRQ)
-- Variables de entorno: N8_FUZZ_OUT (archivo), N8_FRAMES (límite de fotogramas).
local outPath = os.getenv("N8_FUZZ_OUT") or "fuzz.txt"
local frames = tonumber(os.getenv("N8_FRAMES") or "2000")
local out = io.open(outPath, "w")
local mem = emu.memType.nesInternalRam
local frame = 0

local function rd(a) return emu.read(a, mem, false) end

emu.addMemoryCallback(function(addr, value)
    local step = rd(0x07FB) | (rd(0x07FC) << 8)
    local parts = {}
    for a = 0x0600, 0x0668 do parts[#parts + 1] = string.format("%02X", rd(a)) end
    out:write(string.format("%d %02X%02X %02X %s\n", step, rd(0x0671), rd(0x0670), rd(0x0672), table.concat(parts)))
end, emu.callbackType.write, 0x07FF)

emu.addMemoryCallback(function(addr, value)
    if value == 0xAA then
        out:write("FIN\n")
        out:close()
        emu.stop(0)
    end
end, emu.callbackType.write, 0x07FD)

emu.addEventCallback(function()
    frame = frame + 1
    if frame >= frames then
        out:write("LIMITE\n")
        out:close()
        emu.stop(0)
    end
end, emu.eventType.endFrame)
