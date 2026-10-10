# Survive the Hero

Survivor estilo Vampire Survivors al revés, en Godot 4 (GDScript), pixel art 2D. El jugador es el creep (en el juego, "Anti Hero"); el héroe lo controla una IA. Destino: Steam, y mobile más adelante.

<!-- Nota para humanos: los comentarios HTML no cuestan tokens. Mantener este archivo corto (<80 líneas). Lo que solo aplica a ciertos archivos va en .claude/rules/ con `paths:`. -->

## Dónde está cada cosa
- Diseño del MVP: `docs/diseno-mvp.md`. Leelo solo si la tarea toca reglas o balance, no "por las dudas".
- Controles y cómo jugar: `README.md`.
- Decisiones ya tomadas: `/mnt/project-files/.notes/decisiones.md`. No las vuelvas a discutir.
- Mapa del repo: sección de abajo. Actualizala cuando agregues una carpeta o un sistema nuevo, así nadie tiene que explorar.

## Mapa del repo
<!-- Completar a medida que crece el proyecto: una línea por carpeta o sistema. -->
- `project.godot`: configuración (escena principal `scenes/main.tscn`).
- `scripts/balance.gd`: todos los números de balance. Para ajustar balance, tocá solo este archivo.
- `scripts/main.gd`: raíz de la partida (spawn de la horda, reloj, quién te caza y fin de partida).
- `scripts/creep.gd`: el jugador (absorber, mutar, evolucionar, ataques automáticos, embestida invulnerable).
- `scripts/heroes.gd`: los tres héroes (Arquero, Caballero, Maga; tabla `HEROES` en balance), llegadas por portal, "el más cercano" (`world.hero`), amanecer a los 15:00 y victoria.
- `scripts/hero.gd`: IA de un héroe (farmear, kitear, juntar XP, subir de nivel, retirarse, rodada, aviso de disparo).
- `scripts/hero_status.gd`: estados del héroe (sangrado, aturdido, lento) y registro de daño cuerpo a cuerpo / distancia.
- `scripts/events.gd`, `chest.gd`: cofres en disputa y eventos de oleada (estampida, asedio, luna de sangre).
- `scripts/puddle.gd`: charcos de Lluvia ácida.
- `scripts/infamy.gd`, `paladin.gd`: barra de Infamia y Paladín del cielo (te caza y cura al héroe).
- `scripts/creep_bot.gd`: bot del modo `--bot`.
- `scripts/hero_powers.gd`: poderes del héroe, uno por nivel, hasta 5 distintos (orbes, rayo, aura, nova y pasivos).
- `scripts/minion.gd`, `corpse.gd`, `gem.gd`, `projectile.gd`: horda, cadáveres, gemas de XP y flechas.
- `scripts/spit.gd`: escupitajos del creep y disparos de los arqueros de la horda.
- `scripts/civilian.gd`: civiles que huyen del creep (comida extra).
- `scripts/mutations.gd`: lista de mutaciones y evoluciones del creep, y sorteo de 3 opciones (evolución garantizada si está disponible; Festín de relleno).
- Modos de prueba: `-- --sim` (creep invulnerable) y `-- --bot` (bot juega). Federico prueba él mismo: no correr el bot en cada cambio.
- `scripts/hud.gd`, `arena.gd`: interfaz y fondo.
- Los `*.gd.uid` los genera Godot: no los leas ni los edites a mano.

## Comandos
- Simulación de balance de 15 min sin ventana: `godot --headless --fixed-fps 60 --quit-after 54600 res://scenes/main.tscn -- --sim 2>&1 | tail -n 40`
- Siempre filtrá la salida larga (`| tail`, `| grep -E "ERROR|WARN"`); no pegues logs completos al contexto.

## Cómo trabajar sin gastar tokens de más
- No leas `.godot/`, `*.import`, audio, fuentes ni builds: son generados o binarios (bloqueados en `.claude/settings.json`).
- Buscá con `rg` y leé solo el rango de líneas que necesitás; no abras escenas `.tscn` enteras si alcanza con un nodo.
- Exploraciones amplias: delegalas a un subagente y pedile solo la conclusión.
- Antes de cambios grandes, plan corto primero; evita intentos fallidos caros.
- Al cerrar una tarea larga, dejá lo que otro hilo necesite saber en `/mnt/project-files/.notes/` (la memoria del proyecto está desactivada).

## Git
- Autor de los commits: `Federico <fede.osorio@outlook.com.ar>`, sin línea `Co-Authored-By` de Claude (pedido de Federico).
- Mensajes de commit en español, cortos.
