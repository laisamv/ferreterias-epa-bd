SET SERVEROUTPUT ON
WHENEVER SQLERROR EXIT ROLLBACK

DECLARE
   v_cnt NUMBER;
BEGIN
   SELECT COUNT(*) INTO v_cnt FROM sucursal;
   IF v_cnt > 0 THEN
      RAISE_APPLICATION_ERROR(-20100,
         'Ya hay datos cargados. Para repetir la carga ejecuta 01_ddl.sql, ' ||
         '02_triggers.sql y luego 03_carga.sql.');
   END IF;
   DBMS_RANDOM.SEED(2026);
   DBMS_OUTPUT.PUT_LINE('Tablas vacías: iniciando carga...');
END;
/

INSERT INTO sucursal (nombre, direccion, municipio, departamento, telefono, fecha_apertura)
VALUES ('Plaza Madero', '2a. Avenida 15-20, Zona 10', 'Guatemala', 'Guatemala', '23856001', DATE '2012-03-15');
INSERT INTO sucursal (nombre, direccion, municipio, departamento, telefono, fecha_apertura)
VALUES ('Roosevelt', 'Calzada Roosevelt 22-43, Zona 11', 'Guatemala', 'Guatemala', '23856002', DATE '2010-08-01');
INSERT INTO sucursal (nombre, direccion, municipio, departamento, telefono, fecha_apertura)
VALUES ('Carretera a El Salvador', 'Km 14.5 Carretera a El Salvador', 'Santa Catarina Pinula', 'Guatemala', '23856003', DATE '2014-05-20');
INSERT INTO sucursal (nombre, direccion, municipio, departamento, telefono, fecha_apertura)
VALUES ('Zona 18 Atlántida', 'Calle Principal Atlántida 5-10, Zona 18', 'Guatemala', 'Guatemala', '23856004', DATE '2016-02-10');
INSERT INTO sucursal (nombre, direccion, municipio, departamento, telefono, fecha_apertura)
VALUES ('Villa Nueva', 'Km 17 Carretera al Pacífico', 'Villa Nueva', 'Guatemala', '23856005', DATE '2015-11-05');
INSERT INTO sucursal (nombre, direccion, municipio, departamento, telefono, fecha_apertura)
VALUES ('San Cristóbal', 'Boulevard San Cristóbal 8-50, Zona 8', 'Mixco', 'Guatemala', '23856006', DATE '2017-07-18');
INSERT INTO sucursal (nombre, direccion, municipio, departamento, telefono, fecha_apertura)
VALUES ('Antigua Guatemala', 'Calle de Santa Lucía Sur 12', 'Antigua Guatemala', 'Sacatepéquez', '78326007', DATE '2019-04-22');
INSERT INTO sucursal (nombre, direccion, municipio, departamento, telefono, fecha_apertura)
VALUES ('Quetzaltenango', '4a. Calle 18-30, Zona 3', 'Quetzaltenango', 'Quetzaltenango', '77656008', DATE '2018-09-30');

DECLARE
   TYPE t_txt IS TABLE OF VARCHAR2(40);
   v_nom    t_txt := t_txt('José','María','Carlos','Ana','Luis','Sofía','Juan','Gabriela',
                           'Pedro','Lucía','Miguel','Andrea','Jorge','Daniela','Fernando',
                           'Paola','Ricardo','Valeria','Diego','Karla');
   v_ape    t_txt := t_txt('López','García','Pérez','Hernández','Morales','Castillo','Ramírez',
                           'Méndez','Ortiz','Juárez','Rodas','Barrios','Cifuentes','Monterroso',
                           'Estrada','Gómez','Reyes','Coronado','Solares','Alvarado');
   v_puestos t_txt := t_txt('GERENTE','SUPERVISOR','CAJERO','CAJERO','CAJERO','BODEGUERO');
   n NUMBER := 0;
BEGIN
   FOR s IN (SELECT id_sucursal FROM sucursal ORDER BY id_sucursal) LOOP
      FOR k IN 1 .. v_puestos.COUNT LOOP
         n := n + 1;
         INSERT INTO empleado (id_sucursal, dpi, nombres, apellidos, puesto, telefono, fecha_contratacion)
         VALUES (s.id_sucursal,
                 TO_CHAR(1800000000000 + n * 104729),
                 v_nom(MOD(n * 7, 20) + 1),
                 v_ape(MOD(n * 3, 20) + 1) || ' ' || v_ape(MOD(n * 11 + 5, 20) + 1),
                 v_puestos(k),
                 TO_CHAR(TRUNC(DBMS_RANDOM.VALUE(30000000, 59999999))),
                 TRUNC(SYSDATE - DBMS_RANDOM.VALUE(200, 2500)));
      END LOOP;
   END LOOP;
   DBMS_OUTPUT.PUT_LINE('Empleados: ' || n);
END;
/

DECLARE
   v_cat   NUMBER;
   v_pref  VARCHAR2(3);
   v_n     PLS_INTEGER;
   v_total PLS_INTEGER := 0;

   PROCEDURE cat (p_nombre VARCHAR2, p_desc VARCHAR2, p_pref VARCHAR2) IS
   BEGIN
      INSERT INTO categoria (nombre, descripcion) VALUES (p_nombre, p_desc)
      RETURNING id_categoria INTO v_cat;
      v_pref := p_pref;
      v_n    := 0;
   END;

   PROCEDURE p (p_nom VARCHAR2, p_precio NUMBER, p_uni VARCHAR2 DEFAULT 'UNIDAD') IS
   BEGIN
      v_n     := v_n + 1;
      v_total := v_total + 1;
      INSERT INTO producto (codigo, nombre, id_categoria, unidad_medida, precio_sugerido, fecha_creacion)
      VALUES (v_pref || '-' || LPAD(v_n, 3, '0'), p_nom, v_cat, p_uni, p_precio,
              TRUNC(SYSDATE) - 400 + v_total);
   END;
BEGIN
   cat('Herramientas manuales', 'Herramientas de uso manual', 'HMA');
   p('Martillo de uña 16 oz', 85);             p('Martillo de bola 24 oz', 110);
   p('Mazo de hule 16 oz', 65);                p('Desarmador plano 1/4" x 6"', 28);
   p('Desarmador phillips #2 x 6"', 28);       p('Juego de desarmadores 6 piezas', 145);
   p('Alicate universal 8"', 95);              p('Alicate de punta 6"', 85);
   p('Alicate de presión 10"', 120);           p('Llave cangrejo 10"', 115);
   p('Juego de llaves combinadas 12 piezas', 385); p('Juego de llaves hexagonales 9 piezas', 75);
   p('Sierra de arco 12"', 98);                p('Serrucho 22"', 135);
   p('Cinta métrica 5 m', 55);                 p('Cinta métrica 8 m', 85);
   p('Nivel de aluminio 24"', 120);            p('Escuadra de acero 12"', 70);
   p('Cuchilla retráctil 18 mm', 25);          p('Llave stillson 14"', 175);

   cat('Herramientas eléctricas', 'Herramientas eléctricas y accesorios', 'HEL');
   p('Taladro percutor 1/2" 650 W', 595);      p('Taladro inalámbrico 20 V', 1150);
   p('Rotomartillo SDS Plus 800 W', 1450);     p('Esmeriladora angular 4-1/2" 750 W', 525);
   p('Sierra circular 7-1/4" 1400 W', 975);    p('Caladora 500 W', 485);
   p('Lijadora orbital 1/4 de hoja', 395);     p('Pulidora 7" 1800 W', 1250);
   p('Atornillador inalámbrico 12 V', 780);    p('Cepillo eléctrico 3-1/4"', 865);
   p('Rebajadora 1/4" 710 W', 925);            p('Soldadora inversora 130 A', 1650);
   p('Pistola de calor 1500 W', 265);          p('Compresor de aire 25 L', 1950);
   p('Hidrolavadora 1600 PSI', 1350);          p('Disco de corte para metal 4-1/2"', 12);
   p('Disco de diamante 4-1/2"', 75);          p('Juego de brocas para metal 13 piezas', 165);
   p('Juego de brocas para concreto 5 piezas', 85); p('Batería 20 V 2.0 Ah', 495);

   cat('Construcción', 'Materiales de construcción y obra gris', 'CON');
   p('Cemento gris 42.5 kg', 82, 'BOLSA');     p('Cemento blanco 20 kg', 95, 'BOLSA');
   p('Cal hidratada 25 kg', 45, 'BOLSA');      p('Block de concreto 15x20x40', 6.5);
   p('Hierro corrugado 3/8" x 6 m', 42);       p('Hierro corrugado 1/2" x 6 m', 72);
   p('Alambre de amarre', 9, 'LIBRA');         p('Clavo de 3"', 8.5, 'LIBRA');
   p('Arena de río 40 kg', 18, 'BOLSA');       p('Piedrín 1/2" 40 kg', 22, 'BOLSA');
   p('Lámina galvanizada cal. 26 x 10 pies', 125); p('Malla de gallinero 1 m x 25 m', 325, 'ROLLO');
   p('Adhesivo para cerámica 20 kg', 68, 'BOLSA'); p('Piso cerámico 33x33', 115, 'CAJA');
   p('Azulejo 20x30', 105, 'CAJA');            p('Impermeabilizante acrílico', 235, 'GALON');
   p('Carretilla de construcción 5 pies³', 525); p('Pala cuadrada', 95);
   p('Piocha con cabo', 125);                  p('Cubeta para mezcla 19 L', 35);

   cat('Pintura', 'Pinturas, solventes y accesorios', 'PIN');
   p('Pintura látex interior blanco', 145, 'GALON'); p('Pintura látex interior blanco cubeta 5 gal', 650);
   p('Pintura látex exterior', 195, 'GALON');  p('Pintura de aceite esmalte negro', 225, 'GALON');
   p('Pintura anticorrosiva gris', 210, 'GALON'); p('Pintura en aerosol negro mate', 38);
   p('Pintura en aerosol blanco brillante', 38); p('Sellador para paredes', 135, 'GALON');
   p('Barniz marino transparente', 265, 'GALON'); p('Thinner corriente', 85, 'GALON');
   p('Aguarrás', 35, 'LITRO');                 p('Brocha 2"', 18);
   p('Brocha 4"', 32);                         p('Rodillo de felpa 9"', 45);
   p('Bandeja para rodillo', 30);              p('Extensión para rodillo 1.5 m', 55);
   p('Masilla para resanar 1/4 galón', 48);    p('Lija de agua #120', 5);
   p('Cinta de enmascarar 1"', 18, 'ROLLO');   p('Espátula de 3"', 22);

   cat('Electricidad', 'Material eléctrico', 'ELE');
   p('Cable THHN calibre 12', 7.5, 'METRO');   p('Cable THHN calibre 14', 5.5, 'METRO');
   p('Cable THHN calibre 10', 11, 'METRO');    p('Cable dúplex calibre 16', 4.5, 'METRO');
   p('Tomacorriente doble polarizado', 22);    p('Interruptor sencillo', 18);
   p('Interruptor doble', 28);                 p('Caja rectangular metálica', 7.5);
   p('Tubo conduit PVC 1/2" x 3 m', 14);       p('Breaker 1 polo 20 A', 65);
   p('Breaker 2 polos 30 A', 145);             p('Centro de carga 4 espacios', 245);
   p('Cinta de aislar negra', 9, 'ROLLO');     p('Extensión eléctrica 5 m', 65);
   p('Regleta 6 tomas con protector', 115);    p('Timbre inalámbrico', 135);
   p('Varilla de tierra 5/8" x 8 pies', 95);   p('Multímetro digital', 185);
   p('Probador de voltaje', 55);               p('Conector de presión (25 u.)', 35, 'PAQUETE');

   cat('Plomería', 'Tubería, accesorios y artículos sanitarios', 'PLO');
   p('Tubo PVC 1/2" x 6 m', 30);               p('Tubo PVC 3/4" x 6 m', 42);
   p('Tubo PVC drenaje 4" x 6 m', 185);        p('Codo PVC 1/2" x 90°', 2.5);
   p('Tee PVC 1/2"', 3);                       p('Pegamento PVC 1/4 galón', 65);
   p('Cinta teflón', 4, 'ROLLO');              p('Llave de paso 1/2"', 45);
   p('Llave de chorro 1/2"', 55);              p('Grifo para lavamanos', 285);
   p('Mezcladora para cocina', 495);           p('Inodoro completo blanco', 895);
   p('Lavamanos de pedestal', 625);            p('Ducha eléctrica 4 temperaturas', 225);
   p('Tanque de agua 1100 L', 1450);           p('Flotador para tanque', 85);
   p('Sifón para lavatrastos', 45);            p('Manguera flexible para inodoro 16"', 28);
   p('Bomba de agua 1/2 HP', 1250);            p('Destapador de hule', 35);

   cat('Tornillería y fijación', 'Tornillos, clavos, cerraduras y adhesivos', 'TOR');
   p('Tornillo para madera 1-1/2" (100 u.)', 35, 'CAJA'); p('Tornillo para tablayeso 1" (100 u.)', 28, 'CAJA');
   p('Tornillo punta broca 1/2" (100 u.)', 32, 'CAJA');   p('Perno hexagonal 3/8" x 2"', 4.5);
   p('Tuerca hexagonal 3/8"', 1.25);           p('Arandela plana 3/8"', 0.75);
   p('Tarugo plástico 1/4" (100 u.)', 22, 'BOLSA'); p('Ancla expansiva 3/8"', 6.5);
   p('Clavo de acero para concreto 2"', 45, 'CAJA'); p('Clavo para lámina 2-1/2"', 12, 'LIBRA');
   p('Grapa para cerca', 11, 'LIBRA');         p('Remache pop 1/8" (100 u.)', 38, 'CAJA');
   p('Bisagra de 3"', 12);                     p('Candado de latón 40 mm', 85);
   p('Cerradura de pomo para puerta', 165);    p('Cerradura de seguridad doble cilindro', 345);
   p('Cadena galvanizada 1/4"', 22, 'METRO');  p('Pasador de 4"', 18);
   p('Silicón transparente 280 ml', 38);       p('Pegamento epóxico 2 componentes', 45);

   cat('Jardinería', 'Herramientas y artículos de jardín', 'JAR');
   p('Manguera para jardín 1/2" x 15 m', 165); p('Manguera para jardín 1/2" x 30 m', 295);
   p('Pistola de riego 8 funciones', 65);      p('Aspersor giratorio', 75);
   p('Tijera de podar', 115);                  p('Machete 22"', 65);
   p('Rastrillo metálico 14 dientes', 85);     p('Azadón con cabo', 110);
   p('Carretilla de jardín 3 pies³', 395);     p('Regadera plástica 10 L', 55);
   p('Maceta plástica 12"', 35);               p('Tierra negra abonada 25 lb', 30, 'BOLSA');
   p('Fertilizante 15-15-15 5 lb', 45, 'BOLSA'); p('Semilla de grama 1 lb', 65, 'BOLSA');
   p('Podadora de césped a gasolina', 2950);   p('Desbrozadora a gasolina', 2250);
   p('Guantes de jardinería', 30);             p('Insecticida', 75, 'LITRO');
   p('Malla sombra 50%', 18, 'METRO');         p('Tijera para setos', 145);

   cat('Seguridad industrial', 'Equipo de protección personal', 'SEG');
   p('Casco de seguridad', 55);                p('Lentes de seguridad transparentes', 25);
   p('Guantes de cuero', 45);                  p('Guantes de nitrilo (100 u.)', 95, 'CAJA');
   p('Mascarilla N95 (20 u.)', 125, 'CAJA');   p('Respirador media cara', 185);
   p('Protector auditivo tipo copa', 85);      p('Tapones auditivos (10 pares)', 55, 'PAQUETE');
   p('Chaleco reflectivo', 45);                p('Botas de hule', 125);
   p('Botas de seguridad punta de acero', 395); p('Arnés de cuerpo completo', 485);
   p('Línea de vida con amortiguador', 425);   p('Extintor PQS 10 lb', 375);
   p('Botiquín de primeros auxilios', 165);    p('Cono de seguridad 28"', 85);
   p('Cinta de precaución 300 m', 75, 'ROLLO'); p('Careta para soldar', 145);
   p('Overol de trabajo', 195);                p('Rodilleras', 65);

   cat('Iluminación', 'Lámparas, focos y accesorios', 'ILU');
   p('Bombilla LED 9 W', 18);                  p('Bombilla LED 12 W', 25);
   p('Bombilla LED 18 W', 38);                 p('Tubo LED T8 18 W', 45);
   p('Panel LED 60x60 48 W', 185);             p('Reflector LED 50 W', 165);
   p('Reflector LED 100 W', 295);              p('Lámpara solar con sensor', 175);
   p('Plafón LED 24 W', 125);                  p('Ojo de buey LED 12 W', 55);
   p('Lámpara de emergencia recargable', 145); p('Linterna recargable', 85);
   p('Lámpara frontal', 65);                   p('Tira LED 5 m', 125, 'ROLLO');
   p('Socket de porcelana', 12);               p('Sensor de movimiento', 110);
   p('Fotocelda', 75);                         p('Lámpara colgante industrial', 225);
   p('Lámpara de escritorio LED', 145);        p('Farol para exterior', 195);

   DBMS_OUTPUT.PUT_LINE('Productos: ' || v_total);
END;
/

DECLARE
   TYPE t_txt IS TABLE OF VARCHAR2(60);
   v_nom  t_txt := t_txt('José','María','Carlos','Ana','Luis','Sofía','Juan','Gabriela',
                         'Pedro','Lucía','Miguel','Andrea','Jorge','Daniela','Fernando',
                         'Paola','Ricardo','Valeria','Diego','Karla');
   v_ape  t_txt := t_txt('López','García','Pérez','Hernández','Morales','Castillo','Ramírez',
                         'Méndez','Ortiz','Juárez','Rodas','Barrios','Cifuentes','Monterroso',
                         'Estrada','Gómez','Reyes','Coronado','Solares','Alvarado');
   v_emp  t_txt := t_txt('Constructora Los Altos, S.A.','Inversiones Pinula, S.A.',
                         'Remodelaciones Express','Obras Civiles del Sur, S.A.',
                         'Ferretería El Tornillo','Inmobiliaria Cayalá, S.A.',
                         'Servicios Eléctricos Integrales','Pinturas y Acabados Rivera',
                         'Desarrollos Habitacionales Mixco','Plomería Profesional GT',
                         'Grupo Constructor Atitlán','Mantenimiento Industrial MAINSA',
                         'Arquitectura y Diseño Volcán','Condominio Vista Hermosa',
                         'Colegio San Martín','Hotel Casa Antigua',
                         'Taller Mecánico Hermanos Pérez','Carpintería Fina El Roble',
                         'Jardines y Paisajes, S.A.','Municipalidad de Santa Lucía');
   v_mun  t_txt := t_txt('Guatemala','Mixco','Villa Nueva','San Miguel Petapa',
                         'Santa Catarina Pinula','Antigua Guatemala','Quetzaltenango','Escuintla');
   v_nombre VARCHAR2(150);
   v_mail   VARCHAR2(100);
   v_dir    VARCHAR2(200);
BEGIN
   INSERT INTO cliente (nit, nombre, direccion, fecha_registro)
   VALUES ('CF', 'Consumidor Final', 'Ciudad', DATE '2010-01-01');

   FOR i IN 1 .. 79 LOOP
      v_nombre := v_nom(MOD(i * 7, 20) + 1) || ' ' ||
                  v_ape(MOD(i * 3, 20) + 1) || ' ' ||
                  v_ape(MOD(i * 11 + 5, 20) + 1);
      v_mail   := LOWER(TRANSLATE(v_nom(MOD(i * 7, 20) + 1) || '.' || v_ape(MOD(i * 3, 20) + 1),
                                  'áéíóúÁÉÍÓÚñÑ', 'aeiouAEIOUnN')) || i || '@correo.com';
      v_dir    := (MOD(i, 15) + 1) || 'a. Calle ' || (MOD(i * 7, 30) + 1) || '-' ||
                  LPAD(MOD(i * 13, 99) + 1, 2, '0') || ', ' || v_mun(MOD(i, 8) + 1);

      INSERT INTO cliente (nit, dpi, nombre, direccion, telefono, email, fecha_registro)
      VALUES (TO_CHAR(1000000 + i * 9973) ||
                 CASE WHEN MOD(i, 11) = 0 THEN 'K' ELSE TO_CHAR(MOD(i * 7, 10)) END,
              TO_CHAR(2900000000000 + i * 7919),
              v_nombre, v_dir,
              TO_CHAR(TRUNC(DBMS_RANDOM.VALUE(30000000, 59999999))),
              v_mail,
              TRUNC(SYSDATE - DBMS_RANDOM.VALUE(200, 1500)));
   END LOOP;

   FOR i IN 1 .. v_emp.COUNT LOOP
      INSERT INTO cliente (nit, nombre, direccion, telefono, email, fecha_registro)
      VALUES (TO_CHAR(5000000 + i * 7717) || TO_CHAR(MOD(i * 3, 10)),
              v_emp(i),
              'Km ' || (10 + i) || ' Ruta Nacional, ' || v_mun(MOD(i, 8) + 1),
              '2' || TO_CHAR(TRUNC(DBMS_RANDOM.VALUE(2000000, 4999999))),
              'compras' || i || '@empresa.com.gt',
              TRUNC(SYSDATE - DBMS_RANDOM.VALUE(200, 1500)));
   END LOOP;

   DBMS_OUTPUT.PUT_LINE('Clientes: 100');
END;
/

INSERT INTO inventario (id_sucursal, id_producto, stock, stock_minimo)
SELECT s.id_sucursal,
       p.id_producto,
       TRUNC(DBMS_RANDOM.VALUE(40, 251)),
       TRUNC(DBMS_RANDOM.VALUE(5, 16))
  FROM sucursal s
 CROSS JOIN producto p;

DECLARE
   TYPE t_num IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
   TYPE t_set IS TABLE OF BOOLEAN INDEX BY PLS_INTEGER;
   v_suc       t_num;
   v_cli       t_num;
   v_vend      t_num;
   v_usados    t_set;
   v_cf        NUMBER;
   v_id_venta  NUMBER;
   v_s         NUMBER;
   v_emp       NUMBER;
   v_c         NUMBER;
   v_p         NUMBER;
   v_cant      NUMBER;
   v_lineas    PLS_INTEGER;
   v_ok        PLS_INTEGER;
   v_fecha     DATE;
   v_ventas    PLS_INTEGER := 0;
   v_det       PLS_INTEGER := 0;
BEGIN
   SELECT id_sucursal BULK COLLECT INTO v_suc FROM sucursal ORDER BY id_sucursal;
   SELECT id_cliente  BULK COLLECT INTO v_cli FROM cliente WHERE nit <> 'CF' ORDER BY id_cliente;
   SELECT id_cliente  INTO v_cf FROM cliente WHERE nit = 'CF';

   SELECT id_producto BULK COLLECT INTO v_vend
     FROM (SELECT id_producto, ROW_NUMBER() OVER (ORDER BY id_producto) rn FROM producto)
    WHERE MOD(rn, 13) <> 0
    ORDER BY DBMS_RANDOM.VALUE;

   pkg_contexto.g_tipo        := 'SALIDA';
   pkg_contexto.g_observacion := 'Venta histórica (carga inicial)';

   FOR i IN 1 .. 450 LOOP
      SAVEPOINT sp_venta;
      v_usados.DELETE;

      v_s := v_suc(TRUNC(POWER(DBMS_RANDOM.VALUE, 1.5) * v_suc.COUNT) + 1);

      SELECT id_empleado INTO v_emp
        FROM (SELECT id_empleado FROM empleado
               WHERE id_sucursal = v_s AND puesto = 'CAJERO' AND activo = 'S'
               ORDER BY DBMS_RANDOM.VALUE)
       WHERE ROWNUM = 1;

      IF DBMS_RANDOM.VALUE < 0.35 THEN
         v_c := v_cf;
      ELSE
         v_c := v_cli(TRUNC(DBMS_RANDOM.VALUE(1, v_cli.COUNT + 1)));
      END IF;

      v_fecha := TRUNC(SYSDATE) - TRUNC(DBMS_RANDOM.VALUE(1, 181))
                 + (8 + DBMS_RANDOM.VALUE(0, 11)) / 24;

      INSERT INTO encabezado_venta (id_sucursal, id_cliente, id_empleado, fecha_venta)
      VALUES (v_s, v_c, v_emp, v_fecha)
      RETURNING id_venta INTO v_id_venta;

      pkg_contexto.g_id_venta := v_id_venta;

      v_lineas := TRUNC(DBMS_RANDOM.VALUE(1, 6));
      v_ok     := 0;

      FOR l IN 1 .. v_lineas LOOP
         v_p := v_vend(TRUNC(POWER(DBMS_RANDOM.VALUE, 1.8) * v_vend.COUNT) + 1);
         CONTINUE WHEN v_usados.EXISTS(v_p);
         v_usados(v_p) := TRUE;

         v_cant := TRUNC(DBMS_RANDOM.VALUE(1, 7));

         UPDATE inventario
            SET stock = stock - v_cant
          WHERE id_sucursal = v_s
            AND id_producto = v_p
            AND stock >= v_cant;

         IF SQL%ROWCOUNT = 1 THEN
            INSERT INTO detalle_venta (id_venta, id_producto, cantidad)
            VALUES (v_id_venta, v_p, v_cant);
            v_ok  := v_ok + 1;
            v_det := v_det + 1;
         END IF;
      END LOOP;

      IF v_ok = 0 THEN
         ROLLBACK TO SAVEPOINT sp_venta;
      ELSE
         UPDATE encabezado_venta SET estado = 'COMPLETADA' WHERE id_venta = v_id_venta;
         v_ventas := v_ventas + 1;
      END IF;
   END LOOP;

   pkg_contexto.limpiar;

   UPDATE movimiento_inventario m
      SET fecha = (SELECT e.fecha_venta FROM encabezado_venta e WHERE e.id_venta = m.id_venta)
    WHERE m.id_venta IS NOT NULL;

   DBMS_OUTPUT.PUT_LINE('Ventas: ' || v_ventas || '   Líneas de detalle: ' || v_det);
END;
/

COMMIT;

WHENEVER SQLERROR CONTINUE

EXEC sp_cierre_diario

SELECT 'SUCURSAL'              AS tabla, COUNT(*) AS registros FROM sucursal              UNION ALL
SELECT 'EMPLEADO',                       COUNT(*)              FROM empleado              UNION ALL
SELECT 'CATEGORIA',                      COUNT(*)              FROM categoria             UNION ALL
SELECT 'PRODUCTO',                       COUNT(*)              FROM producto              UNION ALL
SELECT 'CLIENTE',                        COUNT(*)              FROM cliente               UNION ALL
SELECT 'INVENTARIO',                     COUNT(*)              FROM inventario            UNION ALL
SELECT 'ENCABEZADO_VENTA',               COUNT(*)              FROM encabezado_venta      UNION ALL
SELECT 'DETALLE_VENTA',                  COUNT(*)              FROM detalle_venta         UNION ALL
SELECT 'MOVIMIENTO_INVENTARIO',          COUNT(*)              FROM movimiento_inventario UNION ALL
SELECT 'INVENTARIO_CIERRE_DIARIO',       COUNT(*)              FROM inventario_cierre_diario;

SELECT COUNT(*) AS facturas_descuadradas
  FROM encabezado_venta e
 WHERE e.total <> (SELECT NVL(SUM(d.subtotal), 0) FROM detalle_venta d WHERE d.id_venta = e.id_venta);

SELECT COUNT(*) AS lineas_sin_kardex
  FROM detalle_venta d
  JOIN encabezado_venta e ON e.id_venta = d.id_venta
 WHERE NOT EXISTS (SELECT 1 FROM movimiento_inventario m
                    WHERE m.id_venta = d.id_venta
                      AND m.id_producto = d.id_producto
                      AND m.id_sucursal = e.id_sucursal);

SELECT COUNT(*) AS stock_negativo FROM inventario WHERE stock < 0;

COLUMN sucursal FORMAT A25
SELECT s.nombre AS sucursal, COUNT(e.id_venta) AS facturas, SUM(e.total) AS total_q
  FROM sucursal s
  LEFT JOIN encabezado_venta e ON e.id_sucursal = s.id_sucursal
 GROUP BY s.nombre
 ORDER BY total_q DESC;
