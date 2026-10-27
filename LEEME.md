# Proyecto Final – Bases de Datos I
## Reingeniería de la Base de Datos – Ferreterías EPA (Oracle 21c XE)

Todo el proyecto se crea dentro de un usuario nuevo llamado `EPA`.
No modifica ninguna otra base de datos ni usuario que ya exista.

---

## 1. Requisitos

| Programa | Notas |
|---|---|
| Oracle Database 21c **XE** (Windows) | Al instalarlo pide una contraseña: es la del usuario `SYSTEM`. |
| Oracle SQL Developer | Para ejecutar los scripts con F5. |
| SQL*Plus | Viene con Oracle XE. Se usa desde CMD en las pruebas de dos sesiones. |
| Python 3.12 o superior | Solo para el prototipo de aplicación (sección 6). |

---

## 2. Conexiones en SQL Developer

Clic en el **+ verde** del panel *Conexiones*.

**dba_XEPDB1** (solo para el script 00)

| Campo | Valor |
|---|---|
| Usuario | `system` |
| Contraseña | la de la instalación de Oracle |
| Rol | valor por defecto |
| Host / Puerto | `localhost` / `1521` |
| **Nombre del Servicio** (no SID) | `XEPDB1` |

**EPA_Proyecto** (para todo lo demás; se crea después del script 00)

| Campo | Valor |
|---|---|
| Usuario | `epa` |
| Contraseña | `Epa2026` |
| Rol | valor por defecto |
| Host / Puerto | `localhost` / `1521` |
| **Nombre del Servicio** (no SID) | `XEPDB1` |

> Si se usa SID `xe`, el script 00 se detiene con el mensaje *"Estás en CDB$ROOT"*.

---

## 3. Orden de ejecución

En SQL Developer: **Archivo → Abrir**, elegir el script, presionar **F5**
(Ejecutar script) y elegir la conexión indicada.

| # | Archivo | Conexión | Cómo | Contenido |
|---|---|---|---|---|
| 1 | `00_setup.sql` | dba_XEPDB1 | F5 | Usuario/esquema EPA y permisos |
| 2 | `01_ddl.sql` | EPA_Proyecto | F5 | 9 tablas con PK, FK, CHECK, UNIQUE e IDENTITY |
| 3 | `02_triggers.sql` | EPA_Proyecto | F5 | Triggers, auditoría, inventario general y job diario |
| 4 | `03_carga.sql` | EPA_Proyecto | F5 | 8 sucursales, 100 clientes, 200 productos, ~450 ventas |
| 5 | `04_sp_venta.sql` | EPA_Proyecto | F5 | Paquete de ventas (COMMIT/ROLLBACK + FOR UPDATE) |
| 6 | `05_concurrencia.sql` | 2 ventanas CMD | Guion | Prueba de concurrencia Sesión A vs Sesión B |
| 7 | `06_crash_test_auto.sql` | EPA_Proyecto | F5 | Venta de 50 artículos que falla en el 25 → ROLLBACK |
| 7b | `06_crash_test_manual.sql` | 2 ventanas CMD | Guion | (Opcional) crash test con caída real |
| 8 | `07_pruebas_integridad.sql` | EPA_Proyecto | F5 | Intentos de dañar la base, todos rechazados |
| 9 | `08_reportes.sql` | EPA_Proyecto | F5 | Reportes como vistas + resumen general |

---

## 4. Pruebas con dos ventanas (pasos 6 y 7b)

1. Abrir **dos ventanas de CMD** lado a lado.
2. En ambas: `sqlplus epa/Epa2026@localhost:1521/XEPDB1`
3. Abrir el guion en el Bloc de notas y copiar **bloque por bloque, en el
   orden de las tablas siguientes** (los bloques están en el archivo en ese mismo orden).

### `05_concurrencia.sql`

| # | Sesión | Bloque del archivo | Resultado esperado |
|---|---|---|---|
| 1 | A | Primer grupo de `SET` (prompt `SESION_A>`) | Configura la sesión A |
| 2 | B | Segundo grupo de `SET` (prompt `SESION_B>`) | Configura la sesión B |
| 3 | A | `BEGIN ... stock = 1 ... END; /` (RESET) | Stock del martillo = 1 |
| **Parte 1** | | | |
| 4 | A | `SELECT ... FOR UPDATE` | Muestra STOCK = 1 (no hacer COMMIT) |
| 5 | B | El mismo `SELECT ... FOR UPDATE` | **B se queda esperando** |
| 6 | A | (Opcional) `SELECT ... FROM v$session` | Muestra quién bloquea a quién |
| 7 | A | `UPDATE ... stock - 1` + `COMMIT` | B se libera y muestra STOCK = 0 |
| 8 | B | `ROLLBACK` | Libera la fila |
| **Parte 2** | | | Antes, repetir el RESET (paso 3) en A |
| 9 | A | `SELECT ... FOR UPDATE` | STOCK = 1 |
| 10 | B | `DECLARE ... pkg_ventas.vender_producto ... /` | **B se queda esperando** |
| 11 | A | `UPDATE ... stock - 1` + `COMMIT` | B: *VENTA RECHAZADA ORA-20001* |
| 12 | B | Los dos `SELECT` (stock y `log_venta_fallida`) | Stock 0 y el intento registrado |
| **Parte 3** | | | Antes, repetir el RESET (paso 3) en A |
| 13 | A | `SELECT` sin `FOR UPDATE` | STOCK = 1 |
| 14 | B | `SELECT` sin `FOR UPDATE` | También STOCK = 1 |
| 15 | A | `UPDATE ... stock - 1` + `COMMIT` | Stock 0 |
| 16 | B | `UPDATE ... stock - 1` + `ROLLBACK` | `ORA-02290` (CK_INVENTARIO_STOCK) |
| **Extra (opcional)** | | | |
| 17 | A | `SELECT ... FOR UPDATE` | Bloquea el martillo |
| 18 | B | `... FOR UPDATE NOWAIT` | `ORA-00054` inmediato |
| 19 | B | `... FOR UPDATE WAIT 5` | `ORA-30006` a los 5 segundos |
| 20 | A | `ROLLBACK` | Libera |
| **Final** | | | |
| 21 | A | `SELECT` del kardex y del stock negativo | Kardex sin negativos; conteo 0 |
| 22 | A | `ROLLBACK` + `DECLARE ... registrar_entrada ... /` | Repone 50 martillos |

### `06_crash_test_manual.sql` (opcional)

| # | Sesión | Bloque del archivo | Resultado esperado |
|---|---|---|---|
| 1 | A | Primer grupo de `SET` | Configura la sesión A |
| 2 | B | Segundo grupo de `SET` | Configura la sesión B |
| 3 | B | Primer `SELECT ... FROM dual` | Foto "antes" |
| 4 | A | `ROLLBACK` + `DECLARE ... /` | Factura con 24 de 50 artículos, sin COMMIT |
| 5 | A | Los dos `SELECT` siguientes | A ve la factura PENDIENTE y el stock descontado |
| 6 | B | `SELECT ... FROM dual` | B no ve nada de eso (igual que la foto "antes") |
| 7 | A | `ROLLBACK`, **o** cerrar la ventana A con la X (no `EXIT`) | Se cancela la venta |
| 8 | B | Último `SELECT ... FROM dual` | Igual a la foto "antes" |

Reglas de SQL*Plus:
- Los bloques que empiezan con `BEGIN` o `DECLARE` terminan con una **`/`**
  sola en una línea; sin ella no se ejecutan.
- Copiar el bloque **completo**, incluida la primera línea (`DECLARE`).
- En la concurrencia, **B ejecuta su consulta mientras A todavía no ha hecho
  COMMIT**. Si A ya confirmó, B no tiene que esperar.
- `EXIT` en SQL*Plus **hace COMMIT**. Para simular una caída se cierra la
  ventana con la **X**.

---

## 5. Diagrama Entidad-Relación

Se genera desde la base ya creada, en SQL Developer:

1. **Archivo → Data Modeler → Importar → Diccionario de Datos**.
2. Conexión `EPA_Proyecto` → marcar solo el esquema **EPA** → marcar las tablas → **Terminar**.
3. Se abre el modelo **relacional**.
4. Botón **`<<`** (Realizar ingeniería a modelo lógico) → **Realizar Ingeniería**.
5. En el modelo lógico: clic derecho → **Notación → Information Engineering** (pata de gallo).
6. Exportar: **Archivo → Data Modeler → Imprimir Diagrama → A Archivo de Imagen**.

---

## 6. Prototipo de aplicación (Python + Streamlit)

La carpeta `app` contiene `app.py` y `requirements.txt`. La aplicación se
conecta a Oracle con `oracledb` (no hace falta instalar Oracle Client) y usa
el paquete `PKG_VENTAS` y las vistas de reportes.

**Antes:** haber ejecutado los scripts 00 a 08 y tener Oracle XE encendido.

### 6.1 Instalar Python (solo la primera vez)

1. Descargar Python desde **python.org/downloads** e instalarlo
   (**Install Python**).
2. Si al terminar se abre una ventana negra de configuración:
   - *"Windows is not configured to allow paths longer than 260 characters"* → **N**
   - *"View online help?"* → **N**
   - *"Open Settings now, so you can modify App execution aliases?"* → **y**.
     En **Configuración → Alias de ejecución de aplicaciones**, activar
     **Python (default)** y **Python install manager**, y desactivar los
     de **Instalador de aplicación** (`python.exe` / `python3.exe`).
3. Abrir un **CMD nuevo** y comprobar:
   ```
   python --version
   ```
   Si responde `Python 3.x.x`, está listo. Si dice *"Python was not found"*,
   revisar el paso de los alias.

### 6.2 Instalar las librerías (solo la primera vez)

1. Descomprimir el ZIP (clic derecho → **Extraer todo**). Dentro del ZIP
   sin extraer no funciona.
2. En el Explorador de archivos, entrar a la carpeta **`app`**.
3. Clic en la **barra de dirección**, borrar la ruta, escribir **`cmd`** y
   presionar **Enter**. Se abre CMD ubicado en esa carpeta.
4. Ejecutar:
   ```
   python -m pip install -r requirements.txt
   ```

### 6.3 Abrir la aplicación

> `app.py` **no se abre con doble clic**; se ejecuta desde CMD.

1. Abrir CMD en la carpeta `app` (igual que en 6.2, pasos 2 y 3).
2. Ejecutar:
   ```
   python -m streamlit run app.py
   ```
3. La primera vez pide un **Email**: presionar **Enter** sin escribir nada.
4. Cuando aparezca `Local URL: http://localhost:8501`, se abre el
   navegador. Si no se abre solo, escribir **`localhost:8501`** en el navegador.
5. **No cerrar la ventana de CMD** mientras se usa la aplicación. Para
   detenerla: **Ctrl + C** en esa ventana.

### 6.4 Pantallas

| Pantalla | Contenido |
|---|---|
| Dashboard | Indicadores y gráficas de ventas por mes, sucursal, producto y categoría |
| Nueva venta | Registra una factura con `PKG_VENTAS.REGISTRAR_VENTA` |
| Facturas | Consulta de facturas y su detalle; anulación con devolución de stock |
| Inventario | Stock por sucursal, ingreso de mercadería y kardex |
| Reportes | Reportes con gráfica y descarga en CSV |

### 6.5 Demostración sugerida

1. **Venta exitosa:** *Nueva venta* → elegir productos → *Registrar venta*.
2. **Venta rechazada:** pedir más unidades que el stock → Oracle responde
   `ORA-20001: Stock insuficiente` y no queda factura (ROLLBACK).
3. **Anulación:** en *Facturas*, anular la venta del punto 1 y ver en el
   *Kardex* el movimiento `ANULACION`.
4. **Reportes:** *Sucursales* muestra la que más vende; *Baja rotación*
   muestra los productos que no se mueven.

---

## 7. Problemas frecuentes

| Problema | Solución |
|---|---|
| *"Estás en CDB$ROOT"* | Usar *Nombre del Servicio* `XEPDB1`, no SID `xe`. |
| *"Ya existe un usuario EPA"* | En `dba_XEPDB1`: `DROP USER epa CASCADE;` y volver al paso 1. |
| *"Ya hay datos cargados"* (03) | La carga se hace una vez. Para repetirla: 01 → 02 → 03. |
| Objeto **INVALID** | Volver a ejecutar el script que lo crea y revisar el primer error. |
| *"Hay cambios pendientes en esta sesión"* | Ejecutar `ROLLBACK;` y reintentar. |
| Ventana de CMD congelada | La otra sesión tiene un bloqueo: `COMMIT;` o `ROLLBACK;` en la otra. |
| *"Python was not found"* | Revisar los alias de ejecución (6.1, paso 2). |
| La app no conecta a Oracle | Verificar que Oracle XE esté encendido y que existan el usuario EPA y los scripts 00–08. |

**Borrar todo el proyecto:** en `dba_XEPDB1` ejecutar `DROP USER epa CASCADE;`
