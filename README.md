# Survive the Hero

Un survivor al revés: sos un creep de la horda, el héroe lo controla la IA. Te alimentás de los cadáveres que deja, evolucionás y al final lo matás.

## Cómo abrirlo

1. Instalá [Godot 4](https://godotengine.org/download) (4.7, versión estándar, no la .NET).
2. En Godot: **Importar** → elegí el archivo `project.godot` de esta carpeta.
3. Apretá **F5** para jugar.

## Controles

| Acción | Teclado | Joystick |
|---|---|---|
| Moverse | WASD o flechas | Stick izquierdo |
| Embestida | Espacio o Shift | RB |
| Evolucionar | E | Y |
| Elegir mutación | 1 / 2 / 3 | X / A / B |
| Reiniciar | R | Start |

La mordida y el escupitajo son automáticos: salen solos cuando el héroe o un civil está a tiro.

## Estado actual: hito 1 (prototipo con formas)

- **Vos:** el círculo verde con anillo.
- **El héroe:** el cuadrado azul. Cuando sale de pantalla, una flecha azul te marca dónde está.
- **La horda:** los círculos marrones, verdes y rojos. Caminan hacia el héroe.
- **Al morir, cada creep deja:**
  - un cadáver: pasá por encima para absorberlo y ganar biomasa y vida;
  - una gema celeste: es la única forma en que el héroe sube de nivel. No te alimenta, pero si la pisás antes que él, se la destruís.
- **Evolución:** con suficiente biomasa apretá E. Hay 4 etapas: Slime, Esqueleto, Cultista y Demonio.
- **Amenaza:** el héroe te ignora (sos un creep más) hasta que la barra se llena. Suben la amenaza morderlo, pisarle gemas o robarle corazones cerca de él, evolucionar y, de a poco, simplemente ser grande. No hay reloj: la partida dura lo que vos decidas.
- **Hambre:** si vas atrás del héroe en poder, cada bocado rinde más (se ve en el HUD).
- **Élites dorados:** aparecen cada 45 segundos. Cuando el héroe mata uno, deja un corazón rojo: si lo comés, ganás una mutación al instante.
- **El héroe:** ataca solo con flechas, esquiva tus escupitajos (no siempre) y se cura únicamente al subir de nivel. La horda lo desgasta, pero el golpe final lo tenés que dar vos.
- **Arqueros:** los creeps violetas atacan al héroe a distancia.
- **Mutaciones:** la biomasa también llena tu barra de nivel. Cada vez que subís, el juego se pausa y elegís 1 de 3 mejoras (las opciones están en `scripts/mutations.gd`).
- **Liderazgo:** los compañeros dentro de tu círculo verde se vuelven más rápidos y pegan más fuerte (se ven con borde verde).
- **Civiles:** los muñequitos amarillos deambulan lejos del héroe y huyen de vos. Comerlos da mucha biomasa.

Todos los números de balance están en `scripts/balance.gd`. El diseño está en `docs/diseno-mvp.md`.

## Simulación de balance

Corre una partida de 15 minutos sin ventana, con el creep invulnerable, e imprime cómo progresa el héroe minuto a minuto:

```
godot --headless --fixed-fps 60 --quit-after 54600 res://scenes/main.tscn -- --sim
```

Con `-- --bot`, en vez de `-- --sim`, el creep lo maneja un bot simple que come, evoluciona y ataca. Sirve para medir en qué minuto llega cada evolución.
