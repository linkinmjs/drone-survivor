Fixes:

- Veo algunos árboles dentro de otras estructuras u otras estructuras una encima de otra.
  → WP-L: resuelto en su mayor parte y medido. **Árboles dentro de estructuras**: (a) 8 instancias de
    arboleda estaban dentro de `rock_e` y `rock_a` (hasta 6,70 m adentro) y 52 dentro del cauce del
    arroyo — el resolvedor no consultaba ni las rocas ni el agua ni los alambrados; ahora sí, y la
    holgura se mide desde la copa y no desde el tronco. (b) El árbol de patio de `Building_House_01_03`
    tenía el tronco 0,65 m dentro de la pared de `Building_Mid_3`: la profundidad del árbol de patio
    dejó de ser la constante de 10 m y ahora es lo que quepa entre la casa y lo que haya detrás; tres
    casas de las veinte se quedan sin árbol porque el mediano les ocupa el corazón de manzana.
    (c) Los seis árboles de quinta se metían 0,34–0,57 m en su propia casa y rozaban el alambre:
    pasan a `tree_medium` a 4,40 m, con 0,94 m de la casa y 0,85 del alambre. (d) Dos árboles de patio
    vecinos se cruzaban 0,70 m: ahora ninguna copa se cruza con otra.
    **Estructuras una encima de otra**: ningún par de parcelas se solapaba, pero sí el resto: el toldo,
    los dos autos y el puesto de pila de la estación de servicio estaban dentro de su caja maciza
    (la estación pasó a colisión compuesta y el dron vuela bajo la marquesina), `pickup`, `truck` y
    `crate` estaban dentro del galpón de campo por una huella declarada más chica que la pieza, dos
    farolas se metían 0,10 m en un mediano y una tercera 0,57 m en el asfalto de una transversal.
    Todo eso lo miden desde ahora cinco filas nuevas de check (A–E) con sus negativas, así que no
    puede volver sin que la suite se ponga en rojo.
  → WP-L (2026-09-24), cerrado lo que quedaba abierto: 45 tramos de cerco de frente tocaban la fachada de
    su propia casa y 16 le atravesaban la pared por ~10 cm (el lote tenía 5,4 m de fondo y la casa 5,0–5,1,
    así que la fachada quedaba a 15–20 cm de la línea municipal y el cerco a 30). Las casas se corrieron
    hacia adentro del lote: el fondo de lote pasó de 5,4 a 6,16 m, que es el mínimo que deja el tramo de
    cerco más justo a 0,103 m de su fachada (mínimo pedido 0,10). Se movieron las 41 casas del pueblo
    0,38 m hacia adentro; cuatro lotes de esquina se angostaron para no pisar la espalda del vecino y una
    casa del borde se corrió 0,375 m para no salirse del círculo de 140 m. Relieve y pueblo rehorneados.
    De paso, el puesto de pila de la estación de servicio no repartía pilas (su hueco de 2,5 m tocaba la
    marquesina): el toldo y el puesto pasaron al costado de la tienda, donde no hay marquesina encima.
- Los assets no están escalados correctamente. Por ejemplo: slot_tower_b pareciera ser la parte de un edificio o bien un pequeño covertizo, sin embargo es mucho más grande que slot_house_d.