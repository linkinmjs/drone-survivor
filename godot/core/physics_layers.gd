## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Catálogo estático de las capas de física 3D y de las máscaras de consulta de
## `docs/02` §3. Ningún sistema recalcula estos enteros a mano.
class_name PhysicsLayers extends RefCounted

## Bit de cada capa: `1 << (n - 1)` sobre la tabla de `docs/02` §3.1.
const WORLD: int = 1              ## Capa 1: suelo, terreno, rocas escalables.
const DRONE: int = 2              ## Capa 2: el dron del jugador.
const ENEMY_BODY: int = 4         ## Capa 3: partes blindadas del enemigo.
const ENEMY_WEAK: int = 8         ## Capa 4: puntos débiles expuestos.
const PROJECTILE_PLAYER: int = 16 ## Capa 5: reservada, proyectiles físicos (P3).
const PROJECTILE_ENEMY: int = 32  ## Capa 6: balística del enemigo.
const PICKUP: int = 64            ## Capa 7: pilas de batería.
const CITY: int = 128             ## Capa 8: edificios, calles y veredas.
const DEBRIS: int = 256           ## Capa 9: escombros desprendidos.
const TRIGGER: int = 512          ## Capa 10: volúmenes de ronda y límites de zona.
const ENEMY_SENSOR: int = 1024    ## Capa 11: reservada.

## Disparo del dron: `world | enemy_body | enemy_weak | city | debris`.
const QUERY_SHOT: int = 397

## Apoyo de pie del enemigo, hacia abajo: `world | city`.
const QUERY_FOOT: int = 129

## Línea de visión: `world | city`. No incluye `enemy_body`, de modo que un
## enemigo nunca se auto-ocluye.
const QUERY_LOS: int = 129

## Barrido y pisotón: `drone | city`.
const QUERY_SWEEP: int = 130
