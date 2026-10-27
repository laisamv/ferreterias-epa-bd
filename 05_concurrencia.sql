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

BEGIN
   pkg_contexto.g_tipo        := 'AJUSTE';
   pkg_contexto.g_observacion := 'Preparación prueba de concurrencia';
   UPDATE inventario
      SET stock = 1
    WHERE id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Plaza Madero')
      AND id_producto = (SELECT id_producto FROM producto WHERE codigo = 'HMA-001');
   pkg_contexto.limpiar;
   COMMIT;
   DBMS_OUTPUT.PUT_LINE('Stock del martillo en Plaza Madero = 1');
END;
/

SELECT i.stock
  FROM inventario i
 WHERE i.id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Plaza Madero')
   AND i.id_producto = (SELECT id_producto FROM producto WHERE codigo = 'HMA-001')
   FOR UPDATE;

SELECT i.stock
  FROM inventario i
 WHERE i.id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Plaza Madero')
   AND i.id_producto = (SELECT id_producto FROM producto WHERE codigo = 'HMA-001')
   FOR UPDATE;

COLUMN event FORMAT A35
SELECT sid, serial#, blocking_session, event, seconds_in_wait
  FROM v$session
 WHERE username = 'EPA'
   AND blocking_session IS NOT NULL;

UPDATE inventario
   SET stock = stock - 1
 WHERE id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Plaza Madero')
   AND id_producto = (SELECT id_producto FROM producto WHERE codigo = 'HMA-001');

COMMIT;

ROLLBACK;

SELECT i.stock
  FROM inventario i
 WHERE i.id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Plaza Madero')
   AND i.id_producto = (SELECT id_producto FROM producto WHERE codigo = 'HMA-001')
   FOR UPDATE;

DECLARE
   v_suc   NUMBER;
   v_emp   NUMBER;
   v_cli   NUMBER;
   v_prod  NUMBER;
   v_id    NUMBER;
   v_total NUMBER;
BEGIN
   SELECT id_sucursal INTO v_suc  FROM sucursal WHERE nombre = 'Plaza Madero';
   SELECT id_producto INTO v_prod FROM producto WHERE codigo = 'HMA-001';
   SELECT id_cliente  INTO v_cli  FROM cliente  WHERE nit = 'CF';
   SELECT MAX(id_empleado) INTO v_emp
     FROM empleado WHERE id_sucursal = v_suc AND puesto = 'CAJERO';

   DBMS_OUTPUT.PUT_LINE('Cajero B (empleado ' || v_emp || ') intentando vender 1 martillo...');
   pkg_ventas.vender_producto(v_suc, v_cli, v_emp, v_prod, 1, v_id, v_total);
   DBMS_OUTPUT.PUT_LINE('VENTA EXITOSA: factura ' || v_id || ' total Q' || v_total);
EXCEPTION
   WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('VENTA RECHAZADA: ' || SQLERRM);
END;
/

UPDATE inventario
   SET stock = stock - 1
 WHERE id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Plaza Madero')
   AND id_producto = (SELECT id_producto FROM producto WHERE codigo = 'HMA-001');

COMMIT;

SELECT stock
  FROM v_inventario_sucursal
 WHERE sucursal = 'Plaza Madero' AND codigo = 'HMA-001';

SELECT id_log, fecha, codigo_error, SUBSTR(mensaje, 1, 90) AS mensaje
  FROM log_venta_fallida
 ORDER BY id_log DESC
 FETCH FIRST 3 ROWS ONLY;

SELECT i.stock
  FROM inventario i
 WHERE i.id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Plaza Madero')
   AND i.id_producto = (SELECT id_producto FROM producto WHERE codigo = 'HMA-001');

SELECT i.stock
  FROM inventario i
 WHERE i.id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Plaza Madero')
   AND i.id_producto = (SELECT id_producto FROM producto WHERE codigo = 'HMA-001');

UPDATE inventario
   SET stock = stock - 1
 WHERE id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Plaza Madero')
   AND id_producto = (SELECT id_producto FROM producto WHERE codigo = 'HMA-001');

COMMIT;

UPDATE inventario
   SET stock = stock - 1
 WHERE id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Plaza Madero')
   AND id_producto = (SELECT id_producto FROM producto WHERE codigo = 'HMA-001');

ROLLBACK;

SELECT stock FROM inventario
 WHERE id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Plaza Madero')
   AND id_producto = (SELECT id_producto FROM producto WHERE codigo = 'HMA-001')
   FOR UPDATE;

SELECT stock FROM inventario
 WHERE id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Plaza Madero')
   AND id_producto = (SELECT id_producto FROM producto WHERE codigo = 'HMA-001')
   FOR UPDATE NOWAIT;

SELECT stock FROM inventario
 WHERE id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Plaza Madero')
   AND id_producto = (SELECT id_producto FROM producto WHERE codigo = 'HMA-001')
   FOR UPDATE WAIT 5;

ROLLBACK;

COLUMN tipo        FORMAT A10
COLUMN observacion FORMAT A40
SELECT m.id_movimiento, TO_CHAR(m.fecha, 'DD/MM HH24:MI:SS') AS fecha,
       m.tipo, m.cantidad, m.stock_anterior, m.stock_nuevo, m.id_venta, m.observacion
  FROM movimiento_inventario m
 WHERE m.id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Plaza Madero')
   AND m.id_producto = (SELECT id_producto FROM producto WHERE codigo = 'HMA-001')
   AND m.fecha >= SYSDATE - 1
 ORDER BY m.id_movimiento;

SELECT COUNT(*) AS filas_con_stock_negativo FROM inventario WHERE stock < 0;

ROLLBACK;
DECLARE
   v_suc  NUMBER;
   v_prod NUMBER;
BEGIN
   SELECT id_sucursal INTO v_suc  FROM sucursal WHERE nombre = 'Plaza Madero';
   SELECT id_producto INTO v_prod FROM producto WHERE codigo = 'HMA-001';
   pkg_ventas.registrar_entrada(v_suc, v_prod, 50, 'Reabastecimiento después de la prueba');
   DBMS_OUTPUT.PUT_LINE('Stock repuesto: ' || pkg_ventas.stock_disponible(v_suc, v_prod));
END;
/
