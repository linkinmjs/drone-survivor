# 16 — Licencias y atribución

> Estado: borrador v1 · Fecha: 2026-09-19 · Gobierna: WP-01 (archivos de raíz) y la publicación · Depende de: `01-sala-limpia-y-reutilizacion.md`

## 1. Objetivo y alcance

Fijar la licencia del juego, registrar todas las atribuciones obligatorias y mantener la lista de verificaciones legales pendientes antes de publicar. No cubre el protocolo de sala limpia (ver `01`).

## 2. Licencia del juego

- **Código y contenido propio**: propietario, *todos los derechos reservados*, titular: el autor del proyecto (Mauri / estudio Ominoso). Archivo `LICENSE` en la raíz del repo con ese texto. Puede relajarse a MIT más adelante sin obstáculo, porque no hay código de terceros con copyleft.
- **Motor**: Godot Engine, licencia MIT. Debe mostrarse el aviso de Godot (y de sus componentes de terceros, `Engine.get_license_text()`) en la pantalla de ayuda o créditos del juego.
- **No hay código GPL**: el simulador `drone-simulator` (fork de `Cykyrios/GodotDrone`, GPL-3) no aporta código a este proyecto. Los archivos reutilizados son de autoría del usuario (lista cerrada en `01`) y se relicencian bajo la licencia de este repo. El repo del simulador sigue bajo GPL-3 sin cambios.

## 3. Atribuciones obligatorias (`CREDITS.md`)

| Recurso | Autor / fuente | Licencia | Obligación |
|---|---|---|---|
| `assets/audio/ui/boot_key.ogg`, `boot_enter.ogg` | Universal UI Soundpack, Nathan Gibson | CC BY 4.0 | Nombrar autor, obra, licencia y cambios en `CREDITS.md` y en la pantalla de créditos |
| Fuentes Recursive (`RecursiveSansLnrSt-Med.otf`, `RecursiveSansLnrSt-Bold.otf`, `RecursiveMonoLnrSt-Regular.otf`) | Arrow Type (Stephen Nixon) | SIL Open Font License 1.1 | Incluir el texto OFL junto a las fuentes; no vender las fuentes por separado |
| Fuentes nuevas de la identidad (elegidas en `13`) | según Google Fonts | OFL 1.1 (verificar cada una) | Ídem |
| Godot Engine | Juan Linietsky, Ariel Manzur y colaboradores | MIT | Aviso en créditos |
| Jolt Physics (integrado en Godot) | Jorrit Rouwe | MIT | Cubierto por el aviso de Godot |
| `assets/audio/ui/{back,click,error,hover,tick}.wav` | sintetizados por herramienta propia | propio | — |
| Sonidos de motores, armas, enemigos | sintetizados por herramienta propia o CC0 | propio / CC0 | Si son CC0, registrar la fuente por cortesía |

## 4. Packs de assets: verificación pendiente (bloquea la publicación, no el desarrollo)

| Pack | Archivos | Origen probable | Qué verificar |
|---|---|---|---|
| Mechas voxel (Arachnodroid, Companion-bot, FieldFighter, Mecha01, MechaTrooper, MechGolem, MobileStorageBot, QuadrupedTank, ReconBot) | `assets/_raw/*.zip`, `Mecha01.rar` (MagicaVoxel, 2020) | packs de un autor de itch.io/Sketchfab | Términos exactos de la página de descarga: uso comercial, modificación (segmentación y remallado), prohibición de redistribuir el asset suelto (el GLB generado y el `.vox` **no** deben publicarse fuera del build), crédito requerido |
| VoxelCity Free Sample | `assets/_raw/FreeSample.zip` (13 FBX + texturas) | muestra gratuita de un pack comercial | Términos de la muestra: uso en producto comercial, modificación (texturas reducidas), crédito; si la muestra no permite uso comercial, comprar el pack completo o reemplazar las piezas |

Hasta confirmar, los `.vox`, `.obj`, `.fbx` y texturas originales se mantienen solo en `assets/_raw/` (con `.gdignore`, fuera del export) y el repo **no se publica** en un remoto público.

## 5. Pendientes heredados del simulador (no se reutilizan)

| Elemento | Situación | Decisión |
|---|---|---|
| `sceneries/skies/sky.gdshader` | licencia sin identificar | No se copia; el cielo se hace de nuevo (`13`) |
| `gui/boot/Withheld Data.otf` | licencia no documentada | Sustituir por una fuente OFL en el boot salvo que el usuario confirme su origen |
| Modelos del dron y sonidos de motor | derivados del proyecto original (GPL-3) | No se copian; modelo voxel propio y audio sintetizado |

## 6. Archivos de raíz (WP-01)

- `LICENSE`: texto propietario ("Copyright (c) 2026 <titular>. Todos los derechos reservados. Se prohíbe la reproducción, distribución o modificación sin autorización escrita del titular.").
- `NOTICE`: "Este producto incluye Godot Engine (MIT) y componentes con licencia MIT/BSD/OFL/CC BY listados en CREDITS.md. No contiene código del proyecto GodotDrone ni de sus derivados."
- `CREDITS.md`: la tabla de §3 en formato de créditos, más los packs de §4 una vez confirmados.
- Pantalla de ayuda/créditos del juego: muestra `CREDITS.md` y `Engine.get_license_text()`.

## 7. Criterios de aceptación

- `LICENSE`, `NOTICE` y `CREDITS.md` existen y coinciden con este documento (`project_check` verifica su existencia).
- **El usuario confirma el nombre legal completo del titular** para el `Copyright (c) 2026 <titular>` de `LICENSE` y `NOTICE`. Hasta entonces WP-01 deja un `TODO` explícito en los dos archivos (`docs/02` D-7). Es un pendiente que **solo el usuario** puede cerrar.
- Antes del checkpoint 3, el usuario confirma los términos de los dos packs (§4) y se actualiza este documento con la fuente exacta y la licencia.
- Ningún asset de `assets/_raw/` entra en el export (`exclude_filter` en `02`).

## 8. Riesgos y decisiones abiertas

- Si un pack no permite uso comercial, el reemplazo es costoso (modelar mechas propios); por eso la verificación debe ocurrir en P1, no en P2.
- La relicencia de los archivos propios copiados del simulador es válida porque el autor conserva el copyright; si alguno resultara contener contribuciones de terceros, debe reimplementarse (registrar en `01`).

## 9. Referencias cruzadas

`01-sala-limpia-y-reutilizacion.md`, `02-configuracion-del-proyecto.md`, `13-identidad-visual-y-audio.md`, `05-pipeline-voxel.md`, `10-ciudad-destructible.md`.
