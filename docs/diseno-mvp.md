# Survive the Hero: diseño del MVP

Documento vivo. Los números son un punto de partida para ajustar jugando.

## La idea en una línea

Un Vampire Survivors al revés: sos un creep más del montón, el héroe (IA) arrasa con todos, vos te alimentás de los cadáveres que deja, evolucionás y al final lo matás.

## Reglas de la partida

- **Duración:** 15 minutos.
- **Ganás** si matás al héroe.
- **Perdés** si morís o si llega el minuto 15 con el héroe vivo. En el minuto 15 el héroe entra en su forma final y te arrasa.
- **Mapa:** una arena cerrada de unos 3000x3000 px con algunos obstáculos para esconderse y rodear.

## Las tres fases

| Fase | Minutos | Qué siente el jugador |
|---|---|---|
| Sigilo | 0–5 | Soy un bicho más. Me escondo entre la horda, robo cadáveres y evito quedar como el creep más cercano. |
| Crecimiento | 5–10 | Ya evolucioné un par de veces. Puedo pelearle cadáveres al héroe y hostigarlo, pero si me ve me castiga. |
| Duelo | 10–15 | El héroe me detectó y me caza. Es él contra mí, y la horda es mi escudo y mi arma. |

**Detección:** el héroe ignora al creep hasta que su "amenaza" supera un umbral. La amenaza sube por:
- etapa de evolución,
- daño hecho al héroe,
- cadáveres y experiencia robados cerca de él.

Si nada de eso la dispara antes, la detección es forzada en el minuto 10. Cuando te detecta, aparece un aviso claro en pantalla ("¡El héroe te vio!").

## Por qué el creep puede crecer más rápido que el héroe

El héroe progresa como en un survivor normal: cada nivel le pide más experiencia y sus mejoras suman de a poco. El creep tiene tres ventajas:

1. **Cada evolución multiplica, no suma.** Una evolución es un salto de stats de ×1,6 a ×2, y además cambia cómo se juega.
2. **Le roba al héroe.** Cada creep que muere deja una gema de experiencia (para el héroe) y un cadáver (para vos). Si comés la gema antes que él, se la negás. Robar es arriesgado y rinde mucho.
3. **Los cadáveres grandes valen más.** Las oleadas tardías traen enemigos más fuertes, que valen más biomasa.

Objetivo de balance: en el minuto 10 el creep le hace al héroe más o menos el 40% del daño que el héroe le hace a él. En el minuto 13 están parejos.

## El creep

- **Stats base:** 30 de vida, velocidad 1,15 veces la del héroe (para poder esquivar) y daño por contacto bajo.
- **Biomasa:** sale de los cadáveres y se usa para evolucionar.
- **Evolución:** 4 etapas. En cada etapa elegís entre 2 o 3 formas, y eso da 10–15 formas en total.
  - Etapa 1: Slime o Esqueletito (inicial)
  - Etapa 2: 3 formas
  - Etapa 3: 4 formas
  - Etapa 4: 4 formas finales (demonios)
- **5 habilidades** (borrador):
  - Embestida: un dash corto.
  - Mordida: golpe cuerpo a cuerpo que además absorbe.
  - Escupitajo ácido: proyectil.
  - Llamado de la horda: los creeps cercanos se lanzan contra el héroe.
  - Camuflaje: baja tu amenaza durante unos segundos.

## El héroe (IA)

Funciona con utilidad: cada medio segundo puntúa sus opciones y elige la mejor, con algo de ruido.

- **Comportamientos:**
  - Farmear el grupo más denso.
  - Juntar gemas de experiencia.
  - Kitear (retroceder disparando).
  - Retirarse y curarse con poca vida.
  - Elegir una mejora al subir de nivel.
  - Cazar al creep (solo después de la detección).
- **Cómo elige objetivo:** el puntaje combina distancia, qué tan fácil es matarlo y amenaza. Antes de detectarte, sos un creep más.
- **Errores humanos:**
  - Tarda 150–300 ms en reaccionar.
  - Su puntería tiene un pequeño error.
  - A veces se distrae farmeando cuando debería cazarte.
  - A veces se mete en un grupo con poca vida.
- **5 armas** (borrador):
  - Espada giratoria (área).
  - Arco (al enemigo más cercano).
  - Bola de fuego (contra grupos).
  - Aura sagrada (daño pasivo alrededor).
  - Rayo en cadena.

## Horda

10 tipos de enemigos con roles distintos: rápidos, tanques, a distancia, enjambre y explosivos. Van hacia el héroe en oleadas cada vez más fuertes. Para el héroe, cada uno da experiencia. Para vos, cada uno deja un cadáver que dura unos 20 segundos en el suelo.

## Hito 1: qué entra

- Proyecto Godot 4 con la arena, la cámara siguiendo al creep y control con teclado o joystick.
- Héroe simple: camina hacia el creep compañero más cercano y lo ataca con un arma básica.
- 2 o 3 tipos de enemigos con formas simples, en oleadas.
- Cadáveres, gemas de experiencia, biomasa y una evolución de ejemplo.
- Detección básica: el umbral de amenaza o el minuto 10.
- Condiciones de victoria y derrota, y un HUD mínimo (vida, biomasa y reloj).

**Pregunta que tiene que responder:** ¿esconderse entre la horda y robarle al héroe ya es divertido?
