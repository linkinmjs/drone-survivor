## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Bus de señales global. Publica [b]hechos[/b], nunca comandos: solo el sistema
## dueño de un hecho lo emite, y cualquiera puede escucharlo sin acoplarse a él.
##
## Las 21 firmas de este archivo son el contrato canónico de `docs/02` §5.1 y son
## la fuente de verdad única del proyecto. Cambiar una firma exige actualizar
## primero ese documento; el documento dueño indicado en cada bloque es el único
## que puede proponer el cambio.
##
## Regla de Godot 4 que vuelve esto obligatorio: un [Callable] conectado a una
## señal debe aceptar [b]todos[/b] los argumentos que la señal emite. Puede
## ignorarlos prefijándolos con `_`, pero no puede omitirlos: conectar un método
## con menos parámetros falla en tiempo de ejecución, no al compilar.
##
## Idioma de conexión impuesto por `return_value_discarded=1`:
## [codeblock]
## var _discard := Events.enemy_part_broken.connect(_on_enemy_part_broken)
## [/codeblock]
extends Node

# --- Dron (dueños: docs/09 energía y casco, docs/08 arma, docs/03 vuelo) ---

## El dron recibió daño. [param source_position] es el origen del impacto, para
## que el HUD pueda dibujar la dirección del daño.
signal drone_damaged(amount: float, source_position: Vector3)

## El dron fue destruido en [param position]; arranca la secuencia de respawn.
signal drone_destroyed(position: Vector3)

## El dron volvió a volar. [param score_multiplier] es el castigo acumulado por
## morir, con piso 0.30 (`docs/09`).
signal drone_respawned(score_multiplier: float)

## Cambió la energía de la batería. [param ratio] va de 0.0 a 1.0 y
## [param critical] avisa de que se cruzó el umbral bajo.
signal energy_changed(ratio: float, critical: bool)

## Cambió la integridad del casco del dron, de 0.0 a 1.0.
signal hull_changed(ratio: float)

## Cambió el calor del arma. [param overheated] indica bloqueo por sobrecalentamiento.
signal weapon_heat_changed(ratio: float, overheated: bool)

## Se disparó un proyectil desde [param origin] en la dirección [param direction],
## que llega normalizada.
signal shot_fired(origin: Vector3, direction: Vector3)

## Un disparo impactó. [param weak] marca punto débil y [param lethal] marca que
## el impacto destruyó el objetivo.
##
## [param surface] dice **contra qué** pegó, con uno de estos cuatro valores:
##
## [codeblock]
## &"weak"   punto débil del enemigo (capa 4); implica weak = true
## &"armor"  blindaje del enemigo (capa 3, parte sin punto débil)
## &"city"   edificio de la ciudad (capa 8)
## &"world"  suelo, escombro o cualquier otra cosa (capas 1 y 9)
## [/codeblock]
##
## Lo agrega WP-26 porque sin él **nadie puede saber qué dibujar ni qué sonar**:
## el punto y los dos booleanos no distinguen una rodilla de una fachada, y
## `VFXPool` lo estaba deduciendo por cercanía al enemigo, que falla justamente
## cuando el jefe está parado encima del edificio al que le estás tirando. La
## superficie la deduce el emisor del collider, que es el único que la tiene.
##
## [b]`world` no viaja[/b] hoy: `docs/08` §2.7 no le da `HitKind` al suelo ni al
## escombro, así que [ProjectilePool] no confirma esos impactos. El valor existe
## en el dominio para que un emisor futuro no tenga que inventarlo y para que
## [method ProjectilePool.surface_for] sea total.
signal hit_confirmed(position: Vector3, weak: bool, lethal: bool, surface: StringName)

## El dron recogió una pila. [param amount] es la energía ganada, de 0.0 a 1.0.
signal battery_collected(amount: float, position: Vector3)

# --- Enemigos (dueño: docs/06) ---

## Apareció un enemigo. [param enemy_id] es su id de catálogo, estable para siempre.
signal enemy_spawned(enemy: Node3D, enemy_id: StringName)

## Se rompió y desprendió una parte del enemigo; su función asociada queda inhabilitada.
signal enemy_part_broken(enemy: Node3D, part_id: StringName, position: Vector3)

## Un punto débil quedó expuesto ([param exposed] verdadero) o volvió a cubrirse.
signal enemy_weak_point_state(enemy: Node3D, wp_id: StringName, exposed: bool)

## El enemigo entró en una fase nueva de su guion de combate.
signal enemy_phase_changed(enemy: Node3D, phase_id: StringName)

## El enemigo telegrafió un ataque; [param duration] es el tiempo de aviso en segundos.
signal enemy_attack_telegraphed(enemy: Node3D, attack_id: StringName, duration: float)

## El enemigo fue derrotado. Se emite exactamente una vez por enemigo.
signal enemy_defeated(enemy: Node3D, enemy_id: StringName)

# --- Ciudad (dueño: docs/10) ---

## Un edificio colapsó. [param value] es su peso en la integridad de la ciudad.
signal building_destroyed(position: Vector3, value: int)

## Cambió la integridad de la ciudad, de 0.0 a 1.0. Es monótona decreciente.
signal city_integrity_changed(ratio: float)

# --- Ronda (dueño: docs/11) ---

## Cambió el estado de la ronda. [param state] es un valor de `Global.RoundState`.
signal round_state_changed(state: int)

# --- Cámara (dueño: docs/13; lo emiten docs/06, 08, 09 y 10) ---

## Se pide sacudida de cámara. [param amount] es el trauma añadido, de 0.0 a 1.0,
## y [param position] permite atenuarlo por distancia.
signal camera_trauma(amount: float, position: Vector3)

# --- Reservadas para P3 (dueño: docs/14) ---
# Se declaran desde WP-01 aunque todavía nadie las emita, para cerrar el bus:
# `unused_signal` las reporta como advertencia, no como error.

## Un enemigo compartió la marca de un objetivo con sus aliados durante
## [param seconds] segundos.
signal enemy_mark_shared(enemy: Node3D, target_position: Vector3, seconds: float)

## Un enemigo pidió refuerzos; [param wave_id] identifica la oleada del catálogo.
signal enemy_wave_requested(enemy: Node3D, wave_id: StringName)
