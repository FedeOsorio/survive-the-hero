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
| Camuflaje (el héroe te pierde de vista, 1 vez por minuto) | Q | LB |
| Evolucionar | E | Y |
| Elegir mutación | 1 / 2 / 3 | X / A / B |
| Reiniciar | R | Start |

La mordida y el escupitajo son automáticos: salen solos cuando el héroe o un civil está a tiro.

## Estado actual: hito 1 (prototipo con formas)

- **Vos:** el círculo verde con anillo.
- **El héroe:** el cuadrado azul. Cuando sale de pantalla, una flecha azul te marca dónde está.
- **La horda:** los círculos marrones, verdes y rojos. Caminan hacia el héroe y cada 2 minutos son más duros, más rápidos y pegan más.
- **Al morir, cada creep deja:**
  - un cadáver: pasá por encima para absorberlo y ganar biomasa y vida;
  - una gema celeste: es la única forma en que el héroe sube de nivel. No te alimenta, pero si la pisás antes que él, se la destruís.
- **Evolución:** con suficiente biomasa apretá E. Hay 4 etapas: Slime, Esqueleto, Cultista y Demonio.
- **Amenaza:** el héroe te ignora (sos un creep más) hasta que la barra se llena. Suben la amenaza morderlo, pisarle gemas o robarle corazones cerca de él, evolucionar y, de a poco, simplemente ser grande. No hay reloj: la partida dura lo que vos decidas.
- **Hambre:** si vas atrás del héroe en poder, cada bocado rinde más (se ve en el HUD).
- **Élites dorados:** aparecen cada 45 segundos. Cuando el héroe mata uno, deja un corazón rojo: si lo comés, ganás una mutación al instante. Él también lo va a buscar: si lo agarra primero, sube un nivel y se cura.
- **El héroe:** ataca con flechas, esquiva tus escupitajos (no siempre) y se cura únicamente al subir de nivel. En cada nivel gana un poder (hasta 5 distintos): orbes de fuego que giran a su alrededor, rayos (marcan un círculo antes de caer), aura sagrada, nova (avisa con un anillo), flechas perforantes, lluvia de flechas o botas. Los poderes de área también te lastiman; la embestida te hace invulnerable. La horda lo desgasta, pero el golpe final lo tenés que dar vos.
- **Arqueros:** los creeps violetas atacan al héroe a distancia.
- **Mutaciones:** la biomasa también llena tu barra de nivel. Cada vez que subís, el juego se pausa y elegís 1 de 3 mejoras (las opciones están en `scripts/mutations.gd`).
- **Liderazgo:** los compañeros dentro de tu círculo verde se vuelven más rápidos y pegan más fuerte (se ven con borde verde).
- **Civiles:** los muñequitos amarillos deambulan lejos del héroe y huyen de vos. Comerlos da mucha biomasa, pero gritan apenas empiezan a huir y el héroe va hacia ahí a matarlos (los que mata él no dejan cadáver). Comerlos además sube tu amenaza.
- **Infamia y Paladín:** la barra dorada debajo de la amenaza sube cuando el héroe no puede con vos: cada civil que matás, cada segundo que sobrevivís detectado y cada vez que lo hacés retirarse. Al llenarse, una columna de luz anuncia un Paladín del cielo (y si seguís, refuerzos: hasta 3 a la vez) que te caza y cura al héroe si están cerca: separalos. Si lo matás, su corazón celestial te da una mutación y biomasa.
- **Evoluciones:** una mutación al máximo + su pareja (la carta dice "Evoluciona con...") desbloquea una evolución dorada: Lluvia ácida, Mandíbula sangrienta, Señor de la carroña o Coraza viva.
- **Cofres:** desde el minuto 1:30 aparece un cofre cada tanto (flecha dorada). Quedate 1 segundo encima sin recibir daño: si lo abrís, mutación gratis; si lo abre el héroe, sube de nivel.
- **Eventos:** desde el minuto 2, cada minuto y medio: Estampida (ola de ratas), Asedio (anillo de zombis alrededor del héroe) y Luna de sangre (la horda pega el doble 30 s).
- **El héroe se adapta:** cuando te detectó, elige poderes contra tu forma de pelear (aura y nova si lo mordés, rayo y botas si le escupís).

Todos los números de balance están en `scripts/balance.gd`. El diseño está en `docs/diseno-mvp.md`.

## Simulación de balance

Corre una partida de 15 minutos sin ventana, con el creep invulnerable, e imprime cómo progresa el héroe minuto a minuto:

```
godot --headless --fixed-fps 60 --quit-after 54600 res://scenes/main.tscn -- --sim
```

Con `-- --bot`, en vez de `-- --sim`, el creep lo maneja un bot simple que come, evoluciona y ataca. Sirve para medir en qué minuto llega cada evolución.
