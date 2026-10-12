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
- `project.godot`: configuración (escena principal `scenes/menu.tscn`; la partida es `scenes/main.tscn`; autoload `Settings`).
- `scripts/balance.gd`: todos los números de balance. Para ajustar balance, tocá solo este archivo.
- `scripts/main.gd`: raíz de la partida (spawn de la horda, reloj, quién te caza y fin de partida).
- `scripts/creep.gd`: el jugador, en cadena de herencia: `creep_base.gd` (variables, rangos, stats, `pmult`/`pcd` de los poderes) → `creep_growth.gd` (comer, mutar, evolucionar) → `creep.gd` (moverse, mordida, embestida invulnerable, daño, dibujo; es el que se instancia).
- `scripts/heroes.gd`: los tres héroes (Arquero, Caballero, Maga; tabla `HEROES` en balance), llegadas por portal, "el más cercano" (`world.hero`), amanecer a los 15:00 y el paso al Último Bastión.
- `scripts/hero.gd`: un héroe, en cadena de herencia (cada pieza extiende la anterior):
  - `hero_base.gd`: todas las variables y consultas chicas (rolling, hunting_you, blocks_from, nombres).
  - `hero_combat.gd`: rodada, tajo, disparos, daño recibido, furia, XP y subir de nivel.
  - `hero_brain.gd`: sospecha, estados de vista (farmear, cazarte, buscarte) y `_think`: a qué tirar y un solo objetivo por vez en lista de prioridades (furia, caza, escape, `_goal`: grito cerca, cofre, corazón, gemas, grito lejos, búsqueda, farmear).
  - `hero.gd`: `_ready`, `setup`, `_process` y `_draw`. Es el que se instancia (heroes.gd).
- `scripts/bastion.gd`: Último Bastión (jefe final 1 contra 1: pared de luz, fases, carne, barra de vida en capa propia; reusa `hero_attacks.gd`).
- `scripts/hero_traits.gd`: mecánica propia de cada héroe (trampas del Arquero, escudo y hachas giratorias del Caballero, parpadeo de la Maga).
- `scripts/hero_fury.gd` (`hero.rage`): furia propia de cada héroe (Arquero: dispara el doble y se cura al matar; Caballero: robo de vida cuerpo a cuerpo; Maga: escudo de maná y hechizos extra).
- `scripts/hero_attacks.gd`: ataques de jefe del héroe (zona roja, golpe a la horda y a vos, esquive que te delata; tabla `HERO_ATTACKS` en balance).
- `scripts/hero_status.gd`: estados del héroe (sangrado, aturdido, lento) y registro de daño cuerpo a cuerpo / distancia.
- `scripts/events.gd`, `chest.gd`: cofres en disputa y eventos de oleada (estampida, asedio, luna de sangre).
- `scripts/puddle.gd`: charcos de Lluvia ácida.
- `scripts/infamy.gd`, `paladin.gd`: barra de Infamia y Paladín del cielo (te caza y cura al héroe).
- `scripts/creep_bot.gd`: bot del modo `--bot`.
- `scripts/hero_powers.gd`: poderes del héroe, uno por nivel, hasta 5 distintos (orbes, rayo, aura, nova y pasivos).
- `scripts/minion.gd`, `corpse.gd`, `gem.gd`, `projectile.gd`: horda, cadáveres, gemas de XP y flechas.
- `scripts/spit.gd`: escupitajos del creep y disparos de los arqueros de la horda.
- `scripts/civilian.gd`: civiles que huyen del creep (comida extra).
- `scripts/mutations.gd`: mejoras al subir de nivel estilo HoloCure: stats (`LIST`), poderes de la clase (`CLASS_POWERS` en balance: 10 por clase, el primero fijo, hasta 5 con 5 rangos) y sorteo de 3 cartas (poder nuevo / rango / stat; Mandíbula sangrienta como única evolución; Festín de relleno).
- Modos de prueba: `-- --sim` (creep invulnerable) y `-- --bot` (bot juega); como la escena principal es el menú, hay que pasar `res://scenes/main.tscn` antes del `--`. Federico prueba él mismo: no correr el bot en cada cambio.
- `scripts/hud.gd`, `arena.gd`: interfaz y fondo.
- `scripts/menu.gd` (`scenes/menu.tscn`), `pause.gd`, `options_menu.gd`, `ui.gd`: menú principal, pausa y botones de la pantalla final, Opciones y piezas de UI compartidas.
- `scripts/creep_abilities.gd` (`player.abilities`): poderes del Engendro (Escupitajo, Huesos, Detonar, Aliento, Llamado; Espinas, Coraza y Pegote en su hijo `engendro_body.gd`; Lluvia ácida en `spit.gd`, Señor de la carroña en `main.gd`) y la tecla C hacia la clase. Números en "Habilidades del creep" al final de `balance.gd`.
- `scripts/creep_class.gd` (`player.klass`): clase del Anti Hero elegida en el menú; la base es el Engendro y expone ganchos (`on_eat`, `take_hit`, `ability` en C, `hp_text`). Clases: `class_abyss.gd` (Abisal: grietas y Agarre, Azote, Fauces, Aplastar, Marea; el resto de sus poderes y el tentáculo de cada grieta en `abyss_powers.gd`) y `class_swarm.gd` (Reina del enjambre: los insectos son la vida, Escudo de insectos automático, Espinas de la Reina, Caparazón le da insectos, y sus 10 poderes). El HUD muestra la fila de poderes. Cartas del menú en `class_select.gd`; números en la sección "Clases del Anti Hero" al final de `balance.gd`; para probar una clase: `-- --class=abisal`.
- `scripts/bushes.gd` (`world.bushes`): arbustos para esconderte; `world.player_hidden(h)` junta camuflaje y arbustos (cazándote, el arbusto solo te esconde lejos de "h").
- `scripts/mutation_picker.gd`: elección de mutación (hijo del HUD): cartas con clic, stick/flechas + A/Enter, 1/2/3 y X/A/B, bloqueo de 0,3 s al abrir.
- `scripts/fx.gd` (`world.fx`): jugo visual (partículas al morir, números de daño que recibís, hit-stop, cámara lenta, anillos al mutar/evolucionar, columna al subir el héroe). Números en la sección FX al final de `balance.gd`.
- `scripts/settings.gd` (autoload `Settings`): opciones en `user://options.cfg`, acción "pause" y contador de FPS. `records.gd`: mejor resultado en `user://records.cfg`.
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
