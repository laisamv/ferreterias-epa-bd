import oracledb
import pandas as pd
import streamlit as st

DB_USER = "epa"
DB_PASSWORD = "Epa2026"
DB_DSN = "localhost:1521/XEPDB1"

st.set_page_config(page_title="Ferreterías EPA", page_icon="🛠️", layout="wide")

@st.cache_resource
def get_pool():
    return oracledb.create_pool(user=DB_USER, password=DB_PASSWORD, dsn=DB_DSN,
                                min=1, max=4, increment=1)

def query(sql, params=None):
    with get_pool().acquire() as con:
        with con.cursor() as cur:
            cur.execute(sql, params or {})
            cols = [d[0].lower() for d in cur.description]
            return pd.DataFrame(cur.fetchall(), columns=cols)

def mensaje_oracle(e):
    err = e.args[0]
    return getattr(err, "message", str(err))

def q(valor):
    try:
        return f"Q {float(valor):,.2f}"
    except (TypeError, ValueError):
        return "Q 0.00"

try:
    query("SELECT 1 FROM dual")
except Exception as e:
    st.error("No se pudo conectar a Oracle.")
    st.code(str(e))
    st.info("Revisa que Oracle XE esté encendido y que el usuario EPA exista "
            f"(usuario `{DB_USER}`, servicio `{DB_DSN}`).")
    st.stop()

st.sidebar.title("🛠️ Ferreterías EPA")
st.sidebar.caption("Prototipo – Proyecto Final Bases de Datos I")
pagina = st.sidebar.radio(
    "Menú",
    ["📊 Dashboard", "🧾 Nueva venta", "📋 Facturas", "📦 Inventario", "📈 Reportes"],
)
st.sidebar.divider()
st.sidebar.caption(f"Conectado a Oracle 21c XE\n\n`{DB_USER}@{DB_DSN}`")

if pagina == "📊 Dashboard":
    st.title("📊 Dashboard general")

    r = query("SELECT * FROM v_rep_resumen").iloc[0]
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Total vendido", q(r.total_ventas))
    c2.metric("Facturas completadas", f"{int(r.facturas):,}")
    c3.metric("Ticket promedio", q(r.ticket_promedio))
    c4.metric("Valor del inventario", q(r.valor_inventario))

    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Clientes", int(r.clientes))
    c2.metric("Productos activos", int(r.productos_activos))
    c3.metric("Productos sin ventas", int(r.productos_sin_ventas))
    c4.metric("Facturas anuladas", int(r.facturas_anuladas))

    st.divider()
    izq, der = st.columns(2)

    with izq:
        st.subheader("Ventas por mes")
        vm = query("SELECT mes, total_ventas FROM v_rep_ventas_mensuales ORDER BY mes")
        st.line_chart(vm.set_index("mes")["total_ventas"])

        st.subheader("Top 10 productos (unidades)")
        tp = query("""SELECT producto, unidades_vendidas FROM v_rep_top_productos
                      ORDER BY ranking, ingresos DESC FETCH FIRST 10 ROWS ONLY""")
        st.bar_chart(tp.set_index("producto")["unidades_vendidas"], horizontal=True)

    with der:
        st.subheader("Ventas por sucursal")
        rs = query("SELECT sucursal, total_ventas FROM v_rep_ranking_sucursales ORDER BY ranking")
        st.bar_chart(rs.set_index("sucursal")["total_ventas"])

        st.subheader("Ventas por categoría")
        vc = query("SELECT categoria, ingresos FROM v_rep_ventas_categoria ORDER BY ranking")
        st.bar_chart(vc.set_index("categoria")["ingresos"], horizontal=True)

elif pagina == "🧾 Nueva venta":
    st.title("🧾 Nueva venta")
    st.caption("La venta se registra con el procedimiento PKG_VENTAS.REGISTRAR_VENTA: "
               "una sola transacción con SELECT ... FOR UPDATE, COMMIT si todo sale bien "
               "y ROLLBACK si algo falla.")

    sucursales = query("SELECT id_sucursal, nombre FROM sucursal WHERE activo = 'S' ORDER BY nombre")
    c1, c2, c3 = st.columns(3)
    suc_nombre = c1.selectbox("Sucursal", sucursales["nombre"])
    id_suc = int(sucursales.loc[sucursales["nombre"] == suc_nombre, "id_sucursal"].iloc[0])

    cajeros = query("""SELECT id_empleado, nombres || ' ' || apellidos || ' (' || puesto || ')' AS nombre
                         FROM empleado
                        WHERE id_sucursal = :s AND activo = 'S'
                          AND puesto IN ('CAJERO', 'SUPERVISOR', 'GERENTE')
                        ORDER BY puesto, nombres""", {"s": id_suc})
    caj_nombre = c2.selectbox("Cajero", cajeros["nombre"], key=f"caj_{id_suc}")
    id_emp = int(cajeros.loc[cajeros["nombre"] == caj_nombre, "id_empleado"].iloc[0])

    clientes = query("""SELECT id_cliente, nit || ' - ' || nombre AS nombre FROM cliente
                         WHERE activo = 'S'
                         ORDER BY CASE WHEN nit = 'CF' THEN 0 ELSE 1 END, nombre""")
    cli_nombre = c3.selectbox("Cliente", clientes["nombre"])
    id_cli = int(clientes.loc[clientes["nombre"] == cli_nombre, "id_cliente"].iloc[0])

    productos = query("""SELECT p.id_producto, p.codigo || ' - ' || p.nombre AS producto,
                                p.precio_sugerido AS precio, i.stock
                           FROM producto p
                           JOIN inventario i ON i.id_producto = p.id_producto
                          WHERE i.id_sucursal = :s AND p.activo = 'S'
                          ORDER BY p.codigo""", {"s": id_suc})
    etiquetas = {
        f"{r.producto}  |  {q(r.precio)}  |  stock: {r.stock}": i
        for i, r in productos.iterrows()
    }
    elegidos = st.multiselect("Productos", list(etiquetas.keys()), key=f"prods_{id_suc}",
                              placeholder="Escribe para buscar un producto...")

    lineas = []
    for etiqueta in elegidos:
        r = productos.loc[etiquetas[etiqueta]]
        cant = st.number_input(f"Cantidad — {r.producto} (stock {r.stock})",
                               min_value=1, value=1, step=1, key=f"cant_{id_suc}_{r.id_producto}")
        lineas.append({"id_producto": int(r.id_producto), "producto": r.producto,
                       "cantidad": int(cant), "precio": float(r.precio),
                       "subtotal": int(cant) * float(r.precio)})

    if lineas:
        detalle = pd.DataFrame(lineas)
        st.dataframe(detalle[["producto", "cantidad", "precio", "subtotal"]], hide_index=True)
        st.markdown(f"### Total estimado: {q(detalle['subtotal'].sum())}")
        st.caption("Prueba: pide más unidades que el stock y verás cómo Oracle rechaza "
                   "la venta completa (ORA-20001) sin dejar factura a medias.")

    if st.button("💾 Registrar venta", type="primary", disabled=not lineas):
        plsql = """
            DECLARE
               v_p pkg_ventas.t_numeros;
               v_c pkg_ventas.t_numeros;
               n   PLS_INTEGER := 0;
            BEGIN
               FOR r IN (SELECT TO_NUMBER(REGEXP_SUBSTR(:prods, '[^,]+', 1, LEVEL)) AS p,
                                TO_NUMBER(REGEXP_SUBSTR(:cants, '[^,]+', 1, LEVEL)) AS c
                           FROM dual
                        CONNECT BY LEVEL <= REGEXP_COUNT(:prods, ',') + 1) LOOP
                  n := n + 1;
                  v_p(n) := r.p;
                  v_c(n) := r.c;
               END LOOP;
               pkg_ventas.registrar_venta(:suc, :cli, :emp, v_p, v_c, :id_venta, :total);
            END;"""
        try:
            with get_pool().acquire() as con:
                with con.cursor() as cur:
                    v_id = cur.var(oracledb.NUMBER)
                    v_total = cur.var(oracledb.NUMBER)
                    cur.execute(plsql,
                                prods=",".join(str(x["id_producto"]) for x in lineas),
                                cants=",".join(str(x["cantidad"]) for x in lineas),
                                suc=id_suc, cli=id_cli, emp=id_emp,
                                id_venta=v_id, total=v_total)
            id_venta = int(v_id.getvalue())
            st.success(f"✅ Factura #{id_venta} COMPLETADA por {q(v_total.getvalue())} (COMMIT realizado).")
            st.dataframe(query("""SELECT p.codigo, p.nombre AS producto, d.cantidad,
                                         d.precio_unitario, d.subtotal
                                    FROM detalle_venta d JOIN producto p ON p.id_producto = d.id_producto
                                   WHERE d.id_venta = :v ORDER BY p.codigo""", {"v": id_venta}),
                         hide_index=True)
        except oracledb.DatabaseError as e:
            st.error(f"❌ Venta rechazada por Oracle (ROLLBACK): {mensaje_oracle(e)}")
            st.info("No quedó ninguna factura ni se descontó stock. "
                    "El intento quedó registrado en LOG_VENTA_FALLIDA.")

elif pagina == "📋 Facturas":
    st.title("📋 Facturas")

    c1, c2 = st.columns([1, 3])
    estado = c1.selectbox("Estado", ["TODAS", "COMPLETADA", "ANULADA", "PENDIENTE"])
    facturas = query("""
        SELECT e.id_venta AS factura, TO_CHAR(e.fecha_venta, 'DD/MM/YYYY HH24:MI') AS fecha,
               s.nombre AS sucursal, c.nombre AS cliente,
               em.nombres || ' ' || em.apellidos AS cajero, e.estado, e.total
          FROM encabezado_venta e
          JOIN sucursal s  ON s.id_sucursal  = e.id_sucursal
          JOIN cliente  c  ON c.id_cliente   = e.id_cliente
          JOIN empleado em ON em.id_empleado = e.id_empleado
         WHERE (:est = 'TODAS' OR e.estado = :est)
         ORDER BY e.id_venta DESC
         FETCH FIRST 100 ROWS ONLY""", {"est": estado})
    st.caption("Últimas 100 facturas")
    st.dataframe(facturas, hide_index=True)

    if not facturas.empty:
        st.divider()
        id_fac = st.selectbox("Ver detalle de la factura", facturas["factura"])
        fila = facturas.loc[facturas["factura"] == id_fac].iloc[0]
        st.markdown(f"**Factura #{id_fac}** — {fila.sucursal} — {fila.cliente} — "
                    f"**{fila.estado}** — {q(fila.total)}")
        st.dataframe(query("""SELECT p.codigo, p.nombre AS producto, d.cantidad,
                                     d.precio_unitario, d.subtotal
                                FROM detalle_venta d JOIN producto p ON p.id_producto = d.id_producto
                               WHERE d.id_venta = :v ORDER BY p.codigo""", {"v": int(id_fac)}),
                     hide_index=True)

        if fila.estado == "COMPLETADA":
            with st.form("anular"):
                motivo = st.text_input("Motivo de la anulación", "Devolución del cliente")
                if st.form_submit_button("🚫 Anular factura y devolver stock"):
                    try:
                        with get_pool().acquire() as con:
                            with con.cursor() as cur:
                                cur.callproc("pkg_ventas.anular_venta", [int(id_fac), motivo])
                        st.success(f"Factura #{id_fac} ANULADA. El stock fue devuelto al inventario.")
                    except oracledb.DatabaseError as e:
                        st.error(mensaje_oracle(e))

elif pagina == "📦 Inventario":
    st.title("📦 Inventario por sucursal")

    sucursales = query("SELECT id_sucursal, nombre FROM sucursal ORDER BY nombre")
    c1, c2, c3 = st.columns([2, 2, 1])
    suc_nombre = c1.selectbox("Sucursal", sucursales["nombre"])
    id_suc = int(sucursales.loc[sucursales["nombre"] == suc_nombre, "id_sucursal"].iloc[0])
    buscar = c2.text_input("Buscar producto")
    solo_bajo = c3.checkbox("Solo bajo mínimo")

    inv = query("""SELECT codigo, producto, categoria, stock, stock_minimo, bajo_minimo,
                          valor_inventario,
                          TO_CHAR(fecha_actualizacion, 'DD/MM/YYYY HH24:MI') AS actualizado
                     FROM v_inventario_sucursal
                    WHERE id_sucursal = :s
                      AND (:b IS NULL OR UPPER(producto) LIKE '%' || UPPER(:b) || '%'
                                      OR UPPER(codigo)   LIKE '%' || UPPER(:b) || '%')
                      AND (:solo = 0 OR bajo_minimo = 'S')
                    ORDER BY codigo""",
                {"s": id_suc, "b": buscar or None, "solo": 1 if solo_bajo else 0})
    c1, c2 = st.columns(2)
    c1.metric("Productos mostrados", len(inv))
    c2.metric("Valor del inventario mostrado", q(inv["valor_inventario"].sum() if not inv.empty else 0))
    st.dataframe(inv, hide_index=True)

    st.divider()
    izq, der = st.columns(2)
    with izq:
        st.subheader("Ingreso de mercadería")
        prods = query("SELECT id_producto, codigo || ' - ' || nombre AS producto FROM producto "
                      "WHERE activo = 'S' ORDER BY codigo")
        with st.form("entrada"):
            prod = st.selectbox("Producto", prods["producto"])
            cant = st.number_input("Cantidad que ingresa", min_value=1, value=10, step=1)
            obs = st.text_input("Observación", "Ingreso de mercadería")
            if st.form_submit_button("➕ Registrar ingreso"):
                id_prod = int(prods.loc[prods["producto"] == prod, "id_producto"].iloc[0])
                try:
                    with get_pool().acquire() as con:
                        with con.cursor() as cur:
                            cur.callproc("pkg_ventas.registrar_entrada", [id_suc, id_prod, int(cant), obs])
                    st.success(f"Ingreso registrado en {suc_nombre}: +{int(cant)} de {prod}.")
                except oracledb.DatabaseError as e:
                    st.error(mensaje_oracle(e))

    with der:
        st.subheader("Kardex (últimos 30 movimientos)")
        st.dataframe(query("""
            SELECT TO_CHAR(m.fecha, 'DD/MM/YYYY HH24:MI') AS fecha, p.codigo, m.tipo,
                   m.cantidad, m.stock_anterior, m.stock_nuevo, m.id_venta AS factura
              FROM movimiento_inventario m
              JOIN producto p ON p.id_producto = m.id_producto
             WHERE m.id_sucursal = :s
             ORDER BY m.id_movimiento DESC
             FETCH FIRST 30 ROWS ONLY""", {"s": id_suc}), hide_index=True)

elif pagina == "📈 Reportes":
    st.title("📈 Reportes gerenciales")

    tabs = st.tabs(["Ventas mensuales", "Más vendidos", "Sucursales", "Baja rotación",
                    "Categorías", "Clientes", "Cajeros"])

    def mostrar(df, nombre):
        st.dataframe(df, hide_index=True)
        st.download_button("⬇️ Descargar CSV", df.to_csv(index=False).encode("utf-8-sig"),
                           file_name=f"{nombre}.csv", mime="text/csv", key=f"dl_{nombre}")

    with tabs[0]:
        df = query("SELECT * FROM v_rep_ventas_mensuales ORDER BY mes")
        st.line_chart(df.set_index("mes")[["total_ventas"]])
        mostrar(df, "ventas_mensuales")

    with tabs[1]:
        n = st.slider("Cantidad de productos", 5, 30, 10)
        df = query("""SELECT * FROM v_rep_top_productos ORDER BY ranking, ingresos DESC
                      FETCH FIRST :n ROWS ONLY""", {"n": n})
        st.bar_chart(df.set_index("producto")["unidades_vendidas"], horizontal=True)
        mostrar(df, "top_productos")

    with tabs[2]:
        df = query("SELECT * FROM v_rep_ranking_sucursales ORDER BY ranking")
        mejor = df.iloc[0]
        st.success(f"🏆 La sucursal que más vende es **{mejor.sucursal}** con {q(mejor.total_ventas)} "
                   f"({mejor.participacion_pct}% de las ventas).")
        st.bar_chart(df.set_index("sucursal")["total_ventas"])
        mostrar(df, "ranking_sucursales")

    with tabs[3]:
        resumen = query("""SELECT clasificacion, COUNT(*) AS productos,
                                  SUM(valor_inmovilizado) AS valor_inmovilizado
                             FROM v_rep_baja_rotacion GROUP BY clasificacion
                            ORDER BY productos DESC""")
        st.dataframe(resumen, hide_index=True)
        clases = st.multiselect("Mostrar", ["SIN VENTAS", "SIN MOVIMIENTO 90 DÍAS", "BAJA ROTACIÓN", "NORMAL"],
                                default=["SIN VENTAS", "SIN MOVIMIENTO 90 DÍAS", "BAJA ROTACIÓN"])
        df = query("SELECT * FROM v_rep_baja_rotacion ORDER BY unidades_90d, valor_inmovilizado DESC")
        mostrar(df[df["clasificacion"].isin(clases)], "baja_rotacion")

    with tabs[4]:
        df = query("SELECT * FROM v_rep_ventas_categoria ORDER BY ranking")
        st.bar_chart(df.set_index("categoria")["ingresos"], horizontal=True)
        mostrar(df, "ventas_categoria")

    with tabs[5]:
        df = query("SELECT * FROM v_rep_mejores_clientes ORDER BY ranking FETCH FIRST 20 ROWS ONLY")
        mostrar(df, "mejores_clientes")

    with tabs[6]:
        df = query("SELECT * FROM v_rep_desempeno_cajeros ORDER BY sucursal, ranking_en_sucursal")
        mostrar(df, "desempeno_cajeros")
