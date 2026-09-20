## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Balance de una parte concreta de un enemigo (`docs/06` §3).
##
## El importador de `docs/05` §9.1 ya escribe `hp`, `armor`, `detachable`,
## `debris_mass` y `function` como metadatos de cada malla: eso es el **valor por
## defecto**. Este recurso es la **fuente de verdad del balance** y pisa lo que
## trajo el GLB, de modo que ajustar la pelea no obliga a reexportar el modelo
## (`docs/06` §2.1 punto 7). Se referencia desde
## [member EnemyProfile.part_overrides], indexado por [member part_id].
##
## Un campo que no se quiera pisar se deja tal cual: el override es total, así
## que el `.tres` repite siempre los cinco valores del import más los tres que
## sólo existen acá (`structure_weight`, `break_trauma`, `dust_scale`).
class_name EnemyPartProfile extends Resource

## Id de la parte. Debe coincidir con el `part_id` del GLB, que es también el
## nombre del nodo `MeshInstance3D` y la clave del diccionario de overrides.
@export var part_id: StringName = &""

## Puntos de vida de la parte. Con `armor` alto hacen falta muchísimos disparos:
## las partes blindadas existen para desprenderse y para dar retroalimentación
## de impacto, no para ser derribadas a tiros (`docs/07` §3).
@export_range(1.0, 100000.0, 1.0, "or_greater") var hp: float = 600.0

## Fracción del daño que absorbe el blindaje. El daño efectivo es
## `amount · (1 − armor)` con `armor` recortado a `[0.0, 0.99]` (`docs/06` §4).
@export_range(0.0, 0.99, 0.01) var armor: float = 0.90

## Si la parte se convierte en escombro al romperse ([method EnemyPart.detach]).
@export var detachable: bool = false

## Masa del `DebrisChunk` resultante, en kilogramos. Si vale 0 se usa la
## `estimated_mass` que el sidecar calculó por volumen de voxels (`docs/05` §4.2).
@export_range(0.0, 200000.0, 1.0, "or_greater") var debris_mass: float = 8000.0

## Función de la parte. Conjunto canónico: `leg`, `sensor`, `weapon`, `cosmetic`
## y `core` (`docs/06` §3). [EnemyBase] normaliza los sinónimos descriptivos del
## `parts.json` con una tabla de equivalencias.
@export var function: StringName = &"cosmetic"

## Peso de la parte en [method EnemyBase.total_structure_ratio]. **0 la deja
## fuera del cálculo**: es lo que hace el Arachnodroid con todo su blindaje, para
## que la integridad mida sólo los 12 000 HP de puntos débiles (`docs/07` §3).
@export_range(0.0, 10.0, 0.05) var structure_weight: float = 1.0

## Sacudida de cámara al romperse, para `Events.camera_trauma`.
@export_range(0.0, 2.0, 0.01) var break_trauma: float = 0.35

## Escala del polvo de rotura; la consume el VFX de `docs/13`.
@export_range(0.0, 5.0, 0.05) var dust_scale: float = 1.0
