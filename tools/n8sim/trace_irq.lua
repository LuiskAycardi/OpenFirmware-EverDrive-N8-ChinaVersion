-- trace_irq.lua — registra cada IRQ atendida por la CPU: fotograma, scanline y punto de PPU.
local frames = tonumber(os.getenv("N8_FRAMES") or "120")
local out = io.open(os.getenv("N8_OUT") or "irq.txt", "w")
local frame = 0
emu.addEventCallback(function()
    local st = emu.getState()
    out:write(string.format("%d %d %d\n", frame, st["ppu.scanline"] or -99, st["ppu.cycle"] or -99))
end, emu.eventType.irq)
emu.addEventCallback(function()
    frame = frame + 1
    if frame >= frames then out:close(); emu.stop(0) end
end, emu.eventType.endFrame)
