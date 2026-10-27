SET SERVEROUTPUT ON SIZE UNLIMITED

ROLLBACK;

DECLARE
   v_suc        NUMBER;
   v_suc2       NUMBER;
   v_emp        NUMBER;
   v_emp_otro   NUMBER;
   v_cli        NUMBER;
   v_prod       NUMBER;
   v_prod2      NUMBER;
   v_nit        VARCHAR2(15);
   v_venta_ok   NUMBER;
   v_venta_anul NUMBER;

   v_total  PLS_INTEGER := 0;
   v_bien   PLS_INTEGER := 0;

   PROCEDURE probar (p_desc VARCHAR2, p_sql VARCHAR2, p_esperado NUMBER) IS
      v_codigo NUMBER;
      v_msg    VARCHAR2(400);
   BEGIN
      v_total := v_total + 1;
      DBMS_OUTPUT.PUT_LINE('[' || LPAD(v_total, 2, '0') || '] ' || p_desc);
      BEGIN
         EXECUTE IMMEDIATE p_sql;
         ROLLBACK;
         DBMS_OUTPUT.PUT_LINE('     *** FALLÓ: la operación fue ACEPTADA ***');
      EXCEPTION
         WHEN OTHERS THEN
            v_codigo := SQLCODE;
            v_msg    := SUBSTR(REPLACE(SQLERRM, CHR(10), ' '), 1, 110);
            ROLLBACK;
            IF v_codigo = p_esperado THEN
               v_bien := v_bien + 1;
               DBMS_OUTPUT.PUT_LINE('     RECHAZADA OK  -> ' || v_msg);
            ELSE
               DBMS_OUTPUT.PUT_LINE('     Rechazada con otro error (esperado ' ||
                                    p_esperado || ') -> ' || v_msg);
            END IF;
      END;
      DBMS_OUTPUT.PUT_LINE('');
   END probar;

BEGIN
   SELECT id_sucursal INTO v_suc  FROM sucursal WHERE nombre = 'Roosevelt';
   SELECT id_sucursal INTO v_suc2 FROM sucursal WHERE nombre = 'Plaza Madero';
   SELECT MIN(id_empleado) INTO v_emp      FROM empleado WHERE id_sucursal = v_suc  AND puesto = 'CAJERO';
   SELECT MIN(id_empleado) INTO v_emp_otro FROM empleado WHERE id_sucursal = v_suc2 AND puesto = 'CAJERO';
   SELECT id_cliente INTO v_cli FROM cliente WHERE nit = 'CF';
   SELECT MIN(id_producto) INTO v_prod FROM detalle_venta;
   SELECT MAX(id_producto) INTO v_prod2 FROM inventario WHERE id_sucursal = v_suc AND stock >= 5;
   SELECT MIN(nit) INTO v_nit FROM cliente WHERE nit <> 'CF';
   SELECT MAX(id_venta) INTO v_venta_ok   FROM encabezado_venta WHERE estado = 'COMPLETADA';
   SELECT MAX(id_venta) INTO v_venta_anul FROM encabezado_venta WHERE estado = 'ANULADA';

   DBMS_OUTPUT.PUT_LINE('=====================================================================');
   DBMS_OUTPUT.PUT_LINE(' PRUEBAS DE INTEGRIDAD - FERRETERÍAS EPA');
   DBMS_OUTPUT.PUT_LINE('=====================================================================');
   DBMS_OUTPUT.PUT_LINE('');

   DBMS_OUTPUT.PUT_LINE('--- LLAVES PRIMARIAS, UNIQUE Y AUTONUMÉRICOS ---');
   probar('Crear una sucursal con nombre repetido (Roosevelt)',
      q'[INSERT INTO sucursal (nombre, direccion, municipio, telefono)
         VALUES ('Roosevelt', 'X', 'Guatemala', '22222222')]', -1);

   probar('Registrar un cliente con un NIT que ya existe (' || v_nit || ')',
      'INSERT INTO cliente (nit, nombre) VALUES (''' || v_nit || ''', ''Cliente duplicado'')', -1);

   probar('Duplicar un producto en el inventario de la misma sucursal',
      'INSERT INTO inventario (id_sucursal, id_producto, stock) VALUES ('
       || v_suc || ', ' || v_prod2 || ', 10)', -1);

   probar('Forzar un valor en la columna autonumérica (IDENTITY)',
      q'[INSERT INTO categoria (id_categoria, nombre) VALUES (999, 'Categoría forzada')]', -32795);

   DBMS_OUTPUT.PUT_LINE('--- LLAVES FORÁNEAS (problema 4 del sistema legacy) ---');
   probar('Eliminar un producto que tiene ventas registradas',
      'DELETE FROM producto WHERE id_producto = ' || v_prod, -2292);

   probar('Eliminar un cajero que tiene facturas',
      'DELETE FROM empleado WHERE id_empleado = (SELECT MIN(id_empleado) FROM encabezado_venta)', -2292);

   probar('Agregar un detalle a una factura que no existe (id 999999)',
      'INSERT INTO detalle_venta (id_venta, id_producto, cantidad, precio_unitario) VALUES (999999, '
       || v_prod || ', 1, 10)', -2291);

   probar('Crear una factura para un cliente que no existe (id 999999)',
      'INSERT INTO encabezado_venta (id_sucursal, id_cliente, id_empleado) VALUES ('
       || v_suc || ', 999999, ' || v_emp || ')', -2291);

   DBMS_OUTPUT.PUT_LINE('--- RESTRICCIONES CHECK Y NOT NULL ---');
   probar('Dejar el stock en negativo (-5)',
      'UPDATE inventario SET stock = -5 WHERE id_sucursal = ' || v_suc || ' AND id_producto = ' || v_prod2, -2290);

   probar('Poner precio 0 a un producto',
      'UPDATE producto SET precio_sugerido = 0 WHERE id_producto = ' || v_prod, -2290);

   probar('Vender cantidad 0 en una factura nueva',
      'DECLARE v NUMBER; BEGIN
         INSERT INTO encabezado_venta (id_sucursal, id_cliente, id_empleado)
         VALUES (' || v_suc || ', ' || v_cli || ', ' || v_emp || ') RETURNING id_venta INTO v;
         INSERT INTO detalle_venta (id_venta, id_producto, cantidad) VALUES (v, ' || v_prod2 || ', 0);
       END;', -2290);

   probar('Registrar un NIT con formato inválido (ABC-123)',
      q'[INSERT INTO cliente (nit, nombre) VALUES ('ABC-123', 'NIT malo')]', -2290);

   probar('Registrar un teléfono de cliente con 3 dígitos',
      q'[UPDATE cliente SET telefono = '123' WHERE nit <> 'CF' AND ROWNUM = 1]', -2290);

   probar('Crear un producto sin nombre',
      'INSERT INTO producto (codigo, nombre, id_categoria, precio_sugerido)
       VALUES (''TST-001'', NULL, (SELECT MIN(id_categoria) FROM categoria), 10)', -1400);

   DBMS_OUTPUT.PUT_LINE('--- TRIGGERS Y REGLAS DE NEGOCIO (problema 3 del sistema legacy) ---');
   probar('Borrar una factura (factura ' || v_venta_ok || ')',
      'DELETE FROM encabezado_venta WHERE id_venta = ' || v_venta_ok, -20013);

   probar('Cambiar el total de una factura COMPLETADA',
      'UPDATE encabezado_venta SET total = 1 WHERE id_venta = ' || v_venta_ok, -20011);

   probar('Agregar un producto a una factura COMPLETADA',
      'INSERT INTO detalle_venta (id_venta, id_producto, cantidad) VALUES ('
       || v_venta_ok || ', ' || v_prod2 || ', 1)', -20012);

   probar('Borrar una línea de una factura COMPLETADA',
      'DELETE FROM detalle_venta WHERE id_venta = ' || v_venta_ok, -20012);

   probar('Facturar en Roosevelt con un cajero de Plaza Madero',
      'INSERT INTO encabezado_venta (id_sucursal, id_cliente, id_empleado) VALUES ('
       || v_suc || ', ' || v_cli || ', ' || v_emp_otro || ')', -20015);

   probar('Vender un producto dado de baja',
      'DECLARE v NUMBER; BEGIN
         UPDATE producto SET activo = ''N'' WHERE id_producto = ' || v_prod2 || ';
         INSERT INTO encabezado_venta (id_sucursal, id_cliente, id_empleado)
         VALUES (' || v_suc || ', ' || v_cli || ', ' || v_emp || ') RETURNING id_venta INTO v;
         INSERT INTO detalle_venta (id_venta, id_producto, cantidad) VALUES (v, ' || v_prod2 || ', 1);
       END;', -20014);

   probar('Vender más unidades de las que hay (procedimiento de venta)',
      'DECLARE v NUMBER; t NUMBER; BEGIN
         pkg_ventas.vender_producto(' || v_suc || ', ' || v_cli || ', ' || v_emp || ', '
                                     || v_prod2 || ', 999999, v, t);
       END;', -20001);

   IF v_venta_anul IS NOT NULL THEN
      probar('Anular otra vez una factura ya ANULADA (factura ' || v_venta_anul || ')',
         'BEGIN pkg_ventas.anular_venta(' || v_venta_anul || ', ''Segundo intento''); END;', -20022);
   END IF;

   DBMS_OUTPUT.PUT_LINE('=====================================================================');
   DBMS_OUTPUT.PUT_LINE(' RESUMEN: ' || v_bien || ' de ' || v_total ||
                        ' operaciones inválidas fueron RECHAZADAS por el motor.');
   IF v_bien = v_total THEN
      DBMS_OUTPUT.PUT_LINE(' La base de datos NO se pudo dejar inconsistente.');
   END IF;
   DBMS_OUTPUT.PUT_LINE('=====================================================================');
END;
/

SELECT (SELECT COUNT(*) FROM inventario WHERE stock < 0)                     AS stock_negativo,
       (SELECT COUNT(*) FROM encabezado_venta WHERE estado = 'PENDIENTE')     AS facturas_pendientes,
       (SELECT COUNT(*) FROM producto WHERE activo = 'N')                     AS productos_inactivos,
       (SELECT COUNT(*) FROM encabezado_venta e
         WHERE e.total <> (SELECT NVL(SUM(d.subtotal), 0)
                             FROM detalle_venta d WHERE d.id_venta = e.id_venta)) AS facturas_descuadradas,
       (SELECT COUNT(*) FROM detalle_venta d
         WHERE NOT EXISTS (SELECT 1 FROM producto p WHERE p.id_producto = d.id_producto)) AS ventas_sin_producto
  FROM dual;
