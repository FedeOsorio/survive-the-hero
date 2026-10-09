---
paths:
  - "**/*.gd"
  - "**/*.tscn"
---
# GDScript

- Seguí el estilo del código existente: identificadores en inglés y `snake_case`, tipos inferidos con `:=` o explícitos (`-> void`, `: float`).
- Comentario `##` al inicio de cada script explicando qué hace; es lo que se lee para ubicarse sin abrir el archivo entero.
- Los números de balance van en `scripts/balance.gd`, no repartidos por los scripts.
- Un script por responsabilidad; si pasa de ~300 líneas, partilo y actualizá el mapa del repo en `CLAUDE.md`.
- En `.tscn`, editá el nodo puntual; no reescribas la escena entera.
