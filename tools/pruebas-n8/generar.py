#!/usr/bin/env python3
"""generar.py — Página "Pruebas N8" y su versión en texto a partir de plan.json.

  python3 -I tools/pruebas-n8/generar.py SALIDA.html [docs/plan-pruebas-consola.md]

plan.json: lista de secciones {id, consola (nes|famicom), titulo, carpeta, rbf, intro, juegos: [{id, n, m, mirar,
anota, pila, tipo}]}. Los id de los juegos son las claves de la base de datos de la página (colección
`resultados`): no se cambian al editar un juego, o se perdería su resultado.
plantilla.html: la página con `__PLAN__` donde va el JSON. La página publicada es
https://claude.ai/artifact/M7ivqPxY2kGrvWydGXVXPd (capacidad db; se publica con la herramienta Artifact).
"""
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent


def main():
    plan = json.loads((HERE / "plan.json").read_text())
    ids = [j["id"] for s in plan for j in s["juegos"]]
    dup = {i for i in ids if ids.count(i) > 1}
    if dup:
        sys.exit(f"id repetidos: {sorted(dup)}")
    html = (HERE / "plantilla.html").read_text().replace("__PLAN__", json.dumps(plan, ensure_ascii=False))
    pathlib.Path(sys.argv[1]).write_text(html)
    nes = sum(len(s["juegos"]) for s in plan if s["consola"] == "nes")
    fam = sum(len(s["juegos"]) for s in plan if s["consola"] == "famicom")
    print(f"{len(ids)} comprobaciones: {nes} NES, {fam} Famicom")
    if len(sys.argv) > 2:
        md = ["# Plan de pruebas en consola (N8 de NES y N8 de Famicom)", "",
              "Generado por tools/pruebas-n8/generar.py desde plan.json. La versión interactiva (con resultados que",
              "Claude puede leer) es la página \"Pruebas N8\" publicada en claude.ai. Aquí, la misma lista en texto.", "",
              "**Cómo probar:** arranca cada juego y juega uno o dos minutos. Marca OK si todo va como debe. Si falla,",
              "anota qué ves (pantalla negra o gris, gráficos rotos, parpadeo, se reinicia, se cuelga), en qué momento",
              "y si se repite. **Partidas con pila:** guarda, apaga la consola 10 segundos, enciende, vuelve a cargar el",
              "juego desde el menú del N8 y comprueba la partida.", ""]
        for con, nombre in (("nes", "NES (N8 de NES)"), ("famicom", "Famicom AV (N8 de Famicom)")):
            md += [f"## {nombre}", ""]
            for s in plan:
                if s["consola"] != con:
                    continue
                md += [f"### {s['titulo']}", f"Carpeta: `{s['carpeta']}` · RBF: {s['rbf']}", "", s["intro"], "",
                       "| Juego | Mapper | Qué mirar | Qué anotar |", "|---|---|---|---|"]
                for j in s["juegos"]:
                    anota = (j["anota"] or "OK o qué falla") + (" (pila)" if j["pila"] else "")
                    md.append(f"| {j['n']} | {j['m']} | {j['mirar']} | {anota} |")
                md.append("")
        pathlib.Path(sys.argv[2]).write_text("\n".join(md) + "\n")


if __name__ == "__main__":
    main()
