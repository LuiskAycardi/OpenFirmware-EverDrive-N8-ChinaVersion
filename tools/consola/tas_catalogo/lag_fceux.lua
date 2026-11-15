-- lag_fceux.lua — en FCEUX, reproduce la película cargada con --playmov y anota qué fotogramas fueron de lag (el juego
-- no leyó el mando) y, si se piden, guarda capturas. FCEUX reproduce la película tal como se grabó: sirve de juez para
-- saber si Mesen2 la sincroniza y, si no, de referencia para la consola (los TAS verificados reproducen en una NES real
-- lo mismo que FCEUX).
--   N8_LAG_OUT   archivo de salida: una línea "fotograma lag(0/1)" por fotograma de la película
--   N8_SHOTS     fotogramas en que guardar captura (separados por comas; numeración de la película)
--   N8_SHOT_DIR  carpeta de las capturas (f%05d.png)
--   N8_EXTRA     fotogramas a seguir tras el final de la película (para la captura de "fin + 30 s")
--   fceux --sound 0 --playmov PELI.fm2 --loadlua lag_fceux.lua ROM.nes

local salida = io.open(os.getenv("N8_LAG_OUT") or "lag.txt", "w")
local dir = os.getenv("N8_SHOT_DIR") or "."
local extra = tonumber(os.getenv("N8_EXTRA") or "0")
local shots = {}
for n in string.gmatch(os.getenv("N8_SHOTS") or "", "%d+") do shots[tonumber(n)] = true end

emu.speedmode("maximum")
local n = movie.length()
local f = 0
while true do
    f = movie.framecount()
    emu.frameadvance()
    if movie.mode() == "playback" then
        salida:write(f, " ", emu.lagged() and 1 or 0, "\n")
    end
    if shots[f + 1] then
        gui.savescreenshotas(string.format("%s/f%05d.png", dir, f + 1))
    end
    if f >= n + extra then
        break
    end
end
salida:close()
os.exit(0)
