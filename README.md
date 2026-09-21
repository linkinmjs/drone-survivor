# Drone Survivor

Juego de acción en primera persona en el que se pilota un **dron FPV de combate** y
se defiende una ciudad voxel de colosos mecánicos. Cada enemigo es enorme (20–45 m),
lento de matar y peligroso: hay que volar a su alrededor, encontrar sus puntos
débiles, romper sus partes —que se desprenden y caen— y sobrevivir administrando la
energía con pilas repartidas por el mapa.

Los pilares del proyecto son el **pilotaje real** (acro y horizon, rates
configurables, calibración por dispositivo), **colosos que se leen** (telegrafían
sus ataques y pierden partes de forma visible), **la ciudad como reloj** (su
integridad es la condición de derrota) y una **presentación AAA** sobre un estilo
voxel coherente.

El detalle completo de la visión, el alcance del MVP y la hoja de ruta está en
[`godot/docs/00-plan-maestro.md`](godot/docs/00-plan-maestro.md).

## Requisitos

| | |
|---|---|
| Motor | **Godot 4.7** (estable, build estándar; el proyecto es GDScript puro, no hace falta la versión .NET) |
| Plataforma | **Windows** de escritorio |
| Renderizador | **Forward+** (el proyecto no soporta GL Compatibility ni Web) |
| Física | Jolt Physics a 100 Hz |
| Controles | Gamepad o radio RC; teclado y ratón solo para depurar |

## Cómo abrir el proyecto

El proyecto Godot **no está en la raíz del repositorio**, sino en `godot/`. Desde el
gestor de proyectos de Godot hay que importar `godot/project.godot`.

Desde la línea de comandos, con el binario de consola:

```
"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --path godot
```

Para importar los assets sin abrir la ventana del editor:

```
"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless --path godot --editor --quit
```

Ese comando debe terminar **sin ninguna línea** `ERROR:` ni `SCRIPT ERROR:`; es el
primer criterio de aceptación de cualquier paquete de trabajo.

## Cómo correr los checks

Cada feature entrega una escena `godot/tools/<feature>_check.tscn` que verifica su
contrato sin jugador humano, imprime `CHECK <nombre>: OK` o
`CHECK <nombre>: FAIL (n fallos)` y devuelve un código de salida distinto de cero
cuando falla. El catálogo completo está en
[`godot/docs/15-verificacion-y-ci.md`](godot/docs/15-verificacion-y-ci.md).

Todos de una vez (Windows):

```
powershell -File godot/tools/run_checks.ps1
```

Uno solo:

```
powershell -File godot/tools/run_checks.ps1 -Only project_check
```

> Si Windows responde «la ejecución de scripts está deshabilitada en este sistema»,
> la política de ejecución de PowerShell está en `Restricted` (el valor por defecto).
> Se resuelve por invocación con `powershell -ExecutionPolicy Bypass -File …`, o de
> una vez con `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

El equivalente para Linux y para el contenedor de CI es `godot/tools/run_checks.sh`.
Ambos dejan el detalle en `godot/tools/out/report.txt` (no versionado) y devuelven 0
solo si todo pasó.

En CI corren **solo los checks headless**: el contenedor no trae Vulkan y el proyecto
es Forward+, así que los que capturan imagen (`ui_smoke_test`, `boot_check`,
`menu_shots_check`, `render_check`) y los extendidos quedan como **locales**. El mismo
modo se reproduce a mano con `--headless-only` (bash) o `-HeadlessOnly` (PowerShell);
el resumen final lista los que quedaron sin correr.

Un check suelto, a mano:

```
"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless --path godot res://tools/project_check.tscn
```

## Cómo exportar la build de Windows

El preset `Windows Desktop` de `godot/export_presets.cfg` escribe en `builds/windows/`
(no versionado). Hacen falta las plantillas de export 4.7 instaladas en
`%APPDATA%\Godot\export_templates\4.7.stable\`:

```
"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless --path godot --export-release "Windows Desktop"
```

Salen `drone-survivor.exe` y `drone-survivor.pck` uno al lado del otro
(`binary_format/embed_pck=false`). El `.pck` no lleva `tools/`, `docs/` ni
`assets/_raw/`, y los scripts viajan como tokens binarios (`script_export_mode=2`).
El wrapper de consola solo se genera en export de **depuración**
(`debug/export_console_wrapper=1`), así que la build de release no trae
`drone-survivor.console.exe`.

## Integración continua

`.github/workflows/deploy-to-itch.yml` encadena cuatro jobs: `import` → `checks`
(solo los headless) → `export` (preset **Windows Desktop**, publicado como artefacto
`windows-desktop`) → `deploy-itch`, este último desactivado con `if: false` hasta que
el juego se publique. Los cuatro usan **Godot 4.7 stable**.

## Estructura del repositorio

```
godot/            proyecto Godot
  autoloads/      los 11 singletons (Global, Audio, Controls, …, Events)
  drone/          núcleo de vuelo, armas, energía, cámara FPV
  enemies/        framework de enemigos y colosos
  city/           ciudad destructible
  rounds/         rondas, objetivos y resultados
  gui/ hud/       menús, tema e interfaz de vuelo y de combate
  vfx/ world/ audio/ localization/
  assets/         assets importables; assets/_raw/ son los packs crudos (no se versionan)
  asset_import/   scripts de importación
  tools/          checks headless, runners y utilidades de build
  docs/           la documentación de diseño que gobierna cada paquete de trabajo
builds/           salida de las exportaciones (no se versiona)
```

## Documentación

Los documentos de `godot/docs/` son la especificación del juego: cada paquete de
trabajo está gobernado por uno de ellos y no se escribe código sin leerlo.

| Documento | Contenido |
|---|---|
| [`00-plan-maestro.md`](godot/docs/00-plan-maestro.md) | Visión, hoja de ruta, convenciones y orquestación |
| [`01-sala-limpia-y-reutilizacion.md`](godot/docs/01-sala-limpia-y-reutilizacion.md) | Qué se reutiliza, qué se reimplementa, protocolo legal |
| [`02-configuracion-del-proyecto.md`](godot/docs/02-configuracion-del-proyecto.md) | `project.godot`, capas, input, autoloads, import, export y CI |
| [`03-especificacion-nucleo-de-vuelo.md`](godot/docs/03-especificacion-nucleo-de-vuelo.md) | Física del dron, control, radio, cámara y audio |
| [`04-especificacion-configuracion-y-menus.md`](godot/docs/04-especificacion-configuracion-y-menus.md) | Autoloads de configuración y todos los menús |
| [`05-pipeline-voxel.md`](godot/docs/05-pipeline-voxel.md) | `.vox` → partes → GLB → import |
| [`06-framework-de-enemigos.md`](godot/docs/06-framework-de-enemigos.md) | Contrato de enemigo: partes, puntos débiles, rig, IA |
| [`07-arachnodroid.md`](godot/docs/07-arachnodroid.md) | Ficha del primer jefe |
| [`08-combate-y-armas.md`](godot/docs/08-combate-y-armas.md) | Arma, proyectiles, asistencia y calor |
| [`09-energia-y-danio.md`](godot/docs/09-energia-y-danio.md) | Energía, pilas, casco y respawn |
| [`10-ciudad-destructible.md`](godot/docs/10-ciudad-destructible.md) | Import de la ciudad, edificios e integridad |
| [`11-rondas-y-objetivos.md`](godot/docs/11-rondas-y-objetivos.md) | Catálogo de rondas, manager, objetivos y resultados |
| [`12-interfaz-y-hud.md`](godot/docs/12-interfaz-y-hud.md) | FlightHUD, CombatHUD y menús |
| [`13-identidad-visual-y-audio.md`](godot/docs/13-identidad-visual-y-audio.md) | Paleta, Environment, VFX, audio y sacudida de cámara |
| [`14-catalogo-de-enemigos.md`](godot/docs/14-catalogo-de-enemigos.md) | Los nueve enemigos y su orden |
| [`15-verificacion-y-ci.md`](godot/docs/15-verificacion-y-ci.md) | Checks, smoke test, rendimiento y CI |
| [`16-licencias-y-atribucion.md`](godot/docs/16-licencias-y-atribucion.md) | Licencia del juego y atribuciones |

## Sala limpia

Este proyecto se desarrolla en **sala limpia**. No se copia, lee ni consulta código
de terceros con licencia copyleft. En particular, el repositorio `drone-simulator`
queda fuera de límites para cualquier persona o agente que trabaje en este código; la
configuración de `.claude/settings.json` lo bloquea técnicamente.

## Licencia

Proyecto **propietario**. Los archivos `LICENSE`, `NOTICE` y `CREDITS.md` están
diferidos por decisión del usuario hasta el final del proyecto, cuando se confirme el
nombre legal del titular y las licencias de los packs de assets de terceros
(ver `godot/docs/00-plan-maestro.md` §8 y `godot/docs/16-licencias-y-atribucion.md`).
Hasta entonces, cada archivo de código lleva su cabecera de copyright y no se concede
permiso de uso, copia, modificación ni distribución.
