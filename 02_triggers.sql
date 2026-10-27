SET SERVEROUTPUT ON

BEGIN
   BEGIN DBMS_SCHEDULER.DROP_JOB('JOB_CIERRE_INVENTARIO', force => TRUE);
   EXCEPTION WHEN OTHERS THEN NULL; END;
   BEGIN EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW mv_inventario_general';
   EXCEPTION WHEN OTHERS THEN NULL; END;
   BEGIN EXECUTE IMMEDIATE 'DROP TABLE inventario_cierre_diario CASCADE CONSTRAINTS PURGE';
   EXCEPTION WHEN OTHERS THEN NULL; END;
   BEGIN EXECUTE IMMEDIATE 'DROP TABLE bitacora_auditoria CASCADE CONSTRAINTS PURGE';
   EXCEPTION WHEN OTHERS THEN NULL; END;
   DBMS_OUTPUT.PUT_LINE('Limpieza previa completada.');
END;
/

DECLARE
   v_cnt NUMBER;
BEGIN
   SELECT COUNT(*) INTO v_cnt FROM user_constraints
    WHERE constraint_name = 'FK_MOVIMIENTO_INVENTARIO';
   IF v_cnt > 0 THEN
      EXECUTE IMMEDIATE 'ALTER TABLE movimiento_inventario DROP CONSTRAINT fk_movimiento_inventario';
      EXECUTE IMMEDIATE 'ALTER TABLE movimiento_inventario ADD CONSTRAINT fk_mov_sucursal
                         FOREIGN KEY (id_sucursal) REFERENCES sucursal (id_sucursal)';
      EXECUTE IMMEDIATE 'ALTER TABLE movimiento_inventario ADD CONSTRAINT fk_mov_producto
                         FOREIGN KEY (id_producto) REFERENCES producto (id_producto)';
      DBMS_OUTPUT.PUT_LINE('FK del kardex ajustada.');
   ELSE
      DBMS_OUTPUT.PUT_LINE('FK del kardex ya estaba correcta.');
   END IF;
END;
/

CREATE TABLE bitacora_auditoria (
   id_bitacora     NUMBER          GENERATED ALWAYS AS IDENTITY,
   tabla           VARCHAR2(30)    NOT NULL,
   operacion       VARCHAR2(10)    NOT NULL,
   id_registro     VARCHAR2(40)    NOT NULL,
   detalle         VARCHAR2(400),
   usuario_bd      VARCHAR2(30)    DEFAULT USER NOT NULL,
   equipo          VARCHAR2(64)    DEFAULT SYS_CONTEXT('USERENV','HOST'),
   fecha           DATE            DEFAULT SYSDATE NOT NULL,
   CONSTRAINT pk_bitacora     PRIMARY KEY (id_bitacora),
   CONSTRAINT ck_bitacora_op  CHECK (operacion IN ('INSERT','UPDATE','DELETE'))
);
COMMENT ON TABLE bitacora_auditoria IS 'Auditoría de cambios sensibles (precios, bajas, anulaciones)';

CREATE TABLE inventario_cierre_diario (
   fecha_cierre   DATE        NOT NULL,
   id_sucursal    NUMBER      NOT NULL,
   id_producto    NUMBER      NOT NULL,
   stock          NUMBER(10)  NOT NULL,
   stock_minimo   NUMBER(10)  NOT NULL,
   bajo_minimo    CHAR(1)     NOT NULL,
   CONSTRAINT pk_cierre          PRIMARY KEY (fecha_cierre, id_sucursal, id_producto),
   CONSTRAINT fk_cierre_sucursal FOREIGN KEY (id_sucursal) REFERENCES sucursal (id_sucursal),
   CONSTRAINT fk_cierre_producto FOREIGN KEY (id_producto) REFERENCES producto (id_producto),
   CONSTRAINT ck_cierre_stock    CHECK (stock >= 0),
   CONSTRAINT ck_cierre_bajo     CHECK (bajo_minimo IN ('S','N'))
);
COMMENT ON TABLE inventario_cierre_diario IS 'Foto diaria del inventario de cada sucursal (la llena el JOB de las 23:00)';

CREATE OR REPLACE PACKAGE pkg_contexto AS
   g_id_venta     NUMBER;
   g_tipo         VARCHAR2(10);
   g_observacion  VARCHAR2(200);
   PROCEDURE limpiar;
END pkg_contexto;
/

CREATE OR REPLACE PACKAGE BODY pkg_contexto AS
   PROCEDURE limpiar IS
   BEGIN
      g_id_venta    := NULL;
      g_tipo        := NULL;
      g_observacion := NULL;
   END limpiar;
END pkg_contexto;
/

CREATE OR REPLACE TRIGGER trg_inv_fecha
BEFORE UPDATE ON inventario
FOR EACH ROW
BEGIN
   :NEW.fecha_actualizacion := SYSDATE;
END;
/

CREATE OR REPLACE TRIGGER trg_inv_movimiento
AFTER UPDATE OF stock ON inventario
FOR EACH ROW
WHEN (NEW.stock <> OLD.stock)
DECLARE
   v_tipo  VARCHAR2(10);
   v_venta NUMBER        := pkg_contexto.g_id_venta;
   v_obs   VARCHAR2(200) := pkg_contexto.g_observacion;
BEGIN
   v_tipo := NVL(pkg_contexto.g_tipo,
                 CASE WHEN :NEW.stock > :OLD.stock THEN 'ENTRADA' ELSE 'SALIDA' END);

   INSERT INTO movimiento_inventario
          (id_sucursal, id_producto, tipo, cantidad,
           stock_anterior, stock_nuevo, id_venta, observacion)
   VALUES (:NEW.id_sucursal, :NEW.id_producto, v_tipo, ABS(:NEW.stock - :OLD.stock),
           :OLD.stock, :NEW.stock, v_venta, v_obs);
END;
/

CREATE OR REPLACE TRIGGER trg_prod_auditoria
AFTER UPDATE OF precio_sugerido, activo ON producto
FOR EACH ROW
BEGIN
   IF :NEW.precio_sugerido <> :OLD.precio_sugerido THEN
      INSERT INTO bitacora_auditoria (tabla, operacion, id_registro, detalle)
      VALUES ('PRODUCTO', 'UPDATE', TO_CHAR(:NEW.id_producto),
              'Precio ' || :NEW.codigo || ': Q' || TO_CHAR(:OLD.precio_sugerido, 'FM999990.00')
              || ' -> Q' || TO_CHAR(:NEW.precio_sugerido, 'FM999990.00'));
   END IF;

   IF :NEW.activo <> :OLD.activo THEN
      INSERT INTO bitacora_auditoria (tabla, operacion, id_registro, detalle)
      VALUES ('PRODUCTO', 'UPDATE', TO_CHAR(:NEW.id_producto),
              CASE :NEW.activo WHEN 'N' THEN 'Baja lógica de ' ELSE 'Reactivación de ' END
              || :NEW.codigo);
   END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_venta_validar
BEFORE INSERT ON encabezado_venta
FOR EACH ROW
DECLARE
   v_suc     empleado.id_sucursal%TYPE;
   v_activo  empleado.activo%TYPE;
   v_puesto  empleado.puesto%TYPE;
   v_cli_act cliente.activo%TYPE;
BEGIN
   :NEW.estado := 'PENDIENTE';
   :NEW.total  := 0;
   IF :NEW.fecha_venta IS NULL THEN
      :NEW.fecha_venta := SYSDATE;
   END IF;

   SELECT id_sucursal, activo, puesto
     INTO v_suc, v_activo, v_puesto
     FROM empleado
    WHERE id_empleado = :NEW.id_empleado;

   IF v_activo <> 'S' OR v_suc <> :NEW.id_sucursal
      OR v_puesto NOT IN ('CAJERO','SUPERVISOR','GERENTE') THEN
      RAISE_APPLICATION_ERROR(-20015,
         'El empleado ' || :NEW.id_empleado ||
         ' no está activo, no es de la sucursal ' || :NEW.id_sucursal ||
         ' o no puede facturar.');
   END IF;

   SELECT activo INTO v_cli_act FROM cliente WHERE id_cliente = :NEW.id_cliente;
   IF v_cli_act <> 'S' THEN
      RAISE_APPLICATION_ERROR(-20016, 'El cliente ' || :NEW.id_cliente || ' está inactivo.');
   END IF;

EXCEPTION
   WHEN NO_DATA_FOUND THEN
      NULL;
END;
/

CREATE OR REPLACE TRIGGER trg_venta_proteger
BEFORE UPDATE ON encabezado_venta
FOR EACH ROW
BEGIN
   IF :OLD.estado = 'ANULADA' THEN
      RAISE_APPLICATION_ERROR(-20010,
         'La factura ' || :OLD.id_venta || ' está ANULADA y no se puede modificar.');
   END IF;

   IF :OLD.estado = 'COMPLETADA' THEN
      IF :NEW.estado <> 'ANULADA'
         OR :NEW.total       <> :OLD.total
         OR :NEW.id_sucursal <> :OLD.id_sucursal
         OR :NEW.id_cliente  <> :OLD.id_cliente
         OR :NEW.id_empleado <> :OLD.id_empleado
         OR :NEW.fecha_venta <> :OLD.fecha_venta THEN
         RAISE_APPLICATION_ERROR(-20011,
            'La factura ' || :OLD.id_venta || ' está COMPLETADA: solo se permite anularla.');
      END IF;

      INSERT INTO bitacora_auditoria (tabla, operacion, id_registro, detalle)
      VALUES ('ENCABEZADO_VENTA', 'UPDATE', TO_CHAR(:OLD.id_venta),
              'Factura anulada. Total: Q' || TO_CHAR(:OLD.total, 'FM9999990.00'));
   END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_venta_no_borrar
BEFORE DELETE ON encabezado_venta
FOR EACH ROW
BEGIN
   RAISE_APPLICATION_ERROR(-20013,
      'No se permite borrar facturas (id ' || :OLD.id_venta ||
      '). Use el estado ANULADA.');
END;
/

CREATE OR REPLACE TRIGGER trg_detalle_validar
BEFORE INSERT OR UPDATE OR DELETE ON detalle_venta
FOR EACH ROW
DECLARE
   v_estado  encabezado_venta.estado%TYPE;
   v_precio  producto.precio_sugerido%TYPE;
   v_activo  producto.activo%TYPE;
BEGIN
   BEGIN
      SELECT estado INTO v_estado
        FROM encabezado_venta
       WHERE id_venta = NVL(:NEW.id_venta, :OLD.id_venta);
   EXCEPTION
      WHEN NO_DATA_FOUND THEN v_estado := NULL;
   END;

   IF v_estado IS NOT NULL AND v_estado <> 'PENDIENTE' THEN
      RAISE_APPLICATION_ERROR(-20012,
         'La factura ' || NVL(:NEW.id_venta, :OLD.id_venta) ||
         ' está ' || v_estado || '; su detalle no se puede modificar.');
   END IF;

   IF INSERTING OR UPDATING THEN
      BEGIN
         SELECT precio_sugerido, activo INTO v_precio, v_activo
           FROM producto WHERE id_producto = :NEW.id_producto;
      EXCEPTION
         WHEN NO_DATA_FOUND THEN RETURN;
      END;

      IF v_activo <> 'S' THEN
         RAISE_APPLICATION_ERROR(-20014,
            'El producto ' || :NEW.id_producto || ' está dado de baja y no se puede vender.');
      END IF;

      IF :NEW.precio_unitario IS NULL THEN
         :NEW.precio_unitario := v_precio;
      END IF;
   END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_detalle_total
AFTER INSERT OR UPDATE OR DELETE ON detalle_venta
FOR EACH ROW
BEGIN
   IF DELETING OR UPDATING THEN
      UPDATE encabezado_venta
         SET total = total - (:OLD.cantidad * :OLD.precio_unitario)
       WHERE id_venta = :OLD.id_venta;
   END IF;

   IF INSERTING OR UPDATING THEN
      UPDATE encabezado_venta
         SET total = total + (:NEW.cantidad * :NEW.precio_unitario)
       WHERE id_venta = :NEW.id_venta;
   END IF;
END;
/

CREATE OR REPLACE VIEW v_inventario_sucursal AS
SELECT s.id_sucursal,
       s.nombre                       AS sucursal,
       p.id_producto,
       p.codigo,
       p.nombre                       AS producto,
       c.nombre                       AS categoria,
       i.stock,
       i.stock_minimo,
       CASE WHEN i.stock <= i.stock_minimo THEN 'S' ELSE 'N' END AS bajo_minimo,
       i.stock * p.precio_sugerido    AS valor_inventario,
       i.fecha_actualizacion
  FROM inventario i
  JOIN sucursal  s ON s.id_sucursal  = i.id_sucursal
  JOIN producto  p ON p.id_producto  = i.id_producto
  JOIN categoria c ON c.id_categoria = p.id_categoria;

CREATE MATERIALIZED VIEW mv_inventario_general
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS
SELECT p.id_producto,
       p.codigo,
       p.nombre                                              AS producto,
       c.nombre                                              AS categoria,
       NVL(SUM(i.stock), 0)                                  AS stock_total,
       COUNT(i.id_sucursal)                                  AS sucursales,
       SUM(CASE WHEN i.stock <= i.stock_minimo THEN 1 ELSE 0 END) AS sucursales_bajo_minimo,
       NVL(SUM(i.stock), 0) * p.precio_sugerido              AS valor_inventario
  FROM producto p
  JOIN categoria c       ON c.id_categoria = p.id_categoria
  LEFT JOIN inventario i ON i.id_producto  = p.id_producto
 GROUP BY p.id_producto, p.codigo, p.nombre, c.nombre, p.precio_sugerido;

CREATE OR REPLACE PROCEDURE sp_cierre_diario AS
   v_filas NUMBER;
BEGIN
   DBMS_MVIEW.REFRESH('MV_INVENTARIO_GENERAL', 'C');

   MERGE INTO inventario_cierre_diario d
   USING (SELECT TRUNC(SYSDATE) AS fecha_cierre, id_sucursal, id_producto,
                 stock, stock_minimo,
                 CASE WHEN stock <= stock_minimo THEN 'S' ELSE 'N' END AS bajo_minimo
            FROM inventario) x
      ON (d.fecha_cierre = x.fecha_cierre
          AND d.id_sucursal = x.id_sucursal
          AND d.id_producto = x.id_producto)
   WHEN MATCHED THEN UPDATE
        SET d.stock = x.stock, d.stock_minimo = x.stock_minimo, d.bajo_minimo = x.bajo_minimo
   WHEN NOT MATCHED THEN INSERT
        (fecha_cierre, id_sucursal, id_producto, stock, stock_minimo, bajo_minimo)
        VALUES (x.fecha_cierre, x.id_sucursal, x.id_producto, x.stock, x.stock_minimo, x.bajo_minimo);

   v_filas := SQL%ROWCOUNT;
   COMMIT;
   DBMS_OUTPUT.PUT_LINE('Cierre ' || TO_CHAR(SYSDATE,'DD/MM/YYYY') ||
                        ': ' || v_filas || ' filas registradas.');
EXCEPTION
   WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
END sp_cierre_diario;
/

BEGIN
   DBMS_SCHEDULER.CREATE_JOB(
      job_name        => 'JOB_CIERRE_INVENTARIO',
      job_type        => 'STORED_PROCEDURE',
      job_action      => 'SP_CIERRE_DIARIO',
      start_date      => SYSTIMESTAMP,
      repeat_interval => 'FREQ=DAILY;BYHOUR=23;BYMINUTE=0;BYSECOND=0',
      enabled         => TRUE,
      comments        => 'Refresca inventario general y guarda el cierre diario por sucursal');
   DBMS_OUTPUT.PUT_LINE('Job JOB_CIERRE_INVENTARIO creado.');
END;
/

COLUMN trigger_name      FORMAT A22
COLUMN table_name        FORMAT A20
COLUMN triggering_event  FORMAT A28
SELECT trigger_name, table_name, trigger_type, triggering_event, status
  FROM user_triggers
 ORDER BY table_name, trigger_name;

COLUMN object_name FORMAT A25
SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_type IN ('PACKAGE','PACKAGE BODY','PROCEDURE','TRIGGER',
                       'VIEW','MATERIALIZED VIEW')
 ORDER BY object_type, object_name;

COLUMN job_name        FORMAT A25
COLUMN repeat_interval FORMAT A45
SELECT job_name, enabled, state, repeat_interval, next_run_date
  FROM user_scheduler_jobs;
