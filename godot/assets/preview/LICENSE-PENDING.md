# `assets/preview/` — licencias **pendientes**

> Gobierna: `docs/16-licencias-y-atribucion.md` (riesgo D-6 de `docs/05`) · Escrito en WP-G2 (2026-09-24)

Este archivo **registra**, no resuelve. `assets/preview/` guarda **vistas previas** de todo
lo que hay en `assets/_raw/` y el juego todavía no usa: GLB estáticos para mirarlos en la
galería de assets (`tools/asset_gallery.tscn`, filas `Packs/*` y `Enemigos`)
y decidir si entran. **No son arte del juego**: se importan sin `import_script`, ninguna
escena del juego los nombra y la carpeta entera está fuera de los dos presets de
`export_presets.cfg` (`assets/preview/*`). Aun así son **derivados** de packs sin licencia
conocida y quedan anotados acá, igual que `assets/town/LICENSE-PENDING.md` anota los del
pueblo.

## 1. Una fila por pack

| Carpeta | Archivo en `assets/_raw/` | Autor que figura | Qué se derivó | Licencia |
|---|---|---|---|---|
| `cars/` | `cars.zip` | ninguno (los OBJ llevan `# MagicaVoxel @ Ephtracy`, que identifica al **exportador**; prefijo `Free Sample-<n>`) | las 15 piezas: el taxi ensamblado de 6 OBJ (carrocería, 4 ruedas, placa), 2 baldosas de cruce, 4 de calle y 3 señales → `cars_taxi`, `cars_crossing_a/b`, `cars_street_6_a/b`, `cars_street_8_a/b`, `cars_sign_60/64/66` | **DESCONOCIDA** |
| `vcity_extra/` | `city-Free Sample.zip` | ninguno (prefijo `Voxel City-<n>-<Pieza>`) | las 9 piezas que el pueblo no usa: 4 esquinas de vereda, los 4 pisos del edificio amarillo (sueltos y ensamblados) y el toldo grande → `vcity_curb_corner_a…d`, `vcity_floor_angle/b1/b2/b4`, `vcity_building_yellow`, `vcity_market_roof` | **DESCONOCIDA** |
| `village_objects/` | `VoxelVillagePack.zip` (paleta de `objects/`) | ninguno (el ZIP trae `__MACOSX/` y `.DS_Store`) | 4 cajones de color, el puente y la roca grande → `village_crate_blue/green/orange/red`, `village_bridge`, `village_rock_big` | **DESCONOCIDA** |
| `village_buildings/` | `VoxelVillagePack.zip` (paleta de `buildings/`) | ninguno | 5 edificios, 3 puestos de mercado, 5 árboles y la roca chica → `village_building_1…5`, `village_market_stall_1…3`, `village_tree_1…5`, `village_rock_small`. **Las 12 personas no** | **DESCONOCIDA** |
| `foliage_extra/` | `Foliage.rar` | ninguno | los 21 OBJ de `obj/` que el pueblo no usa (2 arbustos, maíz chico y brote, 3 flores, 4 pastos, 6 plantas, 4 rocas) → `foliage_*`. Los `.ply` de `mc/` y los PNG de `slice/`, `2d/` e `iso/` **no** | **DESCONOCIDA** |
| `nuke_extra/` | `nuke Free Sample.zip` | ninguno (prefijo `VoxelNuke-<n>`) | las 11 piezas que el pueblo no usa: 2 baldosas de calle, la de hormigón, el sexto montón de basura y 7 matas de maleza → `nuke_road_tile_0/1`, `nuke_concrete_tile`, `nuke_trash_5`, `nuke_weeds_1/2/3/5/6/7/8` | **DESCONOCIDA** |
| `cliffs/` | `Package.zip` | ninguno | las 10 `MountainRocks`, diezmadas → `cliff_rock_00…09` | **DESCONOCIDA** |
| `enemies/` | `QuadrupedTank.zip`, `MechGolem.zip`, `MechaTrooper.zip`, `FieldFighter.zip`, `MobileStorageBot.zip`, `Mecha01.rar`, `ReconBot.zip`, `Companion-bot.zip` | ninguno | el `.vox` de cada mecha entero, en una sola parte y con sus emisivos → `mech_quadruped_tank`, `mech_golem`, `mech_trooper`, `mech_field_fighter`, `mech_mobile_storage_bot`, `mech_mecha01`, `mech_recon_bot`, `mech_companion_bot` | **DESCONOCIDA** (la misma situación que el Arachnodroid, `docs/05` §15 D-6) |

## 2. Duplicado

**`citry.zip` es un duplicado byte a byte de `city-Free Sample.zip`** (mismo md5, mismos
235 625 bytes). No se usa en ninguna receta: `vcity_extra` lee `city-Free Sample.zip`.
Borrarlo o no es decisión de quien administre `assets/_raw/`; acá sólo se anota.

## 3. Qué se redistribuye

| | En el repositorio | En el export |
|---|---|---|
| Los archivos originales | Sí, en `assets/_raw/` (con `.gdignore`) | No |
| Los OBJ y `.vox` de los packs | **No.** Nunca se extraen: `objvox` y `voxreader` los leen con `archivo.zip!miembro` y `archivo.rar!miembro` (por tubería de UnRAR) | No |
| Los `*_palette.png` | **Regenerados** con `glbwriter.write_palette_png()` a partir de los colores leídos (el de `foliage_extra` con el repintado de `foliage.json`) | No |
| Los GLB de `assets/preview/` | Sí: **derivados** (re-voxelizados, vueltos a mallar con el mesher greedy propio, recentrados, ensamblados y, algunos, diezmados según `tools/voxsplit/models/*.json`) | **No** (`assets/preview/*` excluido) |

## 4. Lo que falta

Lo mismo que en `assets/town/LICENSE-PENDING.md` §5: localizar el origen y la licencia real
de cada pack, anotarlo en `docs/16` y en `CREDITS.md` si hace falta, y **antes** de que
cualquiera de estas piezas pase de `assets/preview/` al juego.
