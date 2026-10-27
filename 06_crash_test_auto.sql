SET SERVEROUTPUT ON

ROLLBACK;

DECLARE
   v_suc      NUMBER;
   v_emp      NUMBER;
   v_cli      NUMBER;
   v_prod     pkg_ventas.t_numeros;
   v_cant     pkg_ventas.t_numeros;
   v_id       NUMBER;
   v_total    NUMBER;
   v_lista    VARCHAR2(4000);

   a_fact  NUMBER; d_fact  NUMBER;
   a_det   NUMBER; d_det   NUMBER;
   a_pend  NUMBER; d_pend  NUMBER;
   a_stock NUMBER; d_stock NUMBER;
   a_mov   NUMBER; d_mov   NUMBER;
   a_log   NUMBER; d_log   NUMBER;

   PROCEDURE linea (p_txt VARCHAR2, p_antes NUMBER, p_desp NUMBER, p_debe_igual BOOLEAN := TRUE) IS
      v_res VARCHAR2(20);
   BEGIN
      IF p_debe_igual THEN
         v_res := CASE WHEN p_antes = p_desp THEN 'OK (igual)' ELSE '*** CAMBIÓ ***' END;
      ELSE
         v_res := CASE WHEN p_desp = p_antes + 1 THEN 'OK (+1 log)' ELSE 'revisar' END;
      END IF;
      DBMS_OUTPUT.PUT_LINE(RPAD(p_txt, 38) || LPAD(p_antes, 10) || LPAD(p_desp, 10) || '   ' || v_res);
   END;

   PROCEDURE foto (p_fact OUT NUMBER, p_det OUT NUMBER, p_pend OUT NUMBER,
                   p_stock OUT NUMBER, p_mov OUT NUMBER, p_log OUT NUMBER) IS
   BEGIN
      SELECT COUNT(*) INTO p_fact FROM encabezado_venta;
      SELECT COUNT(*) INTO p_det  FROM detalle_venta;
      SELECT COUNT(*) INTO p_pend FROM encabezado_venta WHERE estado = 'PENDIENTE';

      p_stock := 0;
      FOR i IN 1 .. v_prod.COUNT LOOP
         p_stock := p_stock + pkg_ventas.stock_disponible(v_suc, v_prod(i));
      END LOOP;
      SELECT COUNT(*) INTO p_mov FROM movimiento_inventario;
      SELECT COUNT(*) INTO p_log FROM log_venta_fallida;
   END;

BEGIN
   SELECT id_sucursal INTO v_suc FROM sucursal WHERE nombre = 'Roosevelt';
   SELECT MIN(id_empleado) INTO v_emp FROM empleado WHERE id_sucursal = v_suc AND puesto = 'CAJERO';
   SELECT id_cliente INTO v_cli FROM cliente WHERE nombre = 'Constructora Los Altos, S.A.';

   SELECT i.id_producto BULK COLLECT INTO v_prod
     FROM inventario i
     JOIN producto  p ON p.id_producto  = i.id_producto
     JOIN categoria c ON c.id_categoria = p.id_categoria
    WHERE i.id_sucursal = v_suc
      AND i.stock >= 2
    ORDER BY CASE WHEN c.nombre = 'Construcción' THEN 0 ELSE 1 END, p.id_producto
    FETCH FIRST 50 ROWS ONLY;

   FOR i IN 1 .. v_prod.COUNT LOOP
      v_cant(i) := 2;
   END LOOP;

   DBMS_OUTPUT.PUT_LINE('==============================================================');
   DBMS_OUTPUT.PUT_LINE(' CRASH TEST: venta de ' || v_prod.COUNT || ' artículos en Roosevelt');
   DBMS_OUTPUT.PUT_LINE(' Cliente: Constructora Los Altos, S.A.  -  Cajero: ' || v_emp);
   DBMS_OUTPUT.PUT_LINE(' La conexión "se cae" en el ARTÍCULO 25');
   DBMS_OUTPUT.PUT_LINE('==============================================================');

   foto(a_fact, a_det, a_pend, a_stock, a_mov, a_log);

   BEGIN
      pkg_ventas.registrar_venta(v_suc, v_cli, v_emp, v_prod, v_cant,
                                 v_id, v_total, p_simular_falla_en => 25);
      DBMS_OUTPUT.PUT_LINE('ERROR: la venta no debió completarse');
   EXCEPTION
      WHEN OTHERS THEN
         DBMS_OUTPUT.PUT_LINE('>> ' || SQLERRM);
         DBMS_OUTPUT.PUT_LINE('>> El procedimiento ejecutó ROLLBACK.');
   END;

   foto(d_fact, d_det, d_pend, d_stock, d_mov, d_log);

   DBMS_OUTPUT.PUT_LINE('');
   DBMS_OUTPUT.PUT_LINE(RPAD('INDICADOR', 38) || LPAD('ANTES', 10) || LPAD('DESPUÉS', 10) || '   RESULTADO');
   DBMS_OUTPUT.PUT_LINE(RPAD('-', 75, '-'));
   linea('Facturas (ENCABEZADO_VENTA)',       a_fact,  d_fact);
   linea('Facturas en estado PENDIENTE',      a_pend,  d_pend);
   linea('Líneas de detalle (DETALLE_VENTA)', a_det,   d_det);
   linea('Stock total de los 50 productos',   a_stock, d_stock);
   linea('Movimientos en kardex',             a_mov,   d_mov);
   linea('Intentos fallidos registrados',     a_log,   d_log, FALSE);
   DBMS_OUTPUT.PUT_LINE(RPAD('-', 75, '-'));

   IF a_fact = d_fact AND a_det = d_det AND a_pend = d_pend
      AND a_stock = d_stock AND a_mov = d_mov THEN
      DBMS_OUTPUT.PUT_LINE('CONCLUSIÓN: ENCABEZADO_VENTA e INVENTARIO conservan su estado original.');
      DBMS_OUTPUT.PUT_LINE('            No quedó factura a medias. ATOMICIDAD comprobada.');
   ELSE
      DBMS_OUTPUT.PUT_LINE('CONCLUSIÓN: *** HUBO DIFERENCIAS, REVISAR ***');
   END IF;
END;
/

COLUMN mensaje FORMAT A90
SELECT id_log, TO_CHAR(fecha, 'DD/MM/YYYY HH24:MI:SS') AS fecha, codigo_error, mensaje
  FROM log_venta_fallida
 ORDER BY id_log DESC
 FETCH FIRST 1 ROWS ONLY;

SELECT COUNT(*) AS facturas_pendientes FROM encabezado_venta WHERE estado = 'PENDIENTE';
