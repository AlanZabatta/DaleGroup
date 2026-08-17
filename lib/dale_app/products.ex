defmodule DaleApp.Products do
  import Ecto.Query
  alias DaleApp.Repo
  alias DaleApp.Products.Product

  def list_brand_products(brand_id) do
    Repo.all(from p in Product, where: p.brand_id == ^brand_id, order_by: p.position_in_brand)
  end

  # Productos visibles: si ocultar_sin_stock esta activo, saca los que tienen
  # filas en stock_items pero con la suma total en 0. Productos sin filas de
  # stock_items (sistema viejo, sin DALE9) no se ven afectados.
  def list_brand_products_visibles(brand_id, ocultar_sin_stock) do
    productos = list_brand_products(brand_id)

    if ocultar_sin_stock do
      ids_con_stock_cero =
        from(s in DaleApp.Products.StockItem,
          join: p in Product, on: p.id == s.product_id,
          where: p.brand_id == ^brand_id,
          group_by: p.id,
          having: sum(s.cantidad) <= 0,
          select: p.id
        )
        |> Repo.all()
        |> MapSet.new()

      Enum.reject(productos, fn p -> MapSet.member?(ids_con_stock_cero, p.id) end)
    else
      productos
    end
  end

  def get_product(id), do: Repo.get(Product, id)

  def crear_canje(attrs) do
    %DaleApp.Products.Canje{}
    |> DaleApp.Products.Canje.changeset(attrs)
    |> Repo.insert()
  end

  def total_canjeado_por_usuario(brand_id, user_id) do
    from(c in DaleApp.Products.Canje,
      where: c.brand_id == ^brand_id and c.user_id == ^user_id and c.es_dueño == false,
      select: sum(c.puntos_costo)
    )
    |> Repo.one()
    |> case do
      nil -> 0
      total -> total
    end
  end

  def descontar_stock_premio(premio) do
    if premio.cantidad_disponible do
      premio
      |> DaleApp.Products.Premio.changeset(%{cantidad_disponible: max(premio.cantidad_disponible - 1, 0)})
      |> Repo.update()
    else
      {:ok, premio}
    end
  end

  def listar_premios(brand_id) do
    from(p in DaleApp.Products.Premio, where: p.brand_id == ^brand_id and p.activo == true, order_by: [desc: p.puntos_costo])
    |> Repo.all()
  end

  def actualizar_premio(premio, attrs) do
    premio
    |> DaleApp.Products.Premio.changeset(attrs)
    |> Repo.update()
  end

  def borrar_premio(premio) do
    Repo.delete(premio)
  end

  def crear_premio(attrs) do
    %DaleApp.Products.Premio{}
    |> DaleApp.Products.Premio.changeset(attrs)
    |> Repo.insert()
  end

  def create_product(attrs) do
    %Product{}
    |> Product.changeset(attrs)
    |> Repo.insert()
  end

  def update_product(product, attrs) do
    product
    |> Product.changeset(attrs)
    |> Repo.update()
  end

  def delete_product(product), do: Repo.delete(product)

  # --- Bitácora de Stock ---

  def registrar_movimiento_stock(attrs) do
    %DaleApp.Products.MovimientoStock{}
    |> DaleApp.Products.MovimientoStock.changeset(attrs)
    |> Repo.insert()
  end

  def listar_movimientos_stock(brand_id, limite \\ 50) do
    Repo.all(
      from m in DaleApp.Products.MovimientoStock,
      where: m.brand_id == ^brand_id,
      order_by: [desc: m.inserted_at],
      limit: ^limite
    )
  end

  def listar_movimientos_stock_por_dia(brand_id, %Date{} = dia) do
    inicio_dia_ar = NaiveDateTime.new!(dia, ~T[00:00:00])
    fin_dia_ar = NaiveDateTime.new!(dia, ~T[23:59:59])
    inicio_utc = NaiveDateTime.add(inicio_dia_ar, 3 * 3600, :second)
    fin_utc = NaiveDateTime.add(fin_dia_ar, 3 * 3600, :second)

    Repo.all(
      from m in DaleApp.Products.MovimientoStock,
      where: m.brand_id == ^brand_id and m.inserted_at >= ^inicio_utc and m.inserted_at <= ^fin_utc,
      order_by: [desc: m.inserted_at]
    )
  end

  def ensure_brand_slots(brand_id) do
    existing = list_brand_products(brand_id)
    existing_count = length(existing)
    slots_needed = 10 - existing_count

    if slots_needed > 0 do
      for i <- (existing_count + 1)..(existing_count + slots_needed) do
        create_product(%{brand_id: brand_id, position_in_brand: i})
      end
    end
  end

  # Busqueda y filtrado de productos (buscador + filtros)
  # opts: %{texto, genero, estilo, categoria, precio_min, precio_max, orden}
  def buscar_productos(opts \\ %{}) do
    query =
      from p in Product,
      join: b in DaleApp.Brands.Brand, on: p.brand_id == b.id,
      where: p.active == true and not is_nil(p.image) and b.active == true,
      select: %{producto: p, marca: b}

    query = aplicar_genero(query, Map.get(opts, :genero))
    query = aplicar_estilo(query, Map.get(opts, :estilo))
    query = aplicar_categoria(query, Map.get(opts, :categoria))
    query = aplicar_precio(query, Map.get(opts, :precio_min), Map.get(opts, :precio_max))
    query = aplicar_nivel_precio(query, Map.get(opts, :nivel))

    texto = Map.get(opts, :texto)
    query_normal = aplicar_texto(query, texto)
    resultados = Repo.all(query_normal)

    resultados =
      if resultados == [] and is_binary(texto) and String.trim(texto) != "" do
        Repo.all(aplicar_texto_fuzzy(query, texto))
      else
        resultados
      end

    aplicar_orden(resultados, Map.get(opts, :orden))
  end

  defp aplicar_texto(query, nil), do: query
  defp aplicar_texto(query, ""), do: query
  defp aplicar_texto(query, texto) do
    patron = "%" <> String.downcase(String.trim(texto)) <> "%"
    from [p, b] in query,
      where: like(fragment("lower(?)", p.name), ^patron) or
             like(fragment("lower(?)", b.name), ^patron)
  end

  defp aplicar_texto_fuzzy(query, texto) do
    limpio = String.downcase(String.trim(texto))
    from [p, b] in query,
      where: fragment("word_similarity(?, lower(?)) > 0.3", ^limpio, p.name) or
             fragment("word_similarity(?, lower(?)) > 0.3", ^limpio, b.name),
      order_by: [desc: fragment("word_similarity(?, lower(?))", ^limpio, p.name)]
  end

  defp aplicar_genero(query, nil), do: query
  defp aplicar_genero(query, ""), do: query
  defp aplicar_genero(query, genero) do
    from [p, b] in query, where: p.gender == ^genero
  end

  defp aplicar_estilo(query, nil), do: query
  defp aplicar_estilo(query, ""), do: query
  defp aplicar_estilo(query, estilo) do
    from [p, b] in query, where: p.estilo == ^estilo
  end

  defp aplicar_categoria(query, nil), do: query
  defp aplicar_categoria(query, ""), do: query
  defp aplicar_categoria(query, categoria) do
    from [p, b] in query, where: ^categoria in p.categorias
  end

  defp aplicar_precio(query, nil, nil), do: query

  defp aplicar_precio(query, min, nil) do
    from [p, b] in query, where: p.price >= ^min
  end

  defp aplicar_precio(query, nil, max) do
    from [p, b] in query, where: p.price <= ^max
  end

  defp aplicar_precio(query, min, max) do
    from [p, b] in query, where: p.price >= ^min and p.price <= ^max
  end

  defp aplicar_orden(resultados, "menor_mayor"), do: Enum.sort_by(resultados, fn %{producto: p} -> p.price || 0 end)
  defp aplicar_orden(resultados, "mayor_menor"), do: Enum.sort_by(resultados, fn %{producto: p} -> -(p.price || 0) end)
  defp aplicar_orden(resultados, _), do: resultados


  def rangos_precio do
    precios = Repo.all(from p in Product, where: p.active == true and not is_nil(p.price), select: p.price, order_by: [asc: p.price])
    case precios do
      [] -> %{t1: 0, t2: 0}
      _ ->
        n = length(precios)
        %{t1: Enum.at(precios, max(div(n,3)-1,0)), t2: Enum.at(precios, max(div(2*n,3)-1,0))}
    end
  end
  defp aplicar_nivel_precio(query, nil), do: query
  defp aplicar_nivel_precio(query, ""), do: query
  defp aplicar_nivel_precio(query, "1") do
    %{t1: t1} = rangos_precio()
    from [p, b] in query, where: p.price <= ^t1
  end
  defp aplicar_nivel_precio(query, "2") do
    %{t1: t1, t2: t2} = rangos_precio()
    from [p, b] in query, where: p.price > ^t1 and p.price <= ^t2
  end
  defp aplicar_nivel_precio(query, "3") do
    %{t2: t2} = rangos_precio()
    from [p, b] in query, where: p.price > ^t2
  end
  defp aplicar_nivel_precio(query, _), do: query

  # --- Ventas ---

  alias DaleApp.Products.Venta

  def registrar_venta(attrs) do
    %Venta{}
    |> Venta.changeset(attrs)
    |> Repo.insert()
  end

  def deshacer_venta(venta_id) do
    case Repo.get(Venta, venta_id) do
      nil -> :ok
      venta -> Repo.delete(venta)
    end
  end

  defp fecha_desde_periodo("mensual"), do: NaiveDateTime.add(NaiveDateTime.utc_now(), -30 * 86400, :second)
  defp fecha_desde_periodo("trimestral"), do: NaiveDateTime.add(NaiveDateTime.utc_now(), -90 * 86400, :second)
  defp fecha_desde_periodo("anual"), do: NaiveDateTime.add(NaiveDateTime.utc_now(), -365 * 86400, :second)
  defp fecha_desde_periodo(_), do: NaiveDateTime.add(NaiveDateTime.utc_now(), -30 * 86400, :second)

  def top_productos_vendidos(brand_id, limite \\ 5, periodo \\ "mensual") do
    desde = fecha_desde_periodo(periodo)

    from(v in Venta,
      where: v.brand_id == ^brand_id and v.inserted_at >= ^desde,
      group_by: v.producto_nombre,
      order_by: [desc: count(v.id)],
      limit: ^limite,
      select: %{producto_nombre: v.producto_nombre, cantidad: count(v.id)}
    )
    |> Repo.all()
  end

  def productos_menos_vendidos(brand_id, limite \\ 5, periodo \\ "mensual") do
    desde = fecha_desde_periodo(periodo)

    ids_con_ventas =
      from(v in Venta, where: v.brand_id == ^brand_id and v.inserted_at >= ^desde, select: v.product_id, distinct: true)
      |> Repo.all()
      |> Enum.reject(&is_nil/1)

    from(p in Product,
      where: p.brand_id == ^brand_id and p.id not in ^ids_con_ventas and p.active == true,
      order_by: p.position_in_brand,
      limit: ^limite
    )
    |> Repo.all()
  end

  def stock_sin_movimiento(brand_id, dias_limite \\ 90, limite \\ 5) do
    ahora = NaiveDateTime.utc_now()

    items_con_stock =
      from(s in DaleApp.Products.StockItem,
        join: p in Product, on: p.id == s.product_id,
        where: p.brand_id == ^brand_id and s.cantidad > 0,
        select: %{product_id: p.id, producto: p, codigo_talle: s.codigo_talle, codigo_color: s.codigo_color}
      )
      |> Repo.all()

    ultimas_ventas =
      from(v in Venta,
        where: v.brand_id == ^brand_id,
        group_by: [v.product_id, v.codigo_talle],
        select: {{v.product_id, v.codigo_talle}, max(v.inserted_at)}
      )
      |> Repo.all()
      |> Map.new()

    items_con_stock
    |> Enum.map(fn item ->
      referencia = Map.get(ultimas_ventas, {item.product_id, item.codigo_talle}) || item.producto.inserted_at
      dias = div(NaiveDateTime.diff(ahora, referencia, :second), 86400)
      %{producto: item.producto, codigo_talle: item.codigo_talle, codigo_color: item.codigo_color, dias: dias}
    end)
    |> Enum.filter(fn %{dias: dias} -> dias >= dias_limite end)
    |> Enum.sort_by(fn %{dias: dias} -> dias end, :desc)
    |> Enum.take(limite)
  end

  def alerta_rotacion_reciente?(product_id, codigo_talle) do
    hace_30_dias = NaiveDateTime.add(NaiveDateTime.utc_now(), -30 * 86400, :second)

    Repo.exists?(
      from a in DaleApp.Products.AlertaRotacionEnviada,
        where:
          a.product_id == ^product_id and
            a.codigo_talle == ^codigo_talle and
            a.inserted_at >= ^hace_30_dias
    )
  end

  def registrar_alerta_rotacion(brand_id, product_id, codigo_talle) do
    %DaleApp.Products.AlertaRotacionEnviada{}
    |> DaleApp.Products.AlertaRotacionEnviada.changeset(%{
      brand_id: brand_id,
      product_id: product_id,
      codigo_talle: codigo_talle
    })
    |> Repo.insert()
  end

  def sell_through(brand_id, dias \\ 30, tipo \\ "stock") do
    desde = NaiveDateTime.add(NaiveDateTime.utc_now(), -dias * 86400, :second)

    vendidas_query = from(v in Venta, where: v.brand_id == ^brand_id and v.inserted_at >= ^desde)

    vendidas_query =
      if tipo == "dale" do
        from(v in vendidas_query, where: v.codigo_tipo == "99")
      else
        from(v in vendidas_query, where: v.codigo_tipo != "99" or is_nil(v.codigo_tipo))
      end

    vendidas = Repo.aggregate(vendidas_query, :count)

    stock_query =
      from(s in DaleApp.Products.StockItem,
        join: p in Product, on: p.id == s.product_id,
        where: p.brand_id == ^brand_id
      )

    stock_query =
      if tipo == "dale" do
        from([s, p] in stock_query, where: p.codigo_tipo == "99")
      else
        from([s, p] in stock_query, where: p.codigo_tipo != "99" or is_nil(p.codigo_tipo))
      end

    stock_actual = Repo.aggregate(stock_query, :sum, :cantidad) || 0

    total = vendidas + stock_actual
    porcentaje = if total > 0, do: round(vendidas / total * 100), else: 0

    %{porcentaje: porcentaje, vendidas: vendidas, stock_actual: stock_actual}
  end

  # --- Remontada: seguimiento de episodios de recuperacion de sell-through ---

  def registrar_snapshot_sell_through(brand_id, tipo) do
    datos = sell_through(brand_id, 30, tipo)

    %DaleApp.Products.SellThroughSnapshot{}
    |> DaleApp.Products.SellThroughSnapshot.changeset(%{
      brand_id: brand_id,
      tipo: tipo,
      porcentaje: datos.porcentaje,
      vendidas: datos.vendidas,
      stock_actual: datos.stock_actual
    })
    |> Repo.insert()

    actualizar_episodio_recuperacion(brand_id, tipo, datos.porcentaje)

    datos
  end

  defp resumen_movimientos_por_tipo(brand_id, tipo, fecha_inicio, fecha_fin) do
    base =
      from(m in DaleApp.Products.MovimientoStock,
        left_join: p in Product, on: p.id == m.producto_id,
        where: m.brand_id == ^brand_id and m.inserted_at >= ^fecha_inicio and m.inserted_at <= ^fecha_fin
      )

    filtrada =
      if tipo == "dale" do
        from([m, p] in base, where: p.codigo_tipo == "99")
      else
        from([m, p] in base, where: is_nil(p.id) or p.codigo_tipo != "99" or is_nil(p.codigo_tipo))
      end

    filtrada
    |> group_by([m, _p], m.tipo_accion)
    |> select([m, _p], {m.tipo_accion, count(m.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp actualizar_episodio_recuperacion(brand_id, tipo, porcentaje) do
    episodio_activo =
      Repo.one(
        from(e in DaleApp.Products.EpisodioRecuperacion,
          where: e.brand_id == ^brand_id and e.tipo == ^tipo and e.activo == true,
          limit: 1
        )
      )

    cond do
      is_nil(episodio_activo) and porcentaje < 40 ->
        %DaleApp.Products.EpisodioRecuperacion{}
        |> DaleApp.Products.EpisodioRecuperacion.changeset(%{
          brand_id: brand_id,
          tipo: tipo,
          sell_through_inicial: porcentaje,
          fecha_inicio: NaiveDateTime.utc_now(),
          activo: true
        })
        |> Repo.insert()

      episodio_activo && porcentaje >= 65 ->
        ahora = NaiveDateTime.utc_now()
        resumen = resumen_movimientos_por_tipo(brand_id, tipo, episodio_activo.fecha_inicio, ahora)

        episodio_activo
        |> DaleApp.Products.EpisodioRecuperacion.changeset(%{
          sell_through_final: porcentaje,
          fecha_fin: ahora,
          activo: false,
          resumen_movimientos: resumen
        })
        |> Repo.update()

      true ->
        :ok
    end
  end

  # --- Talles Incompletos ---

  def talles_incompletos(brand_id, orden \\ "severidad", limite \\ 5) do
    items =
      from(s in DaleApp.Products.StockItem,
        join: p in Product, on: p.id == s.product_id,
        where: p.brand_id == ^brand_id,
        select: %{product_id: p.id, producto: p, codigo_talle: s.codigo_talle, cantidad: s.cantidad, codigo_color: s.codigo_color}
      )
      |> Repo.all()

    ventas_por_producto =
      from(v in Venta,
        where: v.brand_id == ^brand_id and not is_nil(v.product_id),
        group_by: v.product_id,
        select: {v.product_id, count(v.id)}
      )
      |> Repo.all()
      |> Map.new()

    items
    |> Enum.group_by(& &1.product_id)
    |> Enum.map(fn {product_id, filas} ->
      talles = Enum.map(filas, fn f -> %{codigo_talle: f.codigo_talle, cantidad: f.cantidad} end)
      con_stock = Enum.count(talles, fn t -> t.cantidad > 0 end)
      sin_stock = Enum.count(talles, fn t -> t.cantidad <= 0 end)

      %{
        producto: List.first(filas).producto,
        codigo_color: List.first(filas).codigo_color,
        talles: Enum.sort_by(talles, & &1.codigo_talle),
        severidad: sin_stock,
        completo?: con_stock > 0 and sin_stock > 0,
        ventas: Map.get(ventas_por_producto, product_id, 0)
      }
    end)
    |> Enum.filter(& &1.completo?)
    |> ordenar_talles_incompletos(orden)
    |> Enum.take(limite)
  end

  defp ordenar_talles_incompletos(lista, "vendido"), do: Enum.sort_by(lista, & &1.ventas, :desc)
  defp ordenar_talles_incompletos(lista, "precio"), do: Enum.sort_by(lista, fn i -> i.producto.price || 0 end, :desc)
  defp ordenar_talles_incompletos(lista, _), do: Enum.sort_by(lista, & &1.severidad, :desc)

  def rendimiento_por_talla(brand_id, codigo_talle) do
    stock_actual =
      Repo.aggregate(
        from(s in DaleApp.Products.StockItem,
          join: p in Product, on: p.id == s.product_id,
          where: p.brand_id == ^brand_id and s.codigo_talle == ^codigo_talle
        ),
        :sum,
        :cantidad
      ) || 0

    vendidas =
      Repo.aggregate(
        from(v in Venta, where: v.brand_id == ^brand_id and v.codigo_talle == ^codigo_talle),
        :count
      )

    %{stock_actual: stock_actual, vendidas: vendidas}
  end
end
