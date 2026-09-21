## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Texturas procedurales de los efectos (`docs/13` §4: «sin assets externos»).
##
## Todas se generan una sola vez y se cachean en un [Dictionary] estático: las
## diecisiete escenas de `vfx/` comparten cinco imágenes, no tienen diecisiete
## copias. Son chicas a propósito —32 a 128 px— porque una partícula de chispa
## ocupa ocho píxeles en pantalla y un decal de cráter se ve borroso igual.
##
## Sala limpia: nada de esto sale de ningún pack de terceros (`docs/01`).
class_name VFXTextures


## Caché de texturas ya generadas, indexada por clave.
static var _cache: Dictionary[StringName, Texture2D] = {}


## Chispa: punto blanco con caída cuadrática. Es la que usan todos los
## `GPUParticles3D` de chispa, teñidos por el `color` del proceso.
static func spark() -> Texture2D:
	return _cached(&"spark", func() -> Texture2D:
		return _radial(32, 0.0, 1.0, 2.6, Color(1.0, 1.0, 1.0, 1.0)))


## Polvo: mancha muy suave y gris, para las partículas planas de pisada y
## derrumbe. La caída es lineal, que es lo que la hace parecer volumen.
static func dust() -> Texture2D:
	return _cached(&"dust", func() -> Texture2D:
		return _radial(64, 0.0, 1.0, 1.15, Color(1.0, 1.0, 1.0, 1.0)))


## Humo: como el polvo pero con el centro vaciado, para que la columna se lea
## como bocanadas y no como una nube maciza.
static func smoke() -> Texture2D:
	return _cached(&"smoke", func() -> Texture2D:
		var side := 64
		var image := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
		var centre := float(side - 1) * 0.5
		for y: int in side:
			for x: int in side:
				var dx := (float(x) - centre) / centre
				var dy := (float(y) - centre) / centre
				var r := sqrt(dx * dx + dy * dy)
				var alpha := clampf(1.0 - smoothstep(0.15, 1.0, r), 0.0, 1.0)
				alpha *= lerpf(0.55, 1.0, smoothstep(0.0, 0.45, r))
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
		return ImageTexture.create_from_image(image))


## Esquirla: cuadrado con los bordes comidos, para las astillas de hormigón.
static func shard() -> Texture2D:
	return _cached(&"shard", func() -> Texture2D:
		var side := 32
		var image := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
		for y: int in side:
			for x: int in side:
				var dx := absf(float(x) / float(side - 1) - 0.5) * 2.0
				var dy := absf(float(y) / float(side - 1) - 0.5) * 2.0
				var edge := maxf(dx, dy)
				var alpha := 1.0 if edge < 0.82 else clampf(1.0 - (edge - 0.82) / 0.18, 0.0, 1.0)
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
		return ImageTexture.create_from_image(image))


## Marca de quemadura del impacto en blindaje: disco oscuro con borde difuso.
static func burn() -> Texture2D:
	return _cached(&"burn", func() -> Texture2D:
		var side := 64
		var image := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
		var centre := float(side - 1) * 0.5
		for y: int in side:
			for x: int in side:
				var dx := (float(x) - centre) / centre
				var dy := (float(y) - centre) / centre
				var r := sqrt(dx * dx + dy * dy)
				var alpha := clampf(1.0 - smoothstep(0.30, 1.0, r), 0.0, 1.0)
				var shade := lerpf(0.02, 0.22, clampf(r, 0.0, 1.0))
				image.set_pixel(x, y, Color(shade, shade, shade, alpha))
		return ImageTexture.create_from_image(image))


## Anillo de zona del pisotón: borde grueso y relleno tenue, para que el jugador
## lea a la vez **dónde termina** el golpe y **qué superficie** cubre.
static func zone_ring() -> Texture2D:
	return _cached(&"zone_ring", func() -> Texture2D:
		var side := 128
		var image := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
		var centre := float(side - 1) * 0.5
		for y: int in side:
			for x: int in side:
				var dx := (float(x) - centre) / centre
				var dy := (float(y) - centre) / centre
				var r := sqrt(dx * dx + dy * dy)
				# **El borde manda y el relleno acompaña.** El dato accionable es
				# «dónde termina la zona», no «qué superficie cubre»: con el
				# relleno al 26 % que tenía la primera versión, un decal de 18 m
				# se leía como una mancha roja sobre la calle entera y el borde
				# desaparecía (fotograma 199 del showcase del jefe). Ahora el
				# borde es una banda opaca de 0.14 y el relleno baja al 10 %.
				var rim := clampf(1.0 - absf(r - 0.90) / 0.14, 0.0, 1.0)
				var fill := 0.10 * clampf(1.0 - smoothstep(0.82, 1.0, r), 0.0, 1.0)
				# Cuatro marcas de mira a 45°, que es lo que hace que el anillo se
				# lea como una zona de peligro y no como un charco.
				var angle := atan2(dy, dx)
				var tick := 0.0
				if r > 0.58 and r < 0.84:
					tick = 0.70 * clampf(1.0 - absf(fmod(absf(angle) + PI * 0.25,
							PI * 0.5) - PI * 0.25) / 0.09, 0.0, 1.0)
				var alpha := clampf(maxf(maxf(rim, fill), tick), 0.0, 1.0)
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
		return ImageTexture.create_from_image(image))


## Marca de cráter que queda tras el pisotón: polvo claro con grietas oscuras.
##
## **Claro y no oscuro.** La primera versión era un disco oscuro con grietas
## oscuras y sobre el asfalto al anochecer no se veía nada (fotograma 210 del
## showcase del jefe). Un cráter real levanta polvo de hormigón, que es más claro
## que la calzada: el disco va en gris claro y las once grietas en casi negro.
##
## **Segunda pasada**: con 0.72 en el centro tampoco se leía, porque el pisotón
## cae casi siempre dentro de la sombra del propio coloso y un `Decal` de albedo
## sin luz encima sigue siendo oscuro. Ahora el polvo llega a 0.95 —cuatro veces
## el albedo del asfalto— y el `Decal` lo acompaña con una emisión tenue que le
## da el rescoldo de los primeros segundos.
static func crater() -> Texture2D:
	return _cached(&"crater", func() -> Texture2D:
		var side := 128
		var image := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
		var centre := float(side - 1) * 0.5
		# Semilla fija: dos partidas dejan el mismo cráter (`docs/00` §6).
		var rng := RandomNumberGenerator.new()
		rng.seed = 0x5C0FFEE
		var cracks: PackedFloat32Array = PackedFloat32Array()
		for _i: int in 11:
			cracks.append(rng.randf_range(-PI, PI))
		for y: int in side:
			for x: int in side:
				var dx := (float(x) - centre) / centre
				var dy := (float(y) - centre) / centre
				var r := sqrt(dx * dx + dy * dy)
				var alpha := clampf(1.0 - smoothstep(0.30, 1.0, r), 0.0, 1.0) * 0.9
				var shade := lerpf(0.95, 0.58, clampf(r, 0.0, 1.0))
				var angle := atan2(dy, dx)
				for crack: float in cracks:
					var delta := absf(angle_difference(angle, crack))
					if delta >= 0.055 or r >= 0.96:
						continue
					var strength := clampf(1.0 - delta / 0.055, 0.0, 1.0)
					alpha = maxf(alpha, strength * 0.95)
					shade = lerpf(shade, 0.04, strength)
				image.set_pixel(x, y, Color(shade, shade, shade, clampf(alpha, 0.0, 1.0)))
		return ImageTexture.create_from_image(image))


## Halo suave para el destello de la pila y el del punto débil.
static func halo() -> Texture2D:
	return _cached(&"halo", func() -> Texture2D:
		return _radial(64, 0.05, 1.0, 1.8, Color(1.0, 1.0, 1.0, 1.0)))


## Borra la caché. La usan los checks para no arrastrar texturas entre corridas.
static func clear_cache() -> void:
	_cache.clear()


# --- Internos ---------------------------------------------------------------------------------

## Devuelve la textura de [param key], generándola con [param factory] la primera
## vez.
static func _cached(key: StringName, factory: Callable) -> Texture2D:
	var found: Texture2D = _cache.get(key, null)
	if found != null:
		return found
	var made := factory.call() as Texture2D
	_cache[key] = made
	return made


## Disco con caída `pow(1 - r, falloff)` entre [param from] y [param to].
static func _radial(side: int, from: float, to: float, falloff: float,
		tint: Color) -> Texture2D:
	var image := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	var centre := float(side - 1) * 0.5
	for y: int in side:
		for x: int in side:
			var dx := (float(x) - centre) / centre
			var dy := (float(y) - centre) / centre
			var r := clampf((sqrt(dx * dx + dy * dy) - from) / maxf(to - from, 0.0001),
					0.0, 1.0)
			var alpha := pow(clampf(1.0 - r, 0.0, 1.0), falloff)
			image.set_pixel(x, y, Color(tint.r, tint.g, tint.b, alpha * tint.a))
	return ImageTexture.create_from_image(image)
