## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Prop de la pila de energía (`docs/09` §2.4 y §3.1, `docs/13` §4).
##
## Reemplaza al `BoxMesh` cian placeholder de `drone/energy/battery_pickup.tscn`
## sin tocar su colisión, su capa ni su API: la escena sólo cambia lo que se ve.
##
## La celda es **procedural** y no un `.glb` importado: `docs/09` §2.4 pedía
## `assets/drone/battery_cell.glb`, que no existe y que WP-26 no puede crear sin
## salirse de la sala limpia (`docs/01`). Una celda es un cilindro con un casquete
## y una banda, o sea tres primitivas, y generarla acá cuesta menos que importar
## un archivo que habría que licenciar.
##
## [b]Tres draw calls[/b]. Las tres piezas son [MultiMeshInstance3D] y no once
## [MeshInstance3D]: con las cinco pilas que mantiene activas el `BatterySpawner`,
## la versión de once nodos costaba **+77 draw calls** medidos en `render_check`
## (828 → 905, por encima del presupuesto de 900 de `docs/13` §9). Con `MultiMesh`
## el prop entero cuesta tres, y el casquillo se distingue por color de instancia
## en vez de por un material aparte.
##
## [b]El halo es de malla, no de partículas[/b]. `docs/13` §4 presupuesta 12
## emisores para toda la escena y el spawner mantiene **cinco** pilas activas: un
## halo de [GPUParticles3D] por pila se llevaría cinco de los doce —o cinco de los
## seis de LOW— sólo para que unas motas giren alrededor de un objeto decorativo.
## Las seis motas son seis instancias de un `MultiMesh` que orbitan en `_process`,
## con **cero** coste de presupuesto. Ver la discrepancia #4 del informe de WP-26.
class_name BatteryCell extends Node3D

## Motas del halo (`docs/13` §4: «halo de 6 partículas lentas»).
const MOTE_COUNT: int = 6

## Vueltas por segundo del halo. Lentas: la pila flota, no vibra.
const MOTE_SPEED: float = 0.22

## Radio de la órbita de las motas, en metros.
const MOTE_RADIUS: float = 0.55

## Amplitud del vaivén vertical de cada mota, en metros.
const MOTE_BOB: float = 0.18

## Colores de instancia del casco: cuerpo oscuro, casquillo y borne metálicos.
const SHELL_COLORS: Array[Color] = [
	Color(0.26, 0.30, 0.28, 1.0),
	Color(1.00, 1.00, 1.00, 1.0),
	Color(0.88, 0.90, 0.86, 1.0),
]

## Anillos emisivos: altura de cada uno sobre el centro de la celda, en metros.
const BAND_HEIGHTS: Array[float] = [0.2, -0.18]

@onready var _shell: MultiMeshInstance3D = get_node_or_null(^"Shell") as MultiMeshInstance3D
@onready var _bands: MultiMeshInstance3D = get_node_or_null(^"Bands") as MultiMeshInstance3D
@onready var _halo: MultiMeshInstance3D = get_node_or_null(^"Halo") as MultiMeshInstance3D

var _phase: float = 0.0


func _ready() -> void:
	_build_shell()
	_build_bands()
	_place_motes(0.0)


## Órbita del halo. Presentación pura, y se apaga sola cuando la pila se
## desactiva: [method BatteryPickup.deactivate] la esconde, y un nodo invisible no
## tiene por qué seguir calculando senos.
func _process(delta: float) -> void:
	if _halo == null or not is_visible_in_tree():
		return
	_phase = fmod(_phase + delta * MOTE_SPEED, 1.0)
	_place_motes(_phase)


## Cuerpo, casquillo y borne: tres instancias del mismo cilindro, con escalas y
## colores distintos. El escalón del casquillo es lo que hace que la silueta se
## lea como una pila y no como un poste.
func _build_shell() -> void:
	if _shell == null or _shell.multimesh == null:
		return
	var mesh := _shell.multimesh
	var pieces: Array[Transform3D] = [
		Transform3D(Basis.IDENTITY, Vector3.ZERO),
		Transform3D(Basis().scaled(Vector3(0.74, 0.18, 0.74)), Vector3(0.0, 0.48, 0.0)),
		Transform3D(Basis().scaled(Vector3(0.36, 0.16, 0.36)), Vector3(0.0, 0.62, 0.0)),
	]
	for index: int in mini(mesh.instance_count, pieces.size()):
		mesh.set_instance_transform(index, pieces[index])
		mesh.set_instance_color(index, SHELL_COLORS[index])


## Los dos anillos emisivos, arriba y abajo del cuerpo.
func _build_bands() -> void:
	if _bands == null or _bands.multimesh == null:
		return
	var mesh := _bands.multimesh
	for index: int in mini(mesh.instance_count, BAND_HEIGHTS.size()):
		mesh.set_instance_transform(index,
				Transform3D(Basis.IDENTITY, Vector3(0.0, BAND_HEIGHTS[index], 0.0)))


## Coloca las seis motas en su órbita para la fase [param phase], de 0 a 1.
func _place_motes(phase: float) -> void:
	if _halo == null or _halo.multimesh == null:
		return
	var mesh := _halo.multimesh
	var count := maxi(mesh.instance_count, 1)
	for index: int in mesh.instance_count:
		var share := float(index) / float(count)
		var angle := TAU * (phase + share)
		# Cada mota sube y baja en una fase distinta: el halo respira en vez de
		# girar como un plato.
		var bob := sin(TAU * (phase * 2.0 + share)) * MOTE_BOB
		mesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, Vector3(
				cos(angle) * MOTE_RADIUS, bob, sin(angle) * MOTE_RADIUS)))
