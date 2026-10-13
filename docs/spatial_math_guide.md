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

## Integracion con el Octree del backend

El backend y la base de datos validan cosas distintas, en momentos distintos. Ninguna de las dos capas
reemplaza a la otra.

| | Octree del backend | `trg_impedir_superposicion` en la base |
|---|---|---|
| Que compara | Las cajas completas de los muebles (interseccion de volumenes) | Solo los puntos de posicion (distancia menor que `r`) |
| Cuando corre | Al proponer o mover un mueble, antes de llamar a la base | En cada `INSERT` sobre `muebles_sugeridos`, venga de donde venga |
| Que protege | Que el layout sea fisicamente posible | Que no se guarden dos muebles en el mismo punto aunque el backend falle |
| Costo | En memoria, `O(log n)` por consulta al arbol | Un rango sobre `idx_muebles_habitacion_xz` mas `n_cercanos` distancias |

El flujo de una insercion es:

1. El Octree del backend comprueba que la caja del mueble no se cruce con las de los demas.
2. El backend hace el `INSERT` con las coordenadas aprobadas.
3. `trg_impedir_superposicion` toma el bloqueo consultivo de la habitacion y llama a
   `fn_verificar_colision_mueble`. Si hay un mueble a menos de `r` aborta con `exclusion_violation` (23P01).
4. `trg_muebles_limites_check` (orden alfabetico, corre despues) comprueba que la caja quepa en la habitacion;
   si no, aborta con `check_violation` (23514).

Si el Octree funciona bien, el paso 3 casi nunca falla: dos cajas que no se cruzan tienen sus centros separados
al menos por la suma de sus medias medidas en algun eje, que para muebles reales supera con creces 10 cm (la
excepcion son objetos de pocos centimetros o sin medidas). El trigger existe para los casos que el Octree no ve:

- **Peticiones repetidas.** Un doble clic o un reintento de red envia el mismo mueble dos veces. El Octree de
  cada peticion se construyo antes de que la otra se guardara y las dos lo aprueban.
- **Escrituras concurrentes.** Dos pestanas del mismo usuario colocan un mueble en el mismo sitio a la vez. El
  bloqueo `pg_advisory_xact_lock(14, habitacion_id)` hace que la segunda insercion espere a que la primera
  confirme y entonces la vea.
- **Inserciones que no pasan por el backend**, como un `INSERT` manual en el SQL Editor de Supabase o un script
  de carga.

### Que debe hacer el backend con los errores

| SQLSTATE | Origen | Respuesta HTTP sugerida |
|---|---|---|
| `23P01` `exclusion_violation` | `trg_impedir_superposicion` | `409 Conflict`: el sitio ya esta ocupado; volver a consultar el Octree con los datos actuales |
| `23514` `check_violation` | `trg_muebles_limites_check` | `422 Unprocessable Entity`: el mueble no cabe en la habitacion |

El mensaje del error nombra el mueble con el que choca y su id, y el `DETAIL` trae las dos posiciones y la
distancia, por si el backend quiere mostrarlos.

### Ajustar el radio

El radio vive en la definicion del trigger, como argumento de `fn_impedir_superposicion`. Para cambiarlo a 5 cm:

```sql
DROP TRIGGER trg_impedir_superposicion ON muebles_sugeridos;
CREATE TRIGGER trg_impedir_superposicion
  BEFORE INSERT ON muebles_sugeridos
  FOR EACH ROW EXECUTE FUNCTION fn_impedir_superposicion('0.05');
```

Debe ser menor que la menor separacion legitima entre dos posiciones que acepte el Octree.

### Limites conocidos

- **Muebles apilados en el mismo punto.** `08_extended_seeds.sql` coloca la "Mesa de centro" y la "Alfombra" en
  exactamente la misma posicion: una alfombra bajo una mesa es un layout valido, pero el trigger lo rechazaria.
  Ese script corre antes de `14_spatial_collisions.sql`, asi que no falla; volver a ejecutarlo despues si
  fallaria. Para soportar objetos apilados habria que excluir del chequeo los muebles muy bajos (por ejemplo
  `alto < 0.05`).
- **Solo `INSERT`.** Mover un mueble con `UPDATE` no pasa por el trigger. Si hace falta, se puede agregar
  `OR UPDATE OF habitacion_id, posicion_x, posicion_y, posicion_z` y pasar `NEW.id` como `p_excluir_id`.
- **Muebles anteriores al script.** Las filas que ya existian cuando se aplico el trigger no se revisan.
