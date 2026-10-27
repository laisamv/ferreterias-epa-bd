SET SERVEROUTPUT ON

BEGIN
   FOR t IN (SELECT table_name
               FROM user_tables
              WHERE table_name IN ('MOVIMIENTO_INVENTARIO','DETALLE_VENTA',
                                   'ENCABEZADO_VENTA','INVENTARIO','EMPLEADO',
                                   'CLIENTE','PRODUCTO','CATEGORIA','SUCURSAL'))
   LOOP
      EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
      DBMS_OUTPUT.PUT_LINE('Eliminada: ' || t.table_name);
   END LOOP;
END;
/

CREATE TABLE sucursal (
   id_sucursal     NUMBER         GENERATED ALWAYS AS IDENTITY,
   nombre          VARCHAR2(80)   NOT NULL,
   direccion       VARCHAR2(200)  NOT NULL,
   municipio       VARCHAR2(60)   NOT NULL,
   departamento    VARCHAR2(60)   DEFAULT 'Guatemala' NOT NULL,
   telefono        VARCHAR2(8)    NOT NULL,
   fecha_apertura  DATE           DEFAULT SYSDATE NOT NULL,
   activo          CHAR(1)        DEFAULT 'S' NOT NULL,
   CONSTRAINT pk_sucursal          PRIMARY KEY (id_sucursal),
   CONSTRAINT uq_sucursal_nombre   UNIQUE (nombre),
   CONSTRAINT ck_sucursal_telefono CHECK (REGEXP_LIKE(telefono, '^[0-9]{8}$')),
   CONSTRAINT ck_sucursal_activo   CHECK (activo IN ('S','N'))
);

CREATE TABLE empleado (
   id_empleado         NUMBER         GENERATED ALWAYS AS IDENTITY,
   id_sucursal         NUMBER         NOT NULL,
   dpi                 VARCHAR2(13)   NOT NULL,
   nombres             VARCHAR2(80)   NOT NULL,
   apellidos           VARCHAR2(80)   NOT NULL,
   puesto              VARCHAR2(20)   NOT NULL,
   telefono            VARCHAR2(8),
   fecha_contratacion  DATE           DEFAULT SYSDATE NOT NULL,
   activo              CHAR(1)        DEFAULT 'S' NOT NULL,
   CONSTRAINT pk_empleado          PRIMARY KEY (id_empleado),
   CONSTRAINT fk_empleado_sucursal FOREIGN KEY (id_sucursal)
                                   REFERENCES sucursal (id_sucursal),
   CONSTRAINT uq_empleado_dpi      UNIQUE (dpi),
   CONSTRAINT ck_empleado_dpi      CHECK (REGEXP_LIKE(dpi, '^[0-9]{13}$')),
   CONSTRAINT ck_empleado_puesto   CHECK (puesto IN ('CAJERO','SUPERVISOR','BODEGUERO','GERENTE')),
   CONSTRAINT ck_empleado_telefono CHECK (telefono IS NULL OR REGEXP_LIKE(telefono, '^[0-9]{8}$')),
   CONSTRAINT ck_empleado_activo   CHECK (activo IN ('S','N'))
);

CREATE TABLE categoria (
   id_categoria  NUMBER         GENERATED ALWAYS AS IDENTITY,
   nombre        VARCHAR2(50)   NOT NULL,
   descripcion   VARCHAR2(200),
   CONSTRAINT pk_categoria        PRIMARY KEY (id_categoria),
   CONSTRAINT uq_categoria_nombre UNIQUE (nombre)
);

CREATE TABLE producto (
   id_producto      NUMBER         GENERATED ALWAYS AS IDENTITY,
   codigo           VARCHAR2(20)   NOT NULL,
   nombre           VARCHAR2(120)  NOT NULL,
   id_categoria     NUMBER         NOT NULL,
   unidad_medida    VARCHAR2(15)   DEFAULT 'UNIDAD' NOT NULL,
   precio_sugerido  NUMBER(10,2)   NOT NULL,
   fecha_creacion   DATE           DEFAULT SYSDATE NOT NULL,
   activo           CHAR(1)        DEFAULT 'S' NOT NULL,
   CONSTRAINT pk_producto           PRIMARY KEY (id_producto),
   CONSTRAINT fk_producto_categoria FOREIGN KEY (id_categoria)
                                    REFERENCES categoria (id_categoria),
   CONSTRAINT uq_producto_codigo    UNIQUE (codigo),
   CONSTRAINT ck_producto_precio    CHECK (precio_sugerido > 0),
   CONSTRAINT ck_producto_unidad    CHECK (unidad_medida IN ('UNIDAD','CAJA','BOLSA','GALON',
                                                             'LITRO','METRO','LIBRA','QUINTAL',
                                                             'ROLLO','PAQUETE')),
   CONSTRAINT ck_producto_activo    CHECK (activo IN ('S','N'))
);

CREATE TABLE inventario (
   id_sucursal          NUMBER      NOT NULL,
   id_producto          NUMBER      NOT NULL,
   stock                NUMBER(10)  DEFAULT 0 NOT NULL,
   stock_minimo         NUMBER(10)  DEFAULT 5 NOT NULL,
   fecha_actualizacion  DATE        DEFAULT SYSDATE NOT NULL,
   CONSTRAINT pk_inventario          PRIMARY KEY (id_sucursal, id_producto),
   CONSTRAINT fk_inventario_sucursal FOREIGN KEY (id_sucursal)
                                     REFERENCES sucursal (id_sucursal),
   CONSTRAINT fk_inventario_producto FOREIGN KEY (id_producto)
                                     REFERENCES producto (id_producto),
   CONSTRAINT ck_inventario_stock    CHECK (stock >= 0),
   CONSTRAINT ck_inventario_minimo   CHECK (stock_minimo >= 0)
);

CREATE TABLE movimiento_inventario (
   id_movimiento   NUMBER        GENERATED ALWAYS AS IDENTITY,
   id_sucursal     NUMBER        NOT NULL,
   id_producto     NUMBER        NOT NULL,
   tipo            VARCHAR2(10)  NOT NULL,
   cantidad        NUMBER(10)    NOT NULL,
   stock_anterior  NUMBER(10)    NOT NULL,
   stock_nuevo     NUMBER(10)    NOT NULL,
   id_venta        NUMBER,
   observacion     VARCHAR2(200),
   fecha           DATE          DEFAULT SYSDATE NOT NULL,
   usuario_bd      VARCHAR2(30)  DEFAULT USER NOT NULL,
   CONSTRAINT pk_movimiento            PRIMARY KEY (id_movimiento),
   CONSTRAINT fk_mov_sucursal          FOREIGN KEY (id_sucursal)
                                       REFERENCES sucursal (id_sucursal),
   CONSTRAINT fk_mov_producto          FOREIGN KEY (id_producto)
                                       REFERENCES producto (id_producto),
   CONSTRAINT ck_movimiento_tipo       CHECK (tipo IN ('ENTRADA','SALIDA','AJUSTE','ANULACION')),
   CONSTRAINT ck_movimiento_cantidad   CHECK (cantidad > 0),
   CONSTRAINT ck_movimiento_stocks     CHECK (stock_anterior >= 0 AND stock_nuevo >= 0)
);

CREATE TABLE cliente (
   id_cliente      NUMBER         GENERATED ALWAYS AS IDENTITY,
   nit             VARCHAR2(15)   NOT NULL,
   dpi             VARCHAR2(13),
   nombre          VARCHAR2(150)  NOT NULL,
   direccion       VARCHAR2(200),
   telefono        VARCHAR2(8),
   email           VARCHAR2(100),
   fecha_registro  DATE           DEFAULT SYSDATE NOT NULL,
   activo          CHAR(1)        DEFAULT 'S' NOT NULL,
   CONSTRAINT pk_cliente          PRIMARY KEY (id_cliente),
   CONSTRAINT uq_cliente_nit      UNIQUE (nit),
   CONSTRAINT uq_cliente_dpi      UNIQUE (dpi),
   CONSTRAINT ck_cliente_nit      CHECK (nit = 'CF' OR REGEXP_LIKE(nit, '^[0-9]{4,12}[0-9K]$')),
   CONSTRAINT ck_cliente_dpi      CHECK (dpi IS NULL OR REGEXP_LIKE(dpi, '^[0-9]{13}$')),
   CONSTRAINT ck_cliente_telefono CHECK (telefono IS NULL OR REGEXP_LIKE(telefono, '^[0-9]{8}$')),
   CONSTRAINT ck_cliente_email    CHECK (email IS NULL OR REGEXP_LIKE(email, '^[^@ ]+@[^@ ]+\.[a-zA-Z]{2,}$')),
   CONSTRAINT ck_cliente_activo   CHECK (activo IN ('S','N'))
);

CREATE TABLE encabezado_venta (
   id_venta     NUMBER         GENERATED ALWAYS AS IDENTITY,
   id_sucursal  NUMBER         NOT NULL,
   id_cliente   NUMBER         NOT NULL,
   id_empleado  NUMBER         NOT NULL,
   fecha_venta  DATE           DEFAULT SYSDATE NOT NULL,
   estado       VARCHAR2(12)   DEFAULT 'PENDIENTE' NOT NULL,
   total        NUMBER(12,2)   DEFAULT 0 NOT NULL,
   CONSTRAINT pk_encabezado_venta PRIMARY KEY (id_venta),
   CONSTRAINT fk_venta_sucursal   FOREIGN KEY (id_sucursal)
                                  REFERENCES sucursal (id_sucursal),
   CONSTRAINT fk_venta_cliente    FOREIGN KEY (id_cliente)
                                  REFERENCES cliente (id_cliente),
   CONSTRAINT fk_venta_empleado   FOREIGN KEY (id_empleado)
                                  REFERENCES empleado (id_empleado),
   CONSTRAINT ck_venta_estado     CHECK (estado IN ('PENDIENTE','COMPLETADA','ANULADA')),
   CONSTRAINT ck_venta_total      CHECK (total >= 0)
);

CREATE TABLE detalle_venta (
   id_detalle       NUMBER        GENERATED ALWAYS AS IDENTITY,
   id_venta         NUMBER        NOT NULL,
   id_producto      NUMBER        NOT NULL,
   cantidad         NUMBER(10)    NOT NULL,
   precio_unitario  NUMBER(10,2)  NOT NULL,
   subtotal         NUMBER(12,2)  GENERATED ALWAYS AS (cantidad * precio_unitario) VIRTUAL,
   CONSTRAINT pk_detalle_venta      PRIMARY KEY (id_detalle),
   CONSTRAINT fk_detalle_venta      FOREIGN KEY (id_venta)
                                    REFERENCES encabezado_venta (id_venta),
   CONSTRAINT fk_detalle_producto   FOREIGN KEY (id_producto)
                                    REFERENCES producto (id_producto),
   CONSTRAINT uq_detalle_producto   UNIQUE (id_venta, id_producto),
   CONSTRAINT ck_detalle_cantidad   CHECK (cantidad > 0),
   CONSTRAINT ck_detalle_precio     CHECK (precio_unitario >= 0)
);

CREATE INDEX idx_empleado_sucursal  ON empleado (id_sucursal);
CREATE INDEX idx_producto_categoria ON producto (id_categoria);
CREATE INDEX idx_inventario_prod    ON inventario (id_producto);
CREATE INDEX idx_mov_inv            ON movimiento_inventario (id_sucursal, id_producto);
CREATE INDEX idx_mov_fecha          ON movimiento_inventario (fecha);
CREATE INDEX idx_venta_sucursal     ON encabezado_venta (id_sucursal);
CREATE INDEX idx_venta_cliente      ON encabezado_venta (id_cliente);
CREATE INDEX idx_venta_empleado     ON encabezado_venta (id_empleado);
CREATE INDEX idx_venta_fecha        ON encabezado_venta (fecha_venta);
CREATE INDEX idx_detalle_producto   ON detalle_venta (id_producto);

COMMENT ON TABLE sucursal              IS 'Sedes de Ferreterías EPA';
COMMENT ON TABLE empleado              IS 'Personal de cada sucursal (cajeros, supervisores, etc.)';
COMMENT ON TABLE categoria             IS 'Categorías del catálogo (herramientas, pintura, etc.)';
COMMENT ON TABLE producto              IS 'Catálogo único de artículos con precio sugerido';
COMMENT ON TABLE inventario            IS 'Stock físico por sucursal y producto';
COMMENT ON TABLE movimiento_inventario IS 'Kardex: historial de entradas y salidas de inventario';
COMMENT ON TABLE cliente               IS 'Información centralizada de clientes (sin duplicar en facturas)';
COMMENT ON TABLE encabezado_venta      IS 'Encabezado de factura';
COMMENT ON TABLE detalle_venta         IS 'Líneas de factura con precio congelado al momento de la venta';

COMMENT ON COLUMN inventario.stock              IS 'Existencia actual; CHECK impide valores negativos';
COMMENT ON COLUMN detalle_venta.precio_unitario IS 'Precio congelado al momento de la venta';
COMMENT ON COLUMN detalle_venta.subtotal        IS 'Columna virtual = cantidad * precio_unitario';
COMMENT ON COLUMN encabezado_venta.estado       IS 'PENDIENTE, COMPLETADA o ANULADA';

SELECT table_name FROM user_tables ORDER BY table_name;

COLUMN table_name      FORMAT A22
COLUMN constraint_name FORMAT A25
SELECT table_name, constraint_type, constraint_name
  FROM user_constraints
 WHERE constraint_name NOT LIKE 'SYS_%'
 ORDER BY table_name, constraint_type, constraint_name;

SELECT table_name, column_name, generation_type
  FROM user_tab_identity_cols
 ORDER BY table_name;
