# Guia de algebra vectorial y colisiones en PostgreSQL

Este documento explica la matematica detras de `scripts/14_spatial_collisions.sql` y
`scripts/procedures/sp_vector_math.sql`: como se representa la posicion de un mueble, como se decide que dos
muebles chocan y como se calcula el centro de masa de una habitacion. Complementa a `fn_distancia_euclidiana`
de `scripts/06_advanced_queries.sql` y a la validacion de limites de `scripts/07_spatial_constraints.sql`.

## Piezas

| Pieza | Script | Que hace |
|---|---|---|
| `fn_distancia_euclidiana(x1, y1, z1, x2, y2, z2)` | `06_advanced_queries.sql` | Distancia en metros entre dos puntos |
| `fn_verificar_colision_mueble(hab, x, y, z, radio DEFAULT 0.10, excluir_id DEFAULT NULL)` | `14_spatial_collisions.sql` | Id del mueble mas cercano a menos de `radio` del punto, o `NULL` si esta libre |
| `trg_impedir_superposicion` | `14_spatial_collisions.sql` | `BEFORE INSERT` sobre `muebles_sugeridos`: rechaza el mueble nuevo con `exclusion_violation` (23P01) si choca |
| `fn_calcular_centro_masa_habitacion(hab)` | `procedures/sp_vector_math.sql` | Promedio de las posiciones de los muebles y cuantos son |
| `15_stress_seeds.sql` | `15_stress_seeds.sql` | Hotel de 20 habitaciones y 50 muebles para pruebas de carga |

## Convencion de ejes

Es la misma de Three.js en el frontend y de `07_spatial_constraints.sql`:

- **X** es el ancho, **Y** el alto medido desde el piso y **Z** la profundidad, todo en metros.
- El origen `(0, 0, 0)` es la esquina de la habitacion en el piso, junto a la pared del fondo.
- La posicion de un mueble es el **centro de su base**: centrado en X y Z, apoyado sobre Y.

## Vector posicion

Cada mueble se trata como un vector `p = (x, y, z)` que va del origen de su habitacion al centro de su base.
Las operaciones se hacen componente a componente:

| Operacion | Formula | En SQL |
|---|---|---|
| Diferencia | `p2 - p1 = (x2 - x1, y2 - y1, z2 - z1)` | Resta columna a columna |
| Norma (distancia) | `d = sqrt((x2 - x1)^2 + (y2 - y1)^2 + (z2 - z1)^2)` | `fn_distancia_euclidiana` |
| Promedio (centroide) | `c = (p1 + p2 + ... + pn) / n` | `avg(posicion_x)`, `avg(posicion_y)`, `avg(posicion_z)` |

## Colision por radio de proximidad

Dos muebles de la misma habitacion **chocan** cuando sus posiciones estan a menos de un radio de tolerancia `r`:

```
d(p_nuevo, p_existente) < r          r = 0.10 m por defecto
```

Dos muebles con exactamente las mismas coordenadas estan a `d = 0` y siempre chocan. El radio absorbe el
error de redondeo de `FLOAT` y los duplicados casi exactos, por ejemplo la misma peticion enviada dos veces con
una coordenada recalculada.

Calcular `d` contra todos los muebles de la habitacion seria costoso en una habitacion grande. Por eso
`fn_verificar_colision_mueble` filtra primero con un cuadrado de lado `2r` en el plano X-Z:

```sql
AND m.posicion_x BETWEEN p_x - p_radio AND p_x + p_radio
AND m.posicion_z BETWEEN p_z - p_radio AND p_z + p_radio
```

Ese filtro lo resuelve el indice `idx_muebles_habitacion_xz (habitacion_id, posicion_x, posicion_z)` de
`09_performance_indexes.sql`, y la raiz cuadrada solo se calcula para los pocos muebles que quedan dentro. Todo
punto dentro de la esfera de radio `r` esta tambien dentro del cuadrado, asi que el filtro no descarta ningun
choque real.

## Centro de masa

`fn_calcular_centro_masa_habitacion` promedia las posiciones de los `n` muebles de la habitacion:

```
c = ( avg(x), avg(y), avg(z) )
```

Supone que todos los muebles pesan lo mismo: es el centroide de los puntos, no el centro de masa fisico. Como
la posicion es el centro de la base, `centro_y` es la altura media de las bases (0 si todo esta en el piso). Si
la habitacion no tiene muebles devuelve coordenadas `NULL` y `total_muebles = 0`.

Comparado con el centro de la planta, `(ancho / 2, profundidad / 2)`, indica si el layout esta equilibrado:

```sql
SELECT h.nombre, c.*,
       fn_distancia_euclidiana(c.centro_x, 0, c.centro_z,
                               h.ancho / 2, 0, h.profundidad / 2) AS desvio_m
FROM habitaciones h
CROSS JOIN LATERAL fn_calcular_centro_masa_habitacion(h.id) c;
```
