SET SERVEROUTPUT ON
SET LINESIZE 200
SET TIME ON
SET TIMING ON
SET SQLPROMPT "SESION_A> "

SET SERVEROUTPUT ON
SET LINESIZE 200
SET TIME ON
SET TIMING ON
SET SQLPROMPT "SESION_B> "

SELECT (SELECT COUNT(*) FROM encabezado_venta)                          AS facturas,
       (SELECT COUNT(*) FROM encabezado_venta WHERE estado = 'PENDIENTE') AS pendientes,
       (SELECT COUNT(*) FROM detalle_venta)                             AS detalles,
       (SELECT SUM(stock) FROM inventario
         WHERE id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Roosevelt'))
                                                                        AS stock_roosevelt,
       (SELECT COUNT(*) FROM movimiento_inventario)                     AS kardex
  FROM dual;

ROLLBACK;

DECLARE
   v_suc NUMBER; v_emp NUMBER; v_cli NUMBER; v_id NUMBER; n NUMBER := 0;
BEGIN
   SELECT id_sucursal INTO v_suc FROM sucursal WHERE nombre = 'Roosevelt';
   SELECT MIN(id_empleado) INTO v_emp FROM empleado WHERE id_sucursal = v_suc AND puesto = 'CAJERO';
   SELECT id_cliente INTO v_cli FROM cliente WHERE nombre = 'Constructora Los Altos, S.A.';

   INSERT INTO encabezado_venta (id_sucursal, id_cliente, id_empleado)
   VALUES (v_suc, v_cli, v_emp)
   RETURNING id_venta INTO v_id;

   pkg_contexto.g_id_venta := v_id;
   pkg_contexto.g_tipo := 'SALIDA';
   pkg_contexto.g_observacion := 'Crash test manual';

   FOR r IN (SELECT i.id_producto, p.precio_sugerido
               FROM inventario i
               JOIN producto  p ON p.id_producto  = i.id_producto
               JOIN categoria c ON c.id_categoria = p.id_categoria
              WHERE i.id_sucursal = v_suc AND i.stock >= 2
              ORDER BY CASE WHEN c.nombre = 'Construcción' THEN 0 ELSE 1 END, p.id_producto
              FETCH FIRST 50 ROWS ONLY) LOOP
      n := n + 1;
      IF n = 25 THEN
         DBMS_OUTPUT.PUT_LINE('*** ARTÍCULO 25: SE PERDIÓ LA CONEXIÓN ***');
         EXIT;
      END IF;
      UPDATE inventario SET stock = stock - 2
       WHERE id_sucursal = v_suc AND id_producto = r.id_producto;
      INSERT INTO detalle_venta (id_venta, id_producto, cantidad, precio_unitario)
      VALUES (v_id, r.id_producto, 2, r.precio_sugerido);
   END LOOP;

   pkg_contexto.limpiar;
   DBMS_OUTPUT.PUT_LINE('Factura ' || v_id || ': ' || (n - 1) ||
                        ' de 50 artículos registrados. SIN COMMIT.');
END;
/

SELECT e.id_venta, e.estado, e.total,
       (SELECT COUNT(*) FROM detalle_venta d WHERE d.id_venta = e.id_venta) AS lineas
  FROM encabezado_venta e
 WHERE e.id_venta = (SELECT MAX(id_venta) FROM encabezado_venta);

SELECT (SELECT COUNT(*) FROM encabezado_venta)                          AS facturas,
       (SELECT COUNT(*) FROM encabezado_venta WHERE estado = 'PENDIENTE') AS pendientes,
       (SELECT COUNT(*) FROM detalle_venta)                             AS detalles,
       (SELECT SUM(stock) FROM inventario
         WHERE id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Roosevelt'))
                                                                        AS stock_roosevelt,
       (SELECT COUNT(*) FROM movimiento_inventario)                     AS kardex
  FROM dual;

SELECT (SELECT COUNT(*) FROM encabezado_venta)                          AS facturas,
       (SELECT COUNT(*) FROM encabezado_venta WHERE estado = 'PENDIENTE') AS pendientes,
       (SELECT COUNT(*) FROM detalle_venta)                             AS detalles,
       (SELECT SUM(stock) FROM inventario
         WHERE id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Roosevelt'))
                                                                        AS stock_roosevelt,
       (SELECT COUNT(*) FROM movimiento_inventario)                     AS kardex
  FROM dual;

ROLLBACK;

SELECT (SELECT COUNT(*) FROM encabezado_venta)                          AS facturas,
       (SELECT COUNT(*) FROM encabezado_venta WHERE estado = 'PENDIENTE') AS pendientes,
       (SELECT COUNT(*) FROM detalle_venta)                             AS detalles,
       (SELECT SUM(stock) FROM inventario
         WHERE id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Roosevelt'))
                                                                        AS stock_roosevelt,
       (SELECT COUNT(*) FROM movimiento_inventario)                     AS kardex
  FROM dual;
