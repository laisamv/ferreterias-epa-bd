SET SERVEROUTPUT ON
SET LINESIZE 220
SET PAGESIZE 100

CREATE OR REPLACE VIEW v_rep_ventas_mensuales AS
WITH v AS (
   SELECT TRUNC(fecha_venta, 'MM') AS mes,
          COUNT(*)                 AS facturas,
          SUM(total)               AS total_ventas
     FROM encabezado_venta
    WHERE estado = 'COMPLETADA'
    GROUP BY TRUNC(fecha_venta, 'MM')
)
SELECT TO_CHAR(mes, 'YYYY-MM')                          AS mes,
       facturas,
       total_ventas,
       ROUND(total_ventas / facturas, 2)                AS ticket_promedio,
       ROUND( (total_ventas - LAG(total_ventas) OVER (ORDER BY mes))
              / NULLIF(LAG(total_ventas) OVER (ORDER BY mes), 0) * 100, 1)
                                                        AS variacion_pct
  FROM v;

COMMENT ON TABLE v_rep_ventas_mensuales IS 'Reporte 1: ventas por mes con variación porcentual';

CREATE OR REPLACE VIEW v_rep_top_productos AS
SELECT RANK() OVER (ORDER BY SUM(d.cantidad) DESC)  AS ranking,
       p.codigo,
       p.nombre                                     AS producto,
       c.nombre                                     AS categoria,
       SUM(d.cantidad)                              AS unidades_vendidas,
       SUM(d.subtotal)                              AS ingresos,
       COUNT(DISTINCT d.id_venta)                   AS facturas
  FROM detalle_venta d
  JOIN encabezado_venta e ON e.id_venta    = d.id_venta
  JOIN producto        p ON p.id_producto  = d.id_producto
  JOIN categoria       c ON c.id_categoria = p.id_categoria
 WHERE e.estado = 'COMPLETADA'
 GROUP BY p.id_producto, p.codigo, p.nombre, c.nombre;

COMMENT ON TABLE v_rep_top_productos IS 'Reporte 2: ranking de productos por unidades vendidas';

CREATE OR REPLACE VIEW v_rep_ranking_sucursales AS
SELECT RANK() OVER (ORDER BY NVL(SUM(e.total), 0) DESC)              AS ranking,
       s.nombre                                                      AS sucursal,
       s.municipio,
       COUNT(e.id_venta)                                             AS facturas,
       NVL(SUM(e.total), 0)                                          AS total_ventas,
       ROUND(NVL(SUM(e.total), 0) / NULLIF(COUNT(e.id_venta), 0), 2) AS ticket_promedio,
       ROUND(RATIO_TO_REPORT(NVL(SUM(e.total), 0)) OVER () * 100, 2) AS participacion_pct
  FROM sucursal s
  LEFT JOIN encabezado_venta e
         ON e.id_sucursal = s.id_sucursal
        AND e.estado      = 'COMPLETADA'
 GROUP BY s.id_sucursal, s.nombre, s.municipio;

COMMENT ON TABLE v_rep_ranking_sucursales IS 'Reporte 3: sucursales ordenadas por monto vendido';

CREATE OR REPLACE VIEW v_rep_baja_rotacion AS
WITH vendidos AS (
   SELECT d.id_producto,
          SUM(CASE WHEN e.fecha_venta >= SYSDATE - 90 THEN d.cantidad ELSE 0 END) AS unidades_90d,
          MAX(e.fecha_venta)                                                      AS ultima_venta
     FROM detalle_venta d
     JOIN encabezado_venta e ON e.id_venta = d.id_venta
    WHERE e.estado = 'COMPLETADA'
    GROUP BY d.id_producto
),
existencias AS (
   SELECT id_producto, SUM(stock) AS stock_total
     FROM inventario
    GROUP BY id_producto
)
SELECT p.codigo,
       p.nombre                                       AS producto,
       c.nombre                                       AS categoria,
       NVL(v.unidades_90d, 0)                         AS unidades_90d,
       TO_CHAR(v.ultima_venta, 'DD/MM/YYYY')          AS ultima_venta,
       TRUNC(SYSDATE - v.ultima_venta)                AS dias_sin_venta,
       NVL(x.stock_total, 0)                          AS stock_total,
       NVL(x.stock_total, 0) * p.precio_sugerido      AS valor_inmovilizado,
       CASE
          WHEN v.id_producto IS NULL        THEN 'SIN VENTAS'
          WHEN NVL(v.unidades_90d, 0) = 0   THEN 'SIN MOVIMIENTO 90 DÍAS'
          WHEN v.unidades_90d <= 5          THEN 'BAJA ROTACIÓN'
          ELSE 'NORMAL'
       END                                            AS clasificacion
  FROM producto p
  JOIN categoria   c ON c.id_categoria = p.id_categoria
  LEFT JOIN vendidos    v ON v.id_producto = p.id_producto
  LEFT JOIN existencias x ON x.id_producto = p.id_producto
 WHERE p.activo = 'S';

COMMENT ON TABLE v_rep_baja_rotacion IS 'Reporte 4: productos sin ventas o con poca rotación';

CREATE OR REPLACE VIEW v_rep_ventas_categoria AS
SELECT RANK() OVER (ORDER BY SUM(d.subtotal) DESC)              AS ranking,
       c.nombre                                                 AS categoria,
       COUNT(DISTINCT d.id_producto)                            AS productos_vendidos,
       SUM(d.cantidad)                                          AS unidades,
       SUM(d.subtotal)                                          AS ingresos,
       ROUND(RATIO_TO_REPORT(SUM(d.subtotal)) OVER () * 100, 2) AS participacion_pct
  FROM detalle_venta d
  JOIN encabezado_venta e ON e.id_venta    = d.id_venta
  JOIN producto        p ON p.id_producto  = d.id_producto
  JOIN categoria       c ON c.id_categoria = p.id_categoria
 WHERE e.estado = 'COMPLETADA'
 GROUP BY c.id_categoria, c.nombre;

COMMENT ON TABLE v_rep_ventas_categoria IS 'Reporte 5: ingresos y participación por categoría';

CREATE OR REPLACE VIEW v_rep_mejores_clientes AS
SELECT RANK() OVER (ORDER BY SUM(e.total) DESC)     AS ranking,
       cl.nit,
       cl.nombre                                    AS cliente,
       COUNT(e.id_venta)                            AS facturas,
       SUM(e.total)                                 AS total_comprado,
       ROUND(AVG(e.total), 2)                       AS compra_promedio,
       TO_CHAR(MAX(e.fecha_venta), 'DD/MM/YYYY')    AS ultima_compra
  FROM cliente cl
  JOIN encabezado_venta e ON e.id_cliente = cl.id_cliente
 WHERE e.estado = 'COMPLETADA'
   AND cl.nit  <> 'CF'
 GROUP BY cl.id_cliente, cl.nit, cl.nombre;

COMMENT ON TABLE v_rep_mejores_clientes IS 'Reporte 6: clientes registrados con mayor monto de compra';

CREATE OR REPLACE VIEW v_rep_desempeno_cajeros AS
SELECT s.nombre                                                    AS sucursal,
       em.nombres || ' ' || em.apellidos                           AS cajero,
       COUNT(e.id_venta)                                           AS facturas,
       NVL(SUM(e.total), 0)                                        AS total_vendido,
       ROUND(NVL(SUM(e.total), 0) / NULLIF(COUNT(e.id_venta), 0), 2) AS ticket_promedio,
       RANK() OVER (PARTITION BY s.id_sucursal
                    ORDER BY NVL(SUM(e.total), 0) DESC)            AS ranking_en_sucursal
  FROM empleado em
  JOIN sucursal s ON s.id_sucursal = em.id_sucursal
  LEFT JOIN encabezado_venta e
         ON e.id_empleado = em.id_empleado
        AND e.estado      = 'COMPLETADA'
 WHERE em.puesto = 'CAJERO'
 GROUP BY s.id_sucursal, s.nombre, em.id_empleado, em.nombres, em.apellidos;

COMMENT ON TABLE v_rep_desempeno_cajeros IS 'Reporte 7: ventas por cajero y su posición dentro de la sucursal';

CREATE OR REPLACE VIEW v_rep_resumen AS
SELECT (SELECT COUNT(*)  FROM encabezado_venta WHERE estado = 'COMPLETADA')          AS facturas,
       (SELECT SUM(total) FROM encabezado_venta WHERE estado = 'COMPLETADA')         AS total_ventas,
       (SELECT ROUND(AVG(total), 2) FROM encabezado_venta WHERE estado = 'COMPLETADA') AS ticket_promedio,
       (SELECT COUNT(*)  FROM encabezado_venta WHERE estado = 'ANULADA')             AS facturas_anuladas,
       (SELECT COUNT(*)  FROM cliente)                                               AS clientes,
       (SELECT COUNT(*)  FROM producto WHERE activo = 'S')                           AS productos_activos,
       (SELECT COUNT(*)  FROM v_rep_baja_rotacion WHERE clasificacion = 'SIN VENTAS') AS productos_sin_ventas,
       (SELECT SUM(stock * p.precio_sugerido)
          FROM inventario i JOIN producto p ON p.id_producto = i.id_producto)        AS valor_inventario
  FROM dual;

COMMENT ON TABLE v_rep_resumen IS 'Indicadores generales del negocio';

COLUMN total_ventas     FORMAT 999,999,990.00
COLUMN ticket_promedio  FORMAT 999,990.00
COLUMN valor_inventario FORMAT 999,999,990.00
SELECT * FROM v_rep_resumen;

COLUMN mes           FORMAT A8
COLUMN variacion_pct FORMAT 9990.0
SELECT * FROM v_rep_ventas_mensuales ORDER BY mes;

COLUMN codigo    FORMAT A8
COLUMN producto  FORMAT A40
COLUMN categoria FORMAT A24
COLUMN ingresos  FORMAT 999,999,990.00
SELECT * FROM v_rep_top_productos
 ORDER BY ranking, ingresos DESC
 FETCH FIRST 10 ROWS ONLY;

COLUMN sucursal          FORMAT A25
COLUMN municipio         FORMAT A22
COLUMN participacion_pct FORMAT 990.00
SELECT * FROM v_rep_ranking_sucursales ORDER BY ranking;

COLUMN ultima_venta       FORMAT A12
COLUMN clasificacion      FORMAT A24
COLUMN valor_inmovilizado FORMAT 999,999,990.00
SELECT * FROM v_rep_baja_rotacion
 WHERE clasificacion <> 'NORMAL'
 ORDER BY CASE clasificacion WHEN 'SIN VENTAS' THEN 1
                             WHEN 'SIN MOVIMIENTO 90 DÍAS' THEN 2
                             ELSE 3 END,
          unidades_90d, valor_inmovilizado DESC
 FETCH FIRST 20 ROWS ONLY;

SELECT clasificacion, COUNT(*) AS productos, SUM(valor_inmovilizado) AS valor_inmovilizado
  FROM v_rep_baja_rotacion
 GROUP BY clasificacion
 ORDER BY productos DESC;

SELECT * FROM v_rep_ventas_categoria ORDER BY ranking;

COLUMN nit            FORMAT A12
COLUMN cliente        FORMAT A35
COLUMN total_comprado FORMAT 999,999,990.00
SELECT * FROM v_rep_mejores_clientes ORDER BY ranking FETCH FIRST 10 ROWS ONLY;

COLUMN cajero        FORMAT A30
COLUMN total_vendido FORMAT 999,999,990.00
SELECT * FROM v_rep_desempeno_cajeros ORDER BY sucursal, ranking_en_sucursal;

COLUMN object_name FORMAT A30
SELECT object_name, status
  FROM user_objects
 WHERE object_type = 'VIEW' AND object_name LIKE 'V_REP%'
 ORDER BY object_name;
