SET SERVEROUTPUT ON

WHENEVER SQLERROR EXIT

DECLARE
   v_con  VARCHAR2(30) := SYS_CONTEXT('USERENV','CON_NAME');
   v_cnt  NUMBER;
BEGIN
   DBMS_OUTPUT.PUT_LINE('Conectado al contenedor: ' || v_con);
   IF v_con = 'CDB$ROOT' THEN
      RAISE_APPLICATION_ERROR(-20000,
         'Estás en CDB$ROOT. Conéctate al Service Name XEPDB1 y vuelve a ejecutar.');
   END IF;

   SELECT COUNT(*) INTO v_cnt FROM dba_users WHERE username = 'EPA';
   IF v_cnt > 0 THEN
      RAISE_APPLICATION_ERROR(-20001,
         'Ya existe un usuario EPA. No se modificó nada. ' ||
         'Si es del proyecto y quieres recrearlo, ejecuta manualmente: DROP USER epa CASCADE;');
   END IF;
   DBMS_OUTPUT.PUT_LINE('OK: se creará el usuario EPA.');
END;
/

WHENEVER SQLERROR CONTINUE

CREATE USER epa IDENTIFIED BY Epa2026
   DEFAULT TABLESPACE users
   TEMPORARY TABLESPACE temp
   QUOTA UNLIMITED ON users;

GRANT CREATE SESSION            TO epa;
GRANT CREATE TABLE              TO epa;
GRANT CREATE VIEW               TO epa;
GRANT CREATE MATERIALIZED VIEW  TO epa;
GRANT CREATE PROCEDURE          TO epa;
GRANT CREATE TRIGGER            TO epa;
GRANT CREATE SEQUENCE           TO epa;
GRANT CREATE JOB                TO epa;

SELECT username, default_tablespace, account_status, created
  FROM dba_users
 WHERE username = 'EPA';

SELECT privilege
  FROM dba_sys_privs
 WHERE grantee = 'EPA'
 ORDER BY privilege;
