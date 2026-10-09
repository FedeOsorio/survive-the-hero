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
| Morder | Espacio | A |
| Embestida | Shift | B |
| Escupitajo (apunta solo al héroe si está a tiro) | Q | X |
| Evolucionar | E | Y |
| Reiniciar | R | Start |

## Estado actual: hito 1 (prototipo con formas)

- **Vos:** el círculo verde con anillo.
- **El héroe:** el cuadrado azul. Cuando sale de pantalla, una flecha azul te marca dónde está.
- **La horda:** los círculos marrones, verdes y rojos. Caminan hacia el héroe.
- **Al morir, cada creep deja:**
  - un cadáver: pasá por encima para absorberlo y ganar biomasa y vida;
  - una gema celeste: es experiencia para el héroe, y si te la comés primero se la robás.
- **Evolución:** con suficiente biomasa apretá E. Hay 4 etapas: Slime, Esqueleto, Cultista y Demonio.
- **Amenaza:** el héroe te ignora (sos un creep más) hasta que la barra se llena. Suben la amenaza morderlo, evolucionar y robarle gemas cerca de él. En el minuto 10 te detecta sí o sí.
- **Minuto 15:** el héroe se enfurece.

Todos los números de balance están en `scripts/balance.gd`. El diseño está en `docs/diseno-mvp.md`.

## Simulación de balance

Corre una partida de 15 minutos sin ventana, con el creep invulnerable, e imprime cómo progresa el héroe minuto a minuto:

```
godot --headless --fixed-fps 60 --quit-after 54600 res://scenes/main.tscn -- --sim
```
