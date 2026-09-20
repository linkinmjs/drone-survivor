## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## IK analítico de dos huesos por ley del coseno (`docs/06` §8.2).
##
## Resuelve, **en el plano de la pata**, dónde cae la rodilla para que la punta
## de la cadena `fémur → tibia` alcance un objetivo. No toca nodos: es
## matemática pura y estática, así que se puede probar sin escena.
##
## [b]Geometría real del Arachnodroid[/b] (`arachnodroid.parts.json`, pose de
## reposo, 1 voxel = 0.75 m): la coxa pivota en (±4.875, 18.0, ∓6.375), el fémur
## en (±6.375, 17.25, ∓10.5), la rodilla —pivote de la tibia— en (±6, 9.75,
## ∓11.625) y el tobillo —pivote del pie— en (±6, 3.75, ∓11.625). Es decir:
## **cada nodo del GLB tiene su pivote en la articulación**, el hueso cuelga
## hacia `-Y` local y su longitud es la distancia entre su pivote y el del hijo:
## fémur **7.593 m** y tibia **6.0 m**. En reposo la cadena queda al 99.7 % de
## extensión (13.55 m de los 13.59 m disponibles), por eso la pose de marcha
## baja la cadera a `hip_height` y la rodilla se dobla de verdad.
##
## [b]Convención de flexión[/b]: el vector de polo [param pole] define hacia
## dónde sale la rodilla del segmento recto cadera→tobillo. El rig le pasa el
## eje lateral del cuerpo con un sesgo hacia atrás, así que las cuatro rodillas
## se arquean **hacia afuera y hacia atrás**, como una araña, y nunca hacia
## adentro (que es la pose que haría chocar las patas contra la carcasa).
##
## [b]Convención de las bases devueltas[/b]: `basis_a` y `basis_b` son bases de
## mundo con el hueso sobre **-Y** (la dirección en la que cuelgan los huesos
## del modelo) y la normal del plano de flexión sobre **+Z**. Como el fémur del
## modelo no cuelga exactamente sobre `-Y` —su hijo está en
## (0.375, -7.5, -1.125) local—, [Leg] no usa esas bases directamente: compone
## [member dir_a] / [member dir_b] con el marco de reposo de cada hueso. Las
## bases canónicas quedan para quien necesite el contrato literal de
## `docs/06` §14.
class_name TwoBoneIK extends RefCounted

## Holgura mínima entre el objetivo y la cadera: por debajo, la rodilla se
## doblaría 180° y `acos()` perdería precisión.
const MIN_GAP: float = 0.01

## Longitud por debajo de la cual un vector se considera degenerado.
const EPSILON: float = 0.000001


## Resuelve la cadena de dos huesos que arranca en [param root] y termina en
## [param target].
##
## [param len_a] es el fémur, [param len_b] la tibia, [param pole] el vector de
## polo (en mundo; no hace falta que sea unitario ni perpendicular) y
## [param stretch_max] el estiramiento máximo de la cadena antes de rendirse.
##
## [param knee_lift] (WP-24d, 0 por defecto) es el piso de elevación de la
## rodilla como fracción de la perpendicular más vertical de la cadena: con 0 la
## flexión la manda sólo el polo, como en `docs/06` §8.2; por encima de 0 la
## rodilla tiene garantizado salir hacia arriba aunque el objetivo quede del lado
## de dentro de la cadera.
##
## Devuelve `mid` (rodilla), `end` (punta alcanzada), `basis_a`, `basis_b`,
## `dir_a`, `dir_b`, `normal` (normal del plano de flexión), `stretched` (la
## cadena tuvo que estirarse) y `reachable` (llegó al objetivo pedido).
## Nunca devuelve `NaN`: todos los divisores están acotados.
static func solve(root: Vector3, target: Vector3, len_a: float, len_b: float,
		pole: Vector3, stretch_max: float, knee_lift: float = 0.0) -> Dictionary:
	var a := maxf(len_a, MIN_GAP)
	var b := maxf(len_b, MIN_GAP)
	var reach := a + b
	var limit := reach * maxf(stretch_max, 1.0)
	var to_target := target - root
	var raw := to_target.length()

	# Dirección hacia el objetivo. Con el objetivo pegado a la cadera no hay
	# dirección definida: se cuelga la pata hacia abajo antes que devolver NaN.
	var dir := Vector3.DOWN
	if raw > EPSILON:
		dir = to_target / raw

	# Plano de flexión: la componente del polo perpendicular a `dir`. Si el polo
	# es paralelo (pata perfectamente lateral) se toma cualquier perpendicular
	# estable.
	var side := pole - dir * pole.dot(dir)
	if side.length_squared() < EPSILON:
		side = dir.cross(Vector3.UP)
		if side.length_squared() < EPSILON:
			side = dir.cross(Vector3.RIGHT)
	side = side.normalized()

	# Piso de elevación de la rodilla (WP-24d). El polo define **hacia dónde**
	# sale la rodilla, pero su componente perpendicular a la cadena se inclina
	# con ella: si el objetivo queda del lado de dentro de la cadera, esa
	# componente apunta hacia abajo y la rodilla se dobla hacia adentro y hacia
	# el suelo —la pose que rompe la silueta de araña—. Con `knee_lift` la
	# dirección se inclina hacia la perpendicular **más vertical** que existe
	# para esta cadena, lo justo para que la rodilla nunca salga por debajo.
	if knee_lift > 0.0:
		var up_perp := Vector3.UP - dir * dir.dot(Vector3.UP)
		if up_perp.length_squared() > EPSILON:
			up_perp = up_perp.normalized()
			var floor_y := up_perp.y * knee_lift
			if side.y < floor_y and up_perp.y > side.y:
				var blend := clampf((floor_y - side.y) / (up_perp.y - side.y), 0.0, 1.0)
				var lifted := side.lerp(up_perp, blend)
				if lifted.length_squared() > EPSILON:
					side = lifted.normalized()

	var stretched := raw > reach
	var reachable := raw <= limit
	var d := clampf(raw, absf(a - b) + MIN_GAP, limit)
	var scale := 1.0
	if d > reach:
		# La cadena se estira en proporción en vez de despegar el pie
		# (`docs/06` §8.2): 1.15× son 15.63 m de alcance con 7.593 + 6.0.
		scale = d / reach
	var scaled_a := a * scale
	var scaled_b := b * scale

	# Ley del coseno sobre el triángulo (cadera, rodilla, tobillo).
	var cos_knee := clampf((scaled_a * scaled_a + d * d - scaled_b * scaled_b)
			/ (2.0 * scaled_a * d), -1.0, 1.0)
	var knee_angle := acos(cos_knee)
	var mid := root + (dir * cos(knee_angle) + side * sin(knee_angle)) * scaled_a
	var end := root + dir * d

	var dir_a := (mid - root)
	dir_a = dir_a.normalized() if dir_a.length_squared() > EPSILON else dir
	var dir_b := (end - mid)
	dir_b = dir_b.normalized() if dir_b.length_squared() > EPSILON else dir
	var normal := dir.cross(side)
	if normal.length_squared() < EPSILON:
		normal = Vector3.FORWARD
	normal = normal.normalized()

	return {
		"mid": mid,
		"end": end,
		"dir_a": dir_a,
		"dir_b": dir_b,
		"normal": normal,
		"basis_a": bone_basis(dir_a, normal),
		"basis_b": bone_basis(dir_b, normal),
		"stretched": stretched,
		"reachable": reachable,
		"stretch": scale,
	}


## Base canónica de un hueso que cuelga sobre `-Y` con la normal del plano de
## flexión sobre `+Z`.
static func bone_basis(direction: Vector3, normal: Vector3) -> Basis:
	var y_axis := -direction
	var z_axis := normal - y_axis * normal.dot(y_axis)
	if z_axis.length_squared() < EPSILON:
		z_axis = y_axis.cross(Vector3.RIGHT)
		if z_axis.length_squared() < EPSILON:
			z_axis = y_axis.cross(Vector3.FORWARD)
	z_axis = z_axis.normalized()
	return Basis(y_axis.cross(z_axis), y_axis, z_axis)


## Marco ortonormal cuya **primera columna** es [param primary] y cuya tercera
## es la normal del plano que forman [param primary] y [param reference].
##
## Es la pieza que permite orientar un hueso cuyo eje de reposo no coincide con
## ningún eje canónico: `marco_de_pose * marco_de_reposo.transposed()` lleva la
## dirección de reposo del hueso sobre la dirección pedida y arrastra el alabeo
## con el polo.
static func frame(primary: Vector3, reference: Vector3) -> Basis:
	var x_axis := primary.normalized() if primary.length_squared() > EPSILON else Vector3.DOWN
	var z_axis := x_axis.cross(reference)
	if z_axis.length_squared() < EPSILON:
		z_axis = x_axis.cross(Vector3.UP)
		if z_axis.length_squared() < EPSILON:
			z_axis = x_axis.cross(Vector3.RIGHT)
	z_axis = z_axis.normalized()
	return Basis(x_axis, z_axis.cross(x_axis), z_axis)
