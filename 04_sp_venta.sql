SET SERVEROUTPUT ON

BEGIN
   EXECUTE IMMEDIATE 'DROP TABLE log_venta_fallida PURGE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

CREATE TABLE log_venta_fallida (
   id_log        NUMBER          GENERATED ALWAYS AS IDENTITY,
   fecha         DATE            DEFAULT SYSDATE NOT NULL,
   operacion     VARCHAR2(20)    NOT NULL,
   id_sucursal   NUMBER,
   id_empleado   NUMBER,
   codigo_error  NUMBER,
   mensaje       VARCHAR2(500),
   usuario_bd    VARCHAR2(30)    DEFAULT USER NOT NULL,
   CONSTRAINT pk_log_venta_fallida PRIMARY KEY (id_log)
);
COMMENT ON TABLE log_venta_fallida IS 'Intentos de venta/anulación que fallaron y se revirtieron con ROLLBACK';

CREATE OR REPLACE PACKAGE pkg_ventas AS
   TYPE t_numeros IS TABLE OF NUMBER INDEX BY PLS_INTEGER;

   PROCEDURE registrar_venta (
      p_id_sucursal       IN  NUMBER,
      p_id_cliente        IN  NUMBER,
      p_id_empleado       IN  NUMBER,
      p_productos         IN  t_numeros,
      p_cantidades        IN  t_numeros,
      p_id_venta          OUT NUMBER,
      p_total             OUT NUMBER,
      p_simular_falla_en  IN  NUMBER DEFAULT NULL
   );

   PROCEDURE vender_producto (
      p_id_sucursal  IN  NUMBER,
      p_id_cliente   IN  NUMBER,
      p_id_empleado  IN  NUMBER,
      p_id_producto  IN  NUMBER,
      p_cantidad     IN  NUMBER,
      p_id_venta     OUT NUMBER,
      p_total        OUT NUMBER
   );

   PROCEDURE anular_venta (
      p_id_venta  IN NUMBER,
      p_motivo    IN VARCHAR2
   );

   PROCEDURE registrar_entrada (
      p_id_sucursal  IN NUMBER,
      p_id_producto  IN NUMBER,
      p_cantidad     IN NUMBER,
      p_observacion  IN VARCHAR2 DEFAULT 'Ingreso de mercadería'
   );

   FUNCTION stock_disponible (
      p_id_sucursal  IN NUMBER,
      p_id_producto  IN NUMBER
   ) RETURN NUMBER;

END pkg_ventas;
/

CREATE OR REPLACE PACKAGE BODY pkg_ventas AS
   e_tx_activa EXCEPTION;
   PRAGMA EXCEPTION_INIT(e_tx_activa, -1453);

   PROCEDURE log_error (
      p_operacion VARCHAR2, p_suc NUMBER, p_emp NUMBER,
      p_codigo NUMBER, p_mensaje VARCHAR2
   ) IS
      PRAGMA AUTONOMOUS_TRANSACTION;
   BEGIN
      INSERT INTO log_venta_fallida (operacion, id_sucursal, id_empleado, codigo_error, mensaje)
      VALUES (p_operacion, p_suc, p_emp, p_codigo, SUBSTR(p_mensaje, 1, 500));
      COMMIT;
   END log_error;

   PROCEDURE registrar_venta (
      p_id_sucursal       IN  NUMBER,
      p_id_cliente        IN  NUMBER,
      p_id_empleado       IN  NUMBER,
      p_productos         IN  t_numeros,
      p_cantidades        IN  t_numeros,
      p_id_venta          OUT NUMBER,
      p_total             OUT NUMBER,
      p_simular_falla_en  IN  NUMBER DEFAULT NULL
   ) IS
      v_lineas   t_numeros;
      v_prod     NUMBER;
      v_stock    inventario.stock%TYPE;
      v_precio   producto.precio_sugerido%TYPE;
      v_n        PLS_INTEGER := 0;
      v_codigo   NUMBER;
      v_mensaje  VARCHAR2(500);
   BEGIN
      IF p_productos.COUNT = 0 OR p_productos.COUNT <> p_cantidades.COUNT THEN
         RAISE_APPLICATION_ERROR(-20020, 'La venta no tiene productos o las listas no coinciden.');
      END IF;

      FOR i IN p_productos.FIRST .. p_productos.LAST LOOP
         IF p_cantidades(i) IS NULL OR p_cantidades(i) <= 0 THEN
            RAISE_APPLICATION_ERROR(-20020,
               'Cantidad inválida para el producto ' || p_productos(i));
         END IF;
         IF v_lineas.EXISTS(p_productos(i)) THEN
            v_lineas(p_productos(i)) := v_lineas(p_productos(i)) + p_cantidades(i);
         ELSE
            v_lineas(p_productos(i)) := p_cantidades(i);
         END IF;
      END LOOP;

      BEGIN
         SET TRANSACTION NAME 'VENTA_EPA';
      EXCEPTION
         WHEN e_tx_activa THEN
            RAISE_APPLICATION_ERROR(-20023,
               'Hay cambios pendientes en esta sesión. Ejecute COMMIT o ROLLBACK antes de vender.');
      END;

      BEGIN
         INSERT INTO encabezado_venta (id_sucursal, id_cliente, id_empleado)
         VALUES (p_id_sucursal, p_id_cliente, p_id_empleado)
         RETURNING id_venta INTO p_id_venta;

         pkg_contexto.g_id_venta    := p_id_venta;
         pkg_contexto.g_tipo        := 'SALIDA';
         pkg_contexto.g_observacion := 'Venta';

         v_prod := v_lineas.FIRST;
         WHILE v_prod IS NOT NULL LOOP
            v_n := v_n + 1;

            IF p_simular_falla_en IS NOT NULL AND v_n = p_simular_falla_en THEN
               RAISE_APPLICATION_ERROR(-20099,
                  'FALLA SIMULADA: se perdió la conexión al procesar el artículo ' || v_n);
            END IF;

            BEGIN
               SELECT i.stock, p.precio_sugerido
                 INTO v_stock, v_precio
                 FROM inventario i
                 JOIN producto  p ON p.id_producto = i.id_producto
                WHERE i.id_sucursal = p_id_sucursal
                  AND i.id_producto = v_prod
                  FOR UPDATE OF i.stock;
            EXCEPTION
               WHEN NO_DATA_FOUND THEN
                  RAISE_APPLICATION_ERROR(-20021,
                     'El producto ' || v_prod || ' no existe en la sucursal ' || p_id_sucursal);
            END;

            IF v_stock < v_lineas(v_prod) THEN
               RAISE_APPLICATION_ERROR(-20001,
                  'Stock insuficiente del producto ' || v_prod ||
                  ': disponible ' || v_stock || ', solicitado ' || v_lineas(v_prod));
            END IF;

            UPDATE inventario
               SET stock = stock - v_lineas(v_prod)
             WHERE id_sucursal = p_id_sucursal
               AND id_producto = v_prod;

            INSERT INTO detalle_venta (id_venta, id_producto, cantidad, precio_unitario)
            VALUES (p_id_venta, v_prod, v_lineas(v_prod), v_precio);

            v_prod := v_lineas.NEXT(v_prod);
         END LOOP;

         UPDATE encabezado_venta
            SET estado = 'COMPLETADA'
          WHERE id_venta = p_id_venta
         RETURNING total INTO p_total;

         pkg_contexto.limpiar;

         COMMIT;

      EXCEPTION
         WHEN OTHERS THEN
            v_codigo  := SQLCODE;
            v_mensaje := SQLERRM;

            ROLLBACK;
            pkg_contexto.limpiar;
            p_id_venta := NULL;
            p_total    := NULL;
            log_error('VENTA', p_id_sucursal, p_id_empleado, v_codigo, v_mensaje);
            RAISE;
      END;
   END registrar_venta;

   PROCEDURE vender_producto (
      p_id_sucursal  IN  NUMBER,
      p_id_cliente   IN  NUMBER,
      p_id_empleado  IN  NUMBER,
      p_id_producto  IN  NUMBER,
      p_cantidad     IN  NUMBER,
      p_id_venta     OUT NUMBER,
      p_total        OUT NUMBER
   ) IS
      v_p t_numeros;
      v_c t_numeros;
   BEGIN
      v_p(1) := p_id_producto;
      v_c(1) := p_cantidad;
      registrar_venta(p_id_sucursal, p_id_cliente, p_id_empleado, v_p, v_c, p_id_venta, p_total);
   END vender_producto;

   PROCEDURE anular_venta (
      p_id_venta  IN NUMBER,
      p_motivo    IN VARCHAR2
   ) IS
      v_estado  encabezado_venta.estado%TYPE;
      v_suc     encabezado_venta.id_sucursal%TYPE;
      v_emp     encabezado_venta.id_empleado%TYPE;
      v_codigo  NUMBER;
      v_mensaje VARCHAR2(500);
   BEGIN
      BEGIN
         SET TRANSACTION NAME 'ANULACION_EPA';
      EXCEPTION
         WHEN e_tx_activa THEN
            RAISE_APPLICATION_ERROR(-20023,
               'Hay cambios pendientes en esta sesión. Ejecute COMMIT o ROLLBACK antes de anular.');
      END;

      BEGIN
         SELECT estado, id_sucursal, id_empleado
           INTO v_estado, v_suc, v_emp
           FROM encabezado_venta
          WHERE id_venta = p_id_venta
            FOR UPDATE;

         IF v_estado <> 'COMPLETADA' THEN
            RAISE_APPLICATION_ERROR(-20022,
               'La factura ' || p_id_venta || ' está ' || v_estado || ' y no se puede anular.');
         END IF;

         pkg_contexto.g_id_venta    := p_id_venta;
         pkg_contexto.g_tipo        := 'ANULACION';
         pkg_contexto.g_observacion := SUBSTR('Anulación: ' || p_motivo, 1, 200);

         FOR d IN (SELECT id_producto, cantidad
                     FROM detalle_venta
                    WHERE id_venta = p_id_venta
                    ORDER BY id_producto) LOOP
            UPDATE inventario
               SET stock = stock + d.cantidad
             WHERE id_sucursal = v_suc
               AND id_producto = d.id_producto;
         END LOOP;

         UPDATE encabezado_venta SET estado = 'ANULADA' WHERE id_venta = p_id_venta;

         pkg_contexto.limpiar;
         COMMIT;

      EXCEPTION
         WHEN NO_DATA_FOUND THEN
            ROLLBACK;
            pkg_contexto.limpiar;
            RAISE_APPLICATION_ERROR(-20022, 'La factura ' || p_id_venta || ' no existe.');
         WHEN OTHERS THEN
            v_codigo  := SQLCODE;
            v_mensaje := SQLERRM;
            ROLLBACK;
            pkg_contexto.limpiar;
            log_error('ANULACION', v_suc, v_emp, v_codigo, v_mensaje);
            RAISE;
      END;
   END anular_venta;

   PROCEDURE registrar_entrada (
      p_id_sucursal  IN NUMBER,
      p_id_producto  IN NUMBER,
      p_cantidad     IN NUMBER,
      p_observacion  IN VARCHAR2 DEFAULT 'Ingreso de mercadería'
   ) IS
      v_stock inventario.stock%TYPE;
   BEGIN
      IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
         RAISE_APPLICATION_ERROR(-20020, 'La cantidad de ingreso debe ser mayor a 0.');
      END IF;

      BEGIN
         SET TRANSACTION NAME 'ENTRADA_EPA';
      EXCEPTION
         WHEN e_tx_activa THEN
            RAISE_APPLICATION_ERROR(-20023,
               'Hay cambios pendientes en esta sesión. Ejecute COMMIT o ROLLBACK antes.');
      END;

      BEGIN
         SELECT stock INTO v_stock
           FROM inventario
          WHERE id_sucursal = p_id_sucursal
            AND id_producto = p_id_producto
            FOR UPDATE;

         pkg_contexto.g_tipo        := 'ENTRADA';
         pkg_contexto.g_observacion := SUBSTR(p_observacion, 1, 200);

         UPDATE inventario
            SET stock = stock + p_cantidad
          WHERE id_sucursal = p_id_sucursal
            AND id_producto = p_id_producto;

         pkg_contexto.limpiar;
         COMMIT;
      EXCEPTION
         WHEN NO_DATA_FOUND THEN
            ROLLBACK;
            pkg_contexto.limpiar;
            RAISE_APPLICATION_ERROR(-20021,
               'El producto ' || p_id_producto || ' no existe en la sucursal ' || p_id_sucursal);
         WHEN OTHERS THEN
            ROLLBACK;
            pkg_contexto.limpiar;
            RAISE;
      END;
   END registrar_entrada;

   FUNCTION stock_disponible (
      p_id_sucursal  IN NUMBER,
      p_id_producto  IN NUMBER
   ) RETURN NUMBER IS
      v_stock NUMBER;
   BEGIN
      SELECT stock INTO v_stock
        FROM inventario
       WHERE id_sucursal = p_id_sucursal
         AND id_producto = p_id_producto;
      RETURN v_stock;
   EXCEPTION
      WHEN NO_DATA_FOUND THEN RETURN NULL;
   END stock_disponible;

END pkg_ventas;
/

SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_name = 'PKG_VENTAS';

ROLLBACK;

DECLARE
   v_suc   NUMBER;
   v_emp   NUMBER;
   v_cli   NUMBER;
   v_prod  pkg_ventas.t_numeros;
   v_cant  pkg_ventas.t_numeros;
   v_id    NUMBER;
   v_total NUMBER;
BEGIN
   SELECT id_sucursal INTO v_suc FROM sucursal WHERE nombre = 'Plaza Madero';
   SELECT MIN(id_empleado) INTO v_emp FROM empleado WHERE id_sucursal = v_suc AND puesto = 'CAJERO';
   SELECT id_cliente INTO v_cli FROM cliente WHERE nit = 'CF';

   SELECT id_producto BULK COLLECT INTO v_prod
     FROM (SELECT id_producto FROM inventario
            WHERE id_sucursal = v_suc AND stock >= 10
            ORDER BY id_producto)
    WHERE ROWNUM <= 3;

   v_cant(1) := 2;  v_cant(2) := 1;  v_cant(3) := 3;

   DBMS_OUTPUT.PUT_LINE('--- PRUEBA 1: venta exitosa ---');
   FOR i IN 1 .. 3 LOOP
      DBMS_OUTPUT.PUT_LINE('Producto ' || v_prod(i) || ' stock antes: ' ||
                           pkg_ventas.stock_disponible(v_suc, v_prod(i)));
   END LOOP;

   pkg_ventas.registrar_venta(v_suc, v_cli, v_emp, v_prod, v_cant, v_id, v_total);

   DBMS_OUTPUT.PUT_LINE('Factura ' || v_id || ' COMPLETADA. Total: Q' || v_total);
   FOR i IN 1 .. 3 LOOP
      DBMS_OUTPUT.PUT_LINE('Producto ' || v_prod(i) || ' stock después: ' ||
                           pkg_ventas.stock_disponible(v_suc, v_prod(i)));
   END LOOP;
END;
/

COLUMN producto FORMAT A35
SELECT e.id_venta, e.estado, e.total, d.id_producto, p.nombre AS producto,
       d.cantidad, d.precio_unitario, d.subtotal
  FROM encabezado_venta e
  JOIN detalle_venta d ON d.id_venta = e.id_venta
  JOIN producto p      ON p.id_producto = d.id_producto
 WHERE e.id_venta = (SELECT MAX(id_venta) FROM encabezado_venta);

DECLARE
   v_suc    NUMBER;
   v_emp    NUMBER;
   v_cli    NUMBER;
   v_prod   pkg_ventas.t_numeros;
   v_cant   pkg_ventas.t_numeros;
   v_id     NUMBER;
   v_total  NUMBER;
   v_antes  NUMBER;
   v_despues NUMBER;
BEGIN
   SELECT id_sucursal INTO v_suc FROM sucursal WHERE nombre = 'Plaza Madero';
   SELECT MIN(id_empleado) INTO v_emp FROM empleado WHERE id_sucursal = v_suc AND puesto = 'CAJERO';
   SELECT id_cliente INTO v_cli FROM cliente WHERE nit = 'CF';
   SELECT MIN(id_producto) INTO v_prod(1) FROM inventario WHERE id_sucursal = v_suc;
   v_cant(1) := 99999;

   SELECT COUNT(*) INTO v_antes FROM encabezado_venta;

   DBMS_OUTPUT.PUT_LINE('--- PRUEBA 2: stock insuficiente ---');
   BEGIN
      pkg_ventas.registrar_venta(v_suc, v_cli, v_emp, v_prod, v_cant, v_id, v_total);
      DBMS_OUTPUT.PUT_LINE('ERROR: la venta no debió pasar');
   EXCEPTION
      WHEN OTHERS THEN
         DBMS_OUTPUT.PUT_LINE('Venta rechazada -> ' || SQLERRM);
   END;

   SELECT COUNT(*) INTO v_despues FROM encabezado_venta;
   DBMS_OUTPUT.PUT_LINE('Facturas antes: ' || v_antes || ' / después: ' || v_despues ||
                        CASE WHEN v_antes = v_despues THEN '  -> OK, ROLLBACK correcto'
                             ELSE '  -> ERROR' END);
END;
/

COLUMN mensaje FORMAT A80
SELECT id_log, fecha, operacion, codigo_error, mensaje FROM log_venta_fallida ORDER BY id_log;

DECLARE
   v_id NUMBER;
BEGIN
   SELECT MAX(id_venta) INTO v_id FROM encabezado_venta WHERE estado = 'COMPLETADA';
   DBMS_OUTPUT.PUT_LINE('--- PRUEBA 3: anulación de la factura ' || v_id || ' ---');
   pkg_ventas.anular_venta(v_id, 'Prueba de anulación');
   DBMS_OUTPUT.PUT_LINE('Factura ' || v_id || ' ANULADA y stock devuelto.');
END;
/

COLUMN tipo        FORMAT A10
COLUMN observacion FORMAT A40
SELECT id_movimiento, id_producto, tipo, cantidad, stock_anterior, stock_nuevo, observacion
  FROM movimiento_inventario
 WHERE id_venta = (SELECT MAX(id_venta) FROM encabezado_venta)
 ORDER BY id_movimiento;

COLUMN detalle FORMAT A60
SELECT id_bitacora, tabla, operacion, id_registro, detalle, fecha
  FROM bitacora_auditoria
 ORDER BY id_bitacora;
