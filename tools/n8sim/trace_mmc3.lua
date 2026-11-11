-- trace_mmc3.lua — registra las escrituras a $8000-$9FFF (selección/dato del MMC3) con su fotograma
-- y scanline. Uso: N8_FRAMES=n N8_OUT=archivo Mesen --testrunner trace_mmc3.lua rom.nes
local frames = tonumber(os.getenv("N8_FRAMES") or "30")
local out = io.open(os.getenv("N8_OUT") or "trace.txt", "w")
local frame = 0
emu.addMemoryCallback(function(addr, value)
    local st = emu.getState()
    out:write(string.format("%d %d %04X %02X\n", frame, st["ppu.scanline"] or -99, addr, value))
end, emu.callbackType.write, 0x8000, 0x9FFF)
emu.addEventCallback(function()
    frame = frame + 1
    if frame >= frames then out:close(); emu.stop(0) end
end, emu.eventType.endFrame)
