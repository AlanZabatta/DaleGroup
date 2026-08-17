defmodule DaleAppWeb.StockPanoramicoLive do
  use DaleAppWeb, :live_view
  import Ecto.Query, only: [from: 2]
  alias DaleApp.Repo
  alias DaleApp.Brands.Brand
  alias DaleApp.Products.{Product, StockItem, CategoriaCustom, TalleCustom}

  defp formato_fecha_movimiento(nil), do: ""
  defp formato_fecha_movimiento(naive_utc) do
    ahora_ar = NaiveDateTime.add(NaiveDateTime.utc_now(), -3 * 3600, :second)
    fecha_ar = NaiveDateTime.add(naive_utc, -3 * 3600, :second)
    ayer_ar = NaiveDateTime.add(ahora_ar, -86_400, :second)

    hora_12 = case rem(fecha_ar.hour, 12) do
      0 -> 12
      h -> h
    end
    ampm = if fecha_ar.hour >= 12, do: "pm", else: "am"
    minuto = String.pad_leading(Integer.to_string(fecha_ar.minute), 2, "0")
    hora_str = "#{hora_12}:#{minuto}#{ampm}"

    cond do
      NaiveDateTime.to_date(fecha_ar) == NaiveDateTime.to_date(ahora_ar) ->
        "Hoy, #{hora_str}"

      NaiveDateTime.to_date(fecha_ar) == NaiveDateTime.to_date(ayer_ar) ->
        "Ayer, #{hora_str}"

      true ->
        dia = String.pad_leading(Integer.to_string(fecha_ar.day), 2, "0")
        mes = String.pad_leading(Integer.to_string(fecha_ar.month), 2, "0")
        anio = String.pad_leading(Integer.to_string(rem(fecha_ar.year, 100)), 2, "0")
        "#{hora_str} #{dia}/#{mes}/#{anio}"
    end
  end

  @categorias_fijas [
    %{codigo: "01", nombre: "Remeras", icono: "remera"},
    %{codigo: "02", nombre: "Pantalones", icono: "pantalon"},
    %{codigo: "03", nombre: "Buzos", icono: "buzo"},
    %{codigo: "04", nombre: "Camperas", icono: "campera"},
    %{codigo: "99", nombre: "Productos DaleStand", icono: "tienda"}
  ]

  @talles_fijos [
    %{codigo: "02", nombre: "S"},
    %{codigo: "03", nombre: "M"},
    %{codigo: "04", nombre: "L"},
    %{codigo: "05", nombre: "XL"}
  ]

  def mount(params, session, socket) do
    panel_inicial = Map.get(params, "panel", "normal")
    user_id = session["user_id"]
    brand = if user_id, do: Repo.get_by(Brand, user_id: user_id), else: nil
    if brand, do: asegurar_categorias_fijas(brand.id)
    productos_todos = if brand, do: listar_productos_con_stock(brand.id), else: []
    categorias = if brand, do: listar_categorias(brand.id), else: []
    talles_custom = if brand, do: listar_talles_custom(brand.id), else: []
    panel = if brand, do: calcular_panel(brand, productos_todos), else: nil
    talles_totales = if brand, do: calcular_talles_totales(brand.id, talles_custom), else: []
    movimientos_stock = if brand, do: DaleApp.Products.listar_movimientos_stock(brand.id), else: []
    top_vendidos = if brand, do: DaleApp.Products.top_productos_vendidos(brand.id, 3, "mensual"), else: []
    menos_vendidos = if brand, do: DaleApp.Products.productos_menos_vendidos(brand.id, 3, "mensual"), else: []
    menos_rotacion = if brand, do: DaleApp.Products.stock_sin_movimiento(brand.id, 30, 5), else: []
    if brand, do: DaleApp.Products.NotificacionesStock.revisar_rotacion(brand, menos_rotacion)
    # TODO Remontada: cuando se sumen chatbot personalizado y calificaciones de usuarios,
    # actualizar esta seccion para que tambien queden registradas como parte del seguimiento.
    sell_through = if brand, do: DaleApp.Products.registrar_snapshot_sell_through(brand.id, "stock"), else: %{porcentaje: 0, vendidas: 0, stock_actual: 0}
    sell_through_dale = if brand, do: DaleApp.Products.registrar_snapshot_sell_through(brand.id, "dale"), else: %{porcentaje: 0, vendidas: 0, stock_actual: 0}
    talles_incompletos_lista = if brand, do: DaleApp.Products.talles_incompletos(brand.id, "severidad", 5), else: []
    talla_seleccionada_rendimiento = talles_totales |> List.first() |> then(fn t -> t && elem(t, 0) end)
    rendimiento_talla = if brand && talla_seleccionada_rendimiento, do: DaleApp.Products.rendimiento_por_talla(brand.id, talla_seleccionada_rendimiento), else: %{stock_actual: 0, vendidas: 0}
    ids_usuarios_bitacora = movimientos_stock |> Enum.map(& &1.user_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    usuarios_bitacora =
      if ids_usuarios_bitacora == [] do
        %{}
      else
        from(u in DaleApp.Accounts.User, where: u.id in ^ids_usuarios_bitacora)
        |> Repo.all()
        |> Map.new(fn u -> {u.id, u} end)
      end

    {:ok,
     assign(socket,
       brand: brand,
       productos_todos: productos_todos,
       productos: productos_todos,
       termino: "",
       categoria_seleccionada: nil,
       categorias: categorias,
       talles_custom: talles_custom,
       mostrar_modal_categoria: false,
       mostrar_modal_talle: false,
       icono_elegido: nil,
       imagen_subida_url: nil,
       error_categoria: nil,
       error_talle: nil,
       editando_categoria_id: nil,
       articulo_editando: nil,
       panel: panel,
       talles_totales: talles_totales,
       talles_fijos_render: @talles_fijos,
       panel_tab: "control",
       mostrar_formulario_producto: false,
       mostrar_pantalla_imprimir: false,
       ruta_actual: "/mi-tienda/stock",
       combo_destacado_stock: nil,
       vista_panorama: "stock",
       user_id: user_id,
       movimientos_stock: movimientos_stock,
       top_vendidos: top_vendidos,
       menos_vendidos: menos_vendidos,
       periodo_ventas: "mensual",
       menos_rotacion: menos_rotacion,
       sell_through: sell_through,
       sell_through_dale: sell_through_dale,
       talles_incompletos_lista: talles_incompletos_lista,
       limite_talles_incompletos: 10,
       panel_inicial: panel_inicial,
       orden_talles_incompletos: "severidad",
       talla_seleccionada_rendimiento: talla_seleccionada_rendimiento,
       rendimiento_talla: rendimiento_talla,
       mostrar_consejos_sell_through: false,
       usuarios_bitacora: usuarios_bitacora,
       fecha_filtro_bitacora: nil
     )}
  end

  def handle_params(params, _uri, socket) do
    brand = socket.assigns.brand

    categoria_seleccionada =
      case {brand, Map.get(params, "categoria")} do
        {nil, _} -> nil
        {_brand, nil} -> nil
        {brand, tipo} ->
          case nombre_categoria(brand.id, tipo) do
            nil -> nil
            nombre ->
              numero_preview = DaleApp.Products.Dale9.proximo_numero(brand.id, tipo)
              %{codigo: tipo, nombre: nombre, numero_preview: numero_preview}
          end
      end

    forma = Map.get(params, "form")
    mostrar_formulario_producto = forma in ["crear", "editar"]

    articulo_editando =
      case {forma, Map.get(params, "articulo"), categoria_seleccionada} do
        {"editar", nombre, %{codigo: codigo}} when is_binary(nombre) ->
          construir_articulo_editando(socket, codigo, nombre)

        _ ->
          nil
      end

    mostrar_pantalla_imprimir = Map.get(params, "pantalla") == "imprimir"

    {:noreply,
     assign(socket,
       categoria_seleccionada: categoria_seleccionada,
       mostrar_formulario_producto: mostrar_formulario_producto,
       articulo_editando: articulo_editando,
       mostrar_pantalla_imprimir: mostrar_pantalla_imprimir
     )}
  end

  def handle_event("abrir_formulario_producto", _params, socket) do
    codigo = socket.assigns.categoria_seleccionada && socket.assigns.categoria_seleccionada.codigo
    {:noreply, push_patch(socket, to: url_stock(codigo, "crear"))}
  end

  def handle_event("cerrar_formulario_producto", _params, socket) do
    codigo = socket.assigns.categoria_seleccionada && socket.assigns.categoria_seleccionada.codigo
    {:noreply, push_patch(socket, to: url_stock(codigo))}
  end
  def handle_event("abrir_pantalla_imprimir", _params, socket) do
    codigo = socket.assigns.categoria_seleccionada && socket.assigns.categoria_seleccionada.codigo
    nombre = socket.assigns.articulo_editando && socket.assigns.articulo_editando.nombre
    {:noreply, push_patch(socket, to: url_stock(codigo, "editar", nombre, "imprimir"))}
  end
  def handle_event("cerrar_pantalla_imprimir", _params, socket) do
    codigo = socket.assigns.categoria_seleccionada && socket.assigns.categoria_seleccionada.codigo
    nombre = socket.assigns.articulo_editando && socket.assigns.articulo_editando.nombre
    {:noreply, push_patch(socket, to: url_stock(codigo, "editar", nombre))}
  end

  def handle_event("ir_a_producto_sin_stock", %{"tipo" => tipo, "nombre" => nombre, "color" => color, "talle" => talle}, socket) do
    {:noreply,
     socket
     |> assign(combo_destacado_stock: color <> "_" <> talle)
     |> push_patch(to: url_stock(tipo, "editar", nombre))}
  end

  def handle_event("editar_articulo", %{"nombre" => nombre}, socket) do
    codigo = socket.assigns.categoria_seleccionada.codigo
    {:noreply, push_patch(socket, to: url_stock(codigo, "editar", nombre))}
  end

  defp construir_articulo_editando(socket, codigo_tipo, nombre) do
    productos =
      socket.assigns.productos_todos
      |> Enum.map(fn {producto, _total, _codigos} -> producto end)
      |> Enum.filter(fn p -> p.name == nombre && p.codigo_tipo == codigo_tipo end)

    ids = Enum.map(productos, & &1.id)

    stock_items =
      if ids == [] do
        []
      else
        from(s in StockItem, where: s.product_id in ^ids) |> Repo.all()
      end

    stock_items_por_producto = Enum.group_by(stock_items, & &1.product_id)

    variantes =
      stock_items
      |> Enum.map(fn s -> {s.codigo_color <> "_" <> s.codigo_talle, s.cantidad} end)
      |> Map.new()

    productos_por_color =
      productos
      |> Enum.map(fn p ->
        codigo_color =
          case Map.get(stock_items_por_producto, p.id, []) do
            [item | _] -> item.codigo_color
            [] -> nil
          end

        {codigo_color, p.id}
      end)
      |> Enum.filter(fn {codigo_color, _id} -> codigo_color end)
      |> Map.new()

    numeros_por_color =
      productos
      |> Enum.map(fn p ->
        codigo_color =
          case Map.get(stock_items_por_producto, p.id, []) do
            [item | _] -> item.codigo_color
            [] -> nil
          end

        {codigo_color, p.codigo_numero}
      end)
      |> Enum.filter(fn {codigo_color, _numero} -> codigo_color end)
      |> Map.new()

    primero = List.first(productos)

    if primero do
      %{
        nombre: primero.name,
        precio: primero.price,
        descripcion: primero.description || "",
        imagen: primero.image,
        variantes: variantes,
        productos_por_color: productos_por_color,
        numeros_por_color: numeros_por_color
      }
    else
      nil
    end
  end

  defp capacidad_hoja_mm(ancho_mm, alto_mm) do
    area_ancho = 210 - 10 * 2
    area_alto = 297 - 10 * 2
    gap = 2
    cols = div(area_ancho + gap, ancho_mm + gap)
    rows = div(area_alto + gap, alto_mm + gap)
    cols * rows
  end

  defp codigo_completo_combo(nil, _codigo_tipo, _articulo), do: nil
  defp codigo_completo_combo(_clave, nil, _articulo), do: nil

  defp codigo_completo_combo(clave, codigo_tipo, articulo) do
    [codigo_color, codigo_talle] = String.split(clave, "_")

    case Map.get(articulo.numeros_por_color, codigo_color) do
      nil -> nil
      codigo_numero -> StockItem.armar_codigo(codigo_tipo, codigo_color, codigo_numero, codigo_talle)
    end
  end

  defp formatear_dale9_espaciado(codigo9) when is_binary(codigo9) and byte_size(codigo9) == 9 do
    <<tipo::binary-size(2), color::binary-size(2), numero::binary-size(3), talle::binary-size(2)>> = codigo9
    "#{tipo} #{color} #{numero} #{talle}"
  end

  defp formatear_dale9_espaciado(_codigo9), do: "··· ·· ··· ··"

  defp texto_colores_elegidos([]), do: ""
  defp texto_colores_elegidos([codigo]), do: "Color elegido: " <> StockItem.nombre_color(codigo)
  defp texto_colores_elegidos(codigos), do: "#{length(codigos)} colores elegidos"

  defp codigo_de_barras_svg(nil, _tipo), do: nil

  defp codigo_de_barras_svg(codigo, :code128) do
    case Barlix.Code128.encode(codigo) do
      {:ok, dato} ->
        case Barlix.SVG.print(dato, xdim: 2, height: 60, margin: 0) do
          {:ok, svg} -> svg
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp codigo_de_barras_svg(codigo, :ean13) do
    case Barlix.EAN13.encode(codigo) do
      {:ok, dato} ->
        case Barlix.SVG.print(dato, xdim: 2, height: 60, margin: 0) do
          {:ok, svg} -> svg
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp formatear_precio(precio) when is_integer(precio) do
    precio
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
    |> String.replace(",", ".")
  end

  defp formatear_precio(_precio), do: ""

  defp url_stock(categoria, forma \\ nil, articulo \\ nil, pantalla \\ nil) do
    params =
      [{"categoria", categoria}, {"form", forma}, {"articulo", articulo}, {"pantalla", pantalla}]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    case params do
      [] -> "/mi-tienda/stock"
      _ -> "/mi-tienda/stock?" <> URI.encode_query(params)
    end
  end

  def handle_event("producto_creado_ok", _params, socket) do
    productos_todos = listar_productos_con_stock(socket.assigns.brand.id)
    panel = calcular_panel(socket.assigns.brand, productos_todos)

    {:noreply,
     socket
     |> assign(productos_todos: productos_todos, productos: productos_todos, panel: panel)
     |> assign(mostrar_formulario_producto: false)}
  end

  def handle_event("filtrar_bitacora_fecha", %{"fecha" => ""}, socket) do
    movimientos = if socket.assigns.brand, do: DaleApp.Products.listar_movimientos_stock(socket.assigns.brand.id), else: []
    {:noreply, assign(socket, movimientos_stock: movimientos, fecha_filtro_bitacora: nil)}
  end

  def handle_event("filtrar_bitacora_fecha", %{"fecha" => fecha_str}, socket) do
    case Date.from_iso8601(fecha_str) do
      {:ok, dia} ->
        movimientos = if socket.assigns.brand, do: DaleApp.Products.listar_movimientos_stock_por_dia(socket.assigns.brand.id, dia), else: []
        {:noreply, assign(socket, movimientos_stock: movimientos, fecha_filtro_bitacora: fecha_str)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("cambiar_periodo_ventas", %{"periodo" => periodo}, socket) do
    top_vendidos =
      if socket.assigns.brand, do: DaleApp.Products.top_productos_vendidos(socket.assigns.brand.id, 3, periodo), else: []

    menos_vendidos =
      if socket.assigns.brand, do: DaleApp.Products.productos_menos_vendidos(socket.assigns.brand.id, 3, periodo), else: []

    {:noreply, assign(socket, periodo_ventas: periodo, top_vendidos: top_vendidos, menos_vendidos: menos_vendidos)}
  end

  def handle_event("toggle_consejos_sell_through", _params, socket) do
    {:noreply, assign(socket, mostrar_consejos_sell_through: !socket.assigns.mostrar_consejos_sell_through)}
  end

  def handle_event("cambiar_orden_talles_incompletos", %{"orden" => orden}, socket) do
    lista =
      if socket.assigns.brand, do: DaleApp.Products.talles_incompletos(socket.assigns.brand.id, orden, 10), else: []

    {:noreply, assign(socket, orden_talles_incompletos: orden, talles_incompletos_lista: lista, limite_talles_incompletos: 10)}
  end
  def handle_event("cargar_mas_talles_incompletos", _params, socket) do
    nuevo_limite = socket.assigns.limite_talles_incompletos + 10

    lista =
      if socket.assigns.brand,
        do: DaleApp.Products.talles_incompletos(socket.assigns.brand.id, socket.assigns.orden_talles_incompletos, nuevo_limite),
        else: []

    {:noreply, assign(socket, limite_talles_incompletos: nuevo_limite, talles_incompletos_lista: lista)}
  end


  def handle_event("seleccionar_talla_rendimiento", %{"talla" => talla}, socket) do
    rendimiento =
      if socket.assigns.brand, do: DaleApp.Products.rendimiento_por_talla(socket.assigns.brand.id, talla), else: %{stock_actual: 0, vendidas: 0}

    {:noreply, assign(socket, talla_seleccionada_rendimiento: talla, rendimiento_talla: rendimiento)}
  end

  def handle_event("cambiar_vista_panorama", %{"vista" => vista}, socket) do
    {:noreply, assign(socket, vista_panorama: vista)}
  end

  def handle_event("cambiar_tab_panel", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, panel_tab: tab)}
  end

  def handle_event("buscar", %{"termino" => termino}, socket) do
    termino_norm = termino |> String.trim() |> String.downcase()
    termino_traducido = traducir_si_es_ean13(termino_norm)

    productos =
      if termino_norm == "" do
        socket.assigns.productos_todos
      else
        Enum.filter(socket.assigns.productos_todos, fn {producto, _total, codigos} ->
          nombre_match = producto.name && String.contains?(String.downcase(producto.name), termino_norm)
          codigo_match = Enum.any?(codigos, fn c -> String.contains?(String.downcase(c), termino_norm) end)
          codigo_match_ean = termino_traducido && Enum.any?(codigos, fn c -> String.contains?(String.downcase(c), termino_traducido) end)
          nombre_match || codigo_match || codigo_match_ean
        end)
      end

    {:noreply, assign(socket, productos: productos, termino: termino)}
  end

  defp traducir_si_es_ean13(termino) do
    case StockItem.desde_ean13(termino) do
      {:ok, dale9} -> dale9
      {:error, _} -> nil
    end
  end

  def handle_event("elegir_categoria", %{"tipo" => tipo, "nombre" => _nombre}, socket) do
    {:noreply, push_patch(socket, to: url_stock(tipo))}
  end

  def handle_event("volver_categorias", _params, socket) do
    {:noreply, push_patch(socket, to: "/mi-tienda/stock")}
  end

  def handle_event("abrir_modal_categoria", _params, socket) do
    {:noreply, assign(socket, mostrar_modal_categoria: true, icono_elegido: nil, imagen_subida_url: nil, error_categoria: nil, editando_categoria_id: nil)}
  end

  def handle_event("abrir_modal_editar", %{"id" => id}, socket) do
    cat = Enum.find(socket.assigns.categorias, fn c -> to_string(c.id) == id end)

    if cat && cat.codigo_tipo != "99" do
      {:noreply,
       assign(socket,
         mostrar_modal_categoria: true,
         editando_categoria_id: cat.id,
         icono_elegido: cat.icono,
         imagen_subida_url: cat.imagen_url,
         error_categoria: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cerrar_modal_categoria", _params, socket) do
    {:noreply, assign(socket, mostrar_modal_categoria: false)}
  end

  def handle_event("elegir_icono", %{"icono" => icono}, socket) do
    {:noreply, assign(socket, icono_elegido: icono, imagen_subida_url: nil)}
  end

  def handle_event("guardar_categoria", %{"nombre" => nombre}, socket) do
    nombre = String.trim(nombre)
    icono = socket.assigns.icono_elegido
    imagen_url = socket.assigns.imagen_subida_url
    editando_id = socket.assigns.editando_categoria_id

    cond do
      nombre == "" ->
        {:noreply, assign(socket, error_categoria: "Ponele un nombre a la categoría.")}

      is_nil(icono) && is_nil(imagen_url) ->
        {:noreply, assign(socket, error_categoria: "Elegí un ícono o subí una imagen.")}

      editando_id ->
        cat = Repo.get(CategoriaCustom, editando_id)

        case cat |> CategoriaCustom.changeset(%{nombre: nombre, icono: icono, imagen_url: imagen_url}) |> Repo.update() do
          {:ok, _} ->
            categorias = listar_categorias(socket.assigns.brand.id)
            {:noreply, assign(socket, categorias: categorias, mostrar_modal_categoria: false, icono_elegido: nil, imagen_subida_url: nil, error_categoria: nil, editando_categoria_id: nil)}

          {:error, _} ->
            {:noreply, assign(socket, error_categoria: "No se pudo guardar.")}
        end

      true ->
        codigo_tipo = proximo_codigo_tipo(socket.assigns.brand.id)

        case %CategoriaCustom{}
             |> CategoriaCustom.changeset(%{nombre: nombre, icono: icono, imagen_url: imagen_url, codigo_tipo: codigo_tipo, brand_id: socket.assigns.brand.id})
             |> Repo.insert() do
          {:ok, _cat} ->
            categorias = listar_categorias(socket.assigns.brand.id)
            {:noreply, assign(socket, categorias: categorias, mostrar_modal_categoria: false, icono_elegido: nil, imagen_subida_url: nil, error_categoria: nil)}

          {:error, _} ->
            {:noreply, assign(socket, error_categoria: "No se pudo crear la categoría.")}
        end
    end
  end

  def handle_event("abrir_modal_talle", _params, socket) do
    {:noreply, assign(socket, mostrar_modal_talle: true, error_talle: nil)}
  end

  def handle_event("cerrar_modal_talle", _params, socket) do
    {:noreply, assign(socket, mostrar_modal_talle: false)}
  end

  def handle_event("crear_talle", %{"nombre" => nombre}, socket) do
    nombre = String.trim(nombre)

    if nombre == "" do
      {:noreply, assign(socket, error_talle: "Ponele un nombre al talle.")}
    else
      codigo_talle = proximo_codigo_talle(socket.assigns.brand.id)

      case %TalleCustom{}
           |> TalleCustom.changeset(%{nombre: nombre, codigo_talle: codigo_talle, brand_id: socket.assigns.brand.id})
           |> Repo.insert() do
        {:ok, _} ->
          talles_custom = listar_talles_custom(socket.assigns.brand.id)
          talles_totales = calcular_talles_totales(socket.assigns.brand.id, talles_custom)
          {:noreply, assign(socket, talles_custom: talles_custom, talles_totales: talles_totales, mostrar_modal_talle: false, error_talle: nil)}

        {:error, _} ->
          {:noreply, assign(socket, error_talle: "No se pudo crear el talle.")}
      end
    end
  end

  defp proximo_codigo_tipo(brand_id) do
    usados_fijos = Enum.map(@categorias_fijas, & &1.codigo)

    usados_custom =
      from(c in CategoriaCustom, where: c.brand_id == ^brand_id, select: c.codigo_tipo)
      |> Repo.all()

    usados = MapSet.new(usados_fijos ++ usados_custom)

    Enum.find(5..99, fn n -> not MapSet.member?(usados, String.pad_leading(Integer.to_string(n), 2, "0")) end)
    |> Integer.to_string()
    |> String.pad_leading(2, "0")
  end

  defp proximo_codigo_talle(brand_id) do
    usados_fijos = ["01", "02", "03", "04", "05", "06"]

    usados_custom =
      from(t in TalleCustom, where: t.brand_id == ^brand_id, select: t.codigo_talle)
      |> Repo.all()

    usados = MapSet.new(usados_fijos ++ usados_custom)

    Enum.find(7..99, fn n -> not MapSet.member?(usados, String.pad_leading(Integer.to_string(n), 2, "0")) end)
    |> Integer.to_string()
    |> String.pad_leading(2, "0")
  end

  defp listar_categorias(brand_id) do
    from(c in CategoriaCustom, where: c.brand_id == ^brand_id, order_by: [asc: c.codigo_tipo])
    |> Repo.all()
  end

  defp listar_talles_custom(brand_id) do
    from(t in TalleCustom, where: t.brand_id == ^brand_id, order_by: [asc: t.codigo_talle])
    |> Repo.all()
  end

  defp nombre_categoria(brand_id, codigo) do
    case Enum.find(@categorias_fijas, fn %{codigo: c} -> c == codigo end) do
      %{nombre: nombre} -> nombre
      nil ->
        case Repo.get_by(CategoriaCustom, brand_id: brand_id, codigo_tipo: codigo) do
          nil -> nil
          cat -> cat.nombre
        end
    end
  end

  defp asegurar_categorias_fijas(brand_id) do
    codigos_existentes =
      from(c in CategoriaCustom, where: c.brand_id == ^brand_id, select: c.codigo_tipo)
      |> Repo.all()
      |> MapSet.new()

    Enum.each(@categorias_fijas, fn cat ->
      unless MapSet.member?(codigos_existentes, cat.codigo) do
        %CategoriaCustom{}
        |> CategoriaCustom.changeset(%{nombre: cat.nombre, icono: cat.icono, codigo_tipo: cat.codigo, brand_id: brand_id})
        |> Repo.insert()
      end
    end)
  end

  defp calcular_panel(brand, productos_todos) do
    total = length(productos_todos)
    limite_dale = brand.image_limit || 12
    productos_dale = Enum.count(productos_todos, fn {p, _t, _c} -> p.active end)

    sin_stock =
      from(s in StockItem,
        join: p in Product, on: p.id == s.product_id,
        where: p.brand_id == ^brand.id and s.cantidad == 0,
        select: %{
          id: p.id,
          nombre: p.name,
          imagen: p.image,
          codigo_tipo: p.codigo_tipo,
          codigo_color: s.codigo_color,
          codigo_talle: s.codigo_talle
        }
      )
      |> Repo.all()

    poco_stock =
      from(s in StockItem,
        join: p in Product, on: p.id == s.product_id,
        where: p.brand_id == ^brand.id and s.cantidad > 0 and s.cantidad <= ^brand.umbral_poco_stock,
        select: %{
          id: p.id,
          nombre: p.name,
          imagen: p.image,
          codigo_tipo: p.codigo_tipo,
          codigo_color: s.codigo_color,
          codigo_talle: s.codigo_talle,
          cantidad: s.cantidad
        }
      )
      |> Repo.all()

    %{total: total, productos_dale: productos_dale, limite_dale: limite_dale, sin_stock: sin_stock, poco_stock: poco_stock}
  end

  defp calcular_talles_totales(brand_id, talles_custom) do
    totales_db =
      from(s in StockItem,
        join: p in Product, on: p.id == s.product_id,
        where: p.brand_id == ^brand_id,
        group_by: s.codigo_talle,
        select: {s.codigo_talle, sum(s.cantidad)}
      )
      |> Repo.all()
      |> Map.new()

    nombres_custom = Map.new(talles_custom, fn t -> {t.codigo_talle, t.nombre} end)

    (@talles_fijos ++ Enum.map(talles_custom, fn t -> %{codigo: t.codigo_talle, nombre: t.nombre} end))
    |> Enum.map(fn %{codigo: codigo, nombre: nombre} ->
      nombre_real = Map.get(nombres_custom, codigo, nombre)
      total = Map.get(totales_db, codigo, 0)
      {codigo, nombre_real, total}
    end)
  end

  defp listar_productos_con_stock(brand_id) do
    variantes_por_producto =
      from(s in StockItem,
        join: p in Product, on: p.id == s.product_id,
        where: p.brand_id == ^brand_id,
        select: {s.product_id, s.codigo}
      )
      |> Repo.all()
      |> Enum.group_by(fn {product_id, _codigo} -> product_id end, fn {_product_id, codigo} -> codigo end)

    totales =
      from(s in StockItem,
        join: p in Product, on: p.id == s.product_id,
        where: p.brand_id == ^brand_id,
        group_by: s.product_id,
        select: {s.product_id, sum(s.cantidad)}
      )
      |> Repo.all()
      |> Map.new()

    from(p in Product, where: p.brand_id == ^brand_id, order_by: [asc: p.name])
    |> Repo.all()
    |> Enum.map(fn producto ->
      total = Map.get(totales, producto.id, 0)
      codigos_variantes = Map.get(variantes_por_producto, producto.id, [])
      codigo_base = if producto.codigo_tipo && producto.codigo_numero, do: [producto.codigo_tipo <> producto.codigo_numero], else: []
      {producto, total, codigos_variantes ++ codigo_base}
    end)
  end

  defp filas_de_categoria(productos_todos, codigo_tipo) do
    productos =
      productos_todos
      |> Enum.map(fn {producto, _total, _codigos} -> producto end)
      |> Enum.filter(fn producto -> producto.codigo_tipo == codigo_tipo end)

    ids = Enum.map(productos, & &1.id)

    stock_items_por_producto =
      if ids == [] do
        %{}
      else
        from(s in StockItem, where: s.product_id in ^ids)
        |> Repo.all()
        |> Enum.group_by(& &1.product_id)
      end

    productos
    |> Enum.map(fn producto ->
      items = Map.get(stock_items_por_producto, producto.id, [])

      talles =
        items
        |> Enum.group_by(& &1.codigo_talle)
        |> Enum.map(fn {codigo_talle, lista} ->
          {codigo_talle, Enum.sum(Enum.map(lista, & &1.cantidad))}
        end)
        |> Enum.sort_by(fn {codigo_talle, _cantidad} -> codigo_talle end)

      codigo_color =
        case items do
          [primero | _] -> primero.codigo_color
          [] -> nil
        end

      %{producto: producto, codigo_color: codigo_color, talles: talles}
    end)
    |> Enum.group_by(fn fila -> fila.producto.name end)
    |> Enum.sort_by(fn {nombre, _filas} -> nombre end)
  end

  defp estado_talle(cantidad, _umbral_poco) when cantidad <= 0, do: {"#fdecea", "#c0392b"}
  defp estado_talle(cantidad, umbral_poco) when cantidad <= umbral_poco, do: {"#fff6d9", "#a67c00"}
  defp estado_talle(_cantidad, _umbral_poco), do: {"#e6f4e6", "#186904"}

  defp color_hex_por_codigo(codigo_color) do
    mapa = %{
      "Negro" => "#1a1a1a", "Blanco" => "#ffffff", "Gris" => "#9e9e9e", "Beige" => "#e8dcc8",
      "Rojo" => "#d32f2f", "Bordó" => "#6d1b1b", "Rosa" => "#e91e8c", "Naranja" => "#f57c00",
      "Amarillo" => "#fbc02d", "Verde" => "#43a047", "Verde oscuro" => "#1b5e20", "Celeste" => "#4fc3f7",
      "Azul" => "#1565c0", "Azul marino" => "#0d1b4c", "Violeta" => "#7b1fa2", "Marrón" => "#5d3a1a",
      "Dorado" => "#c9a227", "Plateado" => "#b0b0b0"
    }
    Map.get(mapa, StockItem.nombre_color(codigo_color), "#cccccc")
  end

  defp icono_svg("remera"), do: ~s(<path d="M15 4l6 2v5h-3v8a1 1 0 0 1 -1 1h-10a1 1 0 0 1 -1 -1v-8h-3v-5l6 -2a3 3 0 0 0 6 0"/>)
  defp icono_svg("pantalon"), do: ~s(<path d="M6 3h12l1 6-2 12h-4l-1-9-1 9h-4l-2-12z"/>)
  defp icono_svg("buzo"), do: ~s(<path d="M15 4l6 3v5h-3v9a1 1 0 0 1 -1 1h-10a1 1 0 0 1 -1 -1v-9h-3v-5l6 -3a3 3 0 0 0 6 0"/>)
  defp icono_svg("campera"), do: ~s(<path d="M15 4l6 2v5h-3v8a1 1 0 0 1 -1 1h-10a1 1 0 0 1 -1 -1v-8h-3v-5l6 -2a3 3 0 0 0 6 0"/><path d="M9 7l3 3l3 -3"/><line x1="12" y1="10" x2="12" y2="20"/>)
  defp icono_svg("anteojos"), do: ~s(<circle cx="6.5" cy="12" r="3.5"/><circle cx="17.5" cy="12" r="3.5"/><line x1="10" y1="11" x2="14" y2="11"/><path d="M3 11l-1 1"/><path d="M21 11l1 1"/>)
  defp icono_svg("bolso"), do: ~s(<rect x="3" y="8" width="18" height="12" rx="2"/><path d="M8 8v-2a4 4 0 0 1 8 0v2"/>)
  defp icono_svg("tienda"), do: ~s(<path d="M3 21l18 0"/><path d="M3 7v1a3 3 0 0 0 6 0v-1m0 1a3 3 0 0 0 6 0v-1m0 1a3 3 0 0 0 6 0v-1h-18l2 -4h14l2 4"/><path d="M5 21l0 -10.15"/><path d="M19 21l0 -10.15"/><path d="M9 21v-4a2 2 0 0 1 2 -2h2a2 2 0 0 1 2 2v4"/>)
  defp icono_svg(_), do: ~s(<circle cx="12" cy="12" r="8"/>)

  defp icono_svg_por_codigo(codigo, categorias) do
    cat = Enum.find(categorias, fn c -> c.codigo_tipo == codigo end)
    icono_svg(cat && cat.icono)
  end

  def render(assigns) do
    ~H"""
    <div style="padding: 24px 18px 40px; font-family: Poppins, sans-serif; max-width: 600px; margin: 0 auto; background-color: white; min-height: 100vh; position: relative;">
      <%= cond do %>
        <% @categoria_seleccionada && @mostrar_formulario_producto -> %>
          <button type="button" onclick="manejarClickVolverFormularioStock()" style="width: 34px; height: 34px; border-radius: 50%; background: white; border: 1.5px solid #e0e0e0; cursor: pointer; display: flex; align-items: center; justify-content: center; margin-bottom: 16px; padding: 0;">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><line x1="19" y1="12" x2="5" y2="12"/><polyline points="12 19 5 12 12 5"/></svg>
          </button>
          <button type="button" id="boton-cerrar-formulario-real-stock" phx-click="cerrar_formulario_producto" style="display: none;"></button>
          <button type="button" id="boton-abrir-pantalla-imprimir-real-stock" phx-click="abrir_pantalla_imprimir" style="display: none;"></button>
          <button type="button" id="boton-cerrar-pantalla-imprimir-real-stock" phx-click="cerrar_pantalla_imprimir" style="display: none;"></button>
        <% @categoria_seleccionada -> %>
          <button type="button" phx-click="volver_categorias" style="display: inline-flex; background: none; border: none; color: #186904; font-size: 22px; font-weight: 700; cursor: pointer; line-height: 1; padding: 0; margin-bottom: 16px;">&#x2715;</button>
        <% true -> %>
          <.link navigate="/mi-tienda" style="display: inline-flex; background: none; border: none; color: #186904; font-size: 22px; font-weight: 700; cursor: pointer; line-height: 1; text-decoration: none; margin-bottom: 16px;">&#x2715;</.link>
      <% end %>

      <%= if is_nil(@categoria_seleccionada) && !@mostrar_formulario_producto do %>
        <div class="stock-dots" style="position: absolute; top: 28px; right: 18px; display: flex; gap: 6px; align-items: center; pointer-events: none; z-index: 3; opacity: 0.7;">
          <div class={"stock-dot #{if @panel_inicial != "avanzado", do: "activo", else: ""}"} id="punto-slider-stock-0"></div>
          <div class={"stock-dot #{if @panel_inicial == "avanzado", do: "activo", else: ""}"} id="punto-slider-stock-1"></div>
        </div>
      <% end %>

      <%= if @categoria_seleccionada do %>
        <p id="breadcrumb-stock-categoria" style={"font-size: 26px; font-weight: 800; margin: 0 0 20px; display: #{if @mostrar_pantalla_imprimir, do: "none", else: "block"};"}>
          <span style="color: #aaa; cursor: pointer;" phx-click="volver_categorias">Mi Stock</span>
          <span style="color: #aaa;">/</span>
          <span id="breadcrumb-nombre-categoria-stock" style="color: #186904;"><%= @categoria_seleccionada.nombre %></span>
        </p>
      <% else %>
      <% end %>

      <style>
        @keyframes blurCambioBusqueda {
          0% { filter: blur(0px); opacity: 1; }
          45% { filter: blur(6px); opacity: 0.2; }
          55% { filter: blur(6px); opacity: 0.2; }
          100% { filter: blur(0px); opacity: 1; }
        }
        .busqueda-animada { animation: blurCambioBusqueda 0.6s ease; will-change: filter, opacity; contain: layout style paint; }
        #stock-slider::-webkit-scrollbar { display: none; }
        .stock-dot { width: 5px; height: 5px; border-radius: 50%; background: #ccc; transition: all 0.3s; }
        .stock-dot.activo { background: #186904; width: 14px; border-radius: 3px; }
      </style>


      <%= if is_nil(@categoria_seleccionada) && !@mostrar_formulario_producto do %>
      <div id="stock-slider" style="display: flex; gap: 56px; width: 100%; overflow-x: auto; overflow-y: hidden; scroll-snap-type: x mandatory; -webkit-overflow-scrolling: touch; scrollbar-width: none;">
        <div id="stock-panel-0" style="flex: 0 0 100%; min-width: 100%; scroll-snap-align: start; scroll-snap-stop: always; box-sizing: border-box; background: #ffffff; transform: translateZ(0);">
          <p style="font-size: 26px; font-weight: 800; color: #186904; margin: 0 0 20px;">Mi Stock</p>
      <form phx-change="buscar" phx-submit="buscar" id="form-buscar-stock" phx-hook=".BuscadorStock" style={"position: relative; width: 100%; margin-bottom: 20px; #{if @categoria_seleccionada && @mostrar_formulario_producto, do: "display: none;", else: ""}"}>
        <input
          type="text"
          name="termino"
          id="input-buscar-stock"
          value={@termino}
          autocomplete="off"
          style="width: 100%; box-sizing: border-box; padding: 13px 16px 13px 42px; border: 1.5px solid #999; border-radius: 16px; font-family: Poppins, sans-serif; font-size: 14px; font-weight: 700; color: #333; outline: none; background: white;"
        />
        <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="#999" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="position: absolute; left: 14px; top: 50%; transform: translateY(-50%); pointer-events: none;"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
        <span id="placeholder-buscar-stock" style="position: absolute; left: 42px; top: 50%; transform: translateY(-50%); font-family: Poppins, sans-serif; font-size: 14px; font-weight: 700; color: #186904; pointer-events: none;">Buscar Mi Stock</span>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".BuscadorStock">
          export default {
            mounted() {
              this.iniciar();
            },
            updated() {
              this.iniciar();
            },
            iniciar() {
              if (this._yaIniciado) return;
              this._yaIniciado = true;

              const palabras = ["Buscar Mi Stock", "Remera", "030105218", "Pantalon", "Buzo", "070311046", "Campera", "Zapatilla", "010200432"];
              let idx = 0;
              const input = document.getElementById('input-buscar-stock');
              const label = document.getElementById('placeholder-buscar-stock');

              const actualizarVisibilidad = () => {
                if (input && label) {
                  label.style.display = (document.activeElement === input || input.value !== "") ? "none" : "block";
                }
              };

              if (input) {
                input.addEventListener('focus', actualizarVisibilidad);
                input.addEventListener('blur', actualizarVisibilidad);
                input.addEventListener('input', actualizarVisibilidad);
              }

              this._intervalo = setInterval(() => {
                idx = (idx + 1) % palabras.length;
                const labelActual = document.getElementById('placeholder-buscar-stock');
                if (labelActual && document.activeElement !== input) {
                  labelActual.classList.remove('busqueda-animada'); void labelActual.offsetWidth; labelActual.classList.add('busqueda-animada');
                  setTimeout(() => { labelActual.textContent = palabras[idx]; }, 270);
                }
              }, 3000);
            },
            destroyed() {
              if (this._intervalo) clearInterval(this._intervalo);
            }
          }
        </script>
      </form>
      <%= if is_nil(@categoria_seleccionada) && @panel do %>
        <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 20px; padding: 22px 20px; margin-bottom: 16px; box-shadow: 0 4px 14px rgba(24,105,4,0.10);">
          <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 18px;">
            <p style="font-size: 11.5px; font-weight: 800; color: #186904; margin: 0; text-transform: uppercase; letter-spacing: 1.2px;">Panorama</p>
            <div style="display: inline-flex; padding: 3px; background: #eef4ec; border-radius: 10px; gap: 3px; box-shadow: inset 0 1px 3px rgba(24,105,4,0.10);">
              <button type="button" phx-click="cambiar_tab_panel" phx-value-tab="control" style={"padding: 6px 14px; border-radius: 8px; border: none; cursor: pointer; font-family: Poppins, sans-serif; font-size: 11.5px; font-weight: 700; transition: all 0.15s; background: #{if @panel_tab == "control", do: "#186904", else: "transparent"}; color: #{if @panel_tab == "control", do: "white", else: "#5c7a56"};"}>Control</button>
              <button type="button" phx-click="cambiar_tab_panel" phx-value-tab="talle" style={"padding: 6px 14px; border-radius: 8px; border: none; cursor: pointer; font-family: Poppins, sans-serif; font-size: 11.5px; font-weight: 700; transition: all 0.15s; background: #{if @panel_tab == "talle", do: "#186904", else: "transparent"}; color: #{if @panel_tab == "talle", do: "white", else: "#5c7a56"};"}>Talle</button>
            </div>
          </div>

          <%= if @panel_tab == "control" do %>
            <%
              en_dale? = fn codigo -> if @vista_panorama == "dale", do: codigo == "99", else: codigo != "99" end
              sin_stock_filtrado = Enum.filter(@panel.sin_stock, fn p -> en_dale?.(p.codigo_tipo) end)
              poco_stock_filtrado = Enum.filter(@panel.poco_stock, fn p -> en_dale?.(p.codigo_tipo) end)
              hay_problema_stock = Enum.any?(@panel.sin_stock ++ @panel.poco_stock, fn p -> p.codigo_tipo != "99" end)
              hay_problema_dale = Enum.any?(@panel.sin_stock ++ @panel.poco_stock, fn p -> p.codigo_tipo == "99" end)
            %>
            <div style="display: flex; align-items: flex-end; gap: 14px;">
              <%= if @vista_panorama == "stock" do %>
                <div phx-click="cambiar_vista_panorama" phx-value-vista="stock" style="position: relative; cursor: pointer; padding: 10px 16px; border-radius: 14px; background: #e6f2e3; border: 1.5px solid #186904;">
                  <%= if hay_problema_stock do %>
                    <span style="position: absolute; top: -3px; right: -3px; width: 10px; height: 10px; border-radius: 50%; background: #c0392b; box-shadow: 0 0 0 2px white;"></span>
                  <% end %>
                  <p style="font-size: 32px; font-weight: 800; color: #186904; margin: 0; line-height: 1; letter-spacing: -0.5px;"><%= @panel.total %></p>
                  <p style="font-size: 11px; color: #7a9a76; margin: 5px 0 0; font-weight: 600;">productos totales</p>
                </div>
                <div phx-click="cambiar_vista_panorama" phx-value-vista="dale" style="position: relative; cursor: pointer; padding: 8px 14px; border-radius: 14px; background: #f4f4f4; border: 1.5px solid #e0e0e0; opacity: 0.6;">
                  <%= if hay_problema_dale do %>
                    <span style="position: absolute; top: -3px; right: -3px; width: 10px; height: 10px; border-radius: 50%; background: #c0392b; box-shadow: 0 0 0 2px white;"></span>
                  <% end %>
                  <p style="font-size: 16px; font-weight: 800; color: #333; margin: 0; line-height: 1;"><%= @panel.productos_dale %><span style="font-size: 11px; color: #aaa; font-weight: 600;">/<%= @panel.limite_dale %></span></p>
                  <p style="font-size: 10px; color: #999; margin: 4px 0 0; font-weight: 600;">productos Dale</p>
                </div>
              <% else %>
                <div phx-click="cambiar_vista_panorama" phx-value-vista="dale" style="position: relative; cursor: pointer; padding: 10px 16px; border-radius: 14px; background: #e6f2e3; border: 1.5px solid #186904;">
                  <%= if hay_problema_dale do %>
                    <span style="position: absolute; top: -3px; right: -3px; width: 10px; height: 10px; border-radius: 50%; background: #c0392b; box-shadow: 0 0 0 2px white;"></span>
                  <% end %>
                  <p style="font-size: 32px; font-weight: 800; color: #186904; margin: 0; line-height: 1; letter-spacing: -0.5px;"><%= @panel.productos_dale %><span style="font-size: 16px; color: #aaa; font-weight: 700;">/<%= @panel.limite_dale %></span></p>
                  <p style="font-size: 11px; color: #7a9a76; margin: 5px 0 0; font-weight: 600;">productos Dale</p>
                </div>
                <div phx-click="cambiar_vista_panorama" phx-value-vista="stock" style="position: relative; cursor: pointer; padding: 8px 14px; border-radius: 14px; background: #f4f4f4; border: 1.5px solid #e0e0e0; opacity: 0.6;">
                  <%= if hay_problema_stock do %>
                    <span style="position: absolute; top: -3px; right: -3px; width: 10px; height: 10px; border-radius: 50%; background: #c0392b; box-shadow: 0 0 0 2px white;"></span>
                  <% end %>
                  <p style="font-size: 16px; font-weight: 800; color: #333; margin: 0; line-height: 1;"><%= @panel.total %></p>
                  <p style="font-size: 10px; color: #999; margin: 4px 0 0; font-weight: 600;">productos totales</p>
                </div>
              <% end %>
            </div>

            <%= if sin_stock_filtrado != [] do %>
              <div style="border-top: 1.5px dashed #dce8da; margin-top: 18px; padding-top: 14px;">
                <div style="display: flex; align-items: center; gap: 6px; margin-bottom: 10px;">
                  <span style="width: 6px; height: 6px; border-radius: 50%; background: #c0392b; flex-shrink: 0;"></span>
                  <p style="font-size: 11.5px; font-weight: 800; color: #c0392b; margin: 0; text-transform: uppercase; letter-spacing: 0.6px;">Sin unidades (<%= length(sin_stock_filtrado) %>)</p>
                </div>
                <style>
                  .sin-stock-scroll::-webkit-scrollbar { display: none; }
                  .sin-stock-scroll { scrollbar-width: none; -ms-overflow-style: none; }
                </style>
                <div class="sin-stock-scroll" style="display: flex; gap: 10px; overflow-x: auto; padding-bottom: 0;">
                  <%= for p <- sin_stock_filtrado do %>
                    <div phx-click="ir_a_producto_sin_stock" phx-value-tipo={p.codigo_tipo} phx-value-nombre={p.nombre} phx-value-color={p.codigo_color} phx-value-talle={p.codigo_talle} style="flex-shrink: 0; width: 106px; border-radius: 16px; overflow: hidden; border: 1px solid #f4e4e2; box-shadow: 0 3px 10px rgba(192,57,43,0.08); background: white; cursor: pointer;">
                      <div style="aspect-ratio: 3/4; background: #faf5f4; display: flex; align-items: center; justify-content: center; overflow: hidden; position: relative;">
                        <%= if p.imagen do %>
                          <img src={p.imagen} style="width: 100%; height: 100%; object-fit: cover;" />
                        <% else %>
                          <svg width="55%" height="55%" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" style="opacity: 0.5;">
                            {raw(icono_svg_por_codigo(p.codigo_tipo, @categorias))}
                          </svg>
                        <% end %>
                        <span style={"position: absolute; top: 6px; right: 6px; width: 12px; height: 12px; border-radius: 50%; background: #{color_hex_por_codigo(p.codigo_color)}; box-shadow: 0 0 0 2px white; #{if p.codigo_color == "21", do: "border: 1.5px solid #333;", else: ""}"}></span>
                      </div>
                      <div style="padding: 7px 9px;">
                        <p style="font-size: 10.5px; font-weight: 700; color: #111; margin: 0 0 2px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;"><%= p.nombre %></p>
                        <p style="font-size: 10px; color: #999; margin: 0; font-weight: 600;">Talle <%= StockItem.nombre_talle(p.codigo_talle) %></p>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>

            <%= if sin_stock_filtrado == [] && poco_stock_filtrado == [] do %>
              <div style="border-top: 1.5px dashed #dce8da; margin-top: 18px; padding-top: 14px; display: flex; align-items: center; gap: 8px;">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12l5 5l10 -10"/></svg>
                <p style="font-size: 12.5px; font-weight: 700; color: #186904; margin: 0;">Todo tiene stock correctamente</p>
              </div>
            <% end %>

            <%= if poco_stock_filtrado != [] do %>
              <div style="border-top: 1.5px dashed #dce8da; margin-top: 18px; padding-top: 14px;">
                <div style="display: flex; align-items: center; gap: 6px; margin-bottom: 10px;">
                  <span style="width: 6px; height: 6px; border-radius: 50%; background: #a67c00; flex-shrink: 0;"></span>
                  <p style="font-size: 11.5px; font-weight: 800; color: #a67c00; margin: 0; text-transform: uppercase; letter-spacing: 0.6px;">Poco stock (<%= length(poco_stock_filtrado) %>)</p>
                </div>
                <div class="sin-stock-scroll" style="display: flex; gap: 10px; overflow-x: auto; padding-bottom: 0;">
                  <%= for p <- poco_stock_filtrado do %>
                    <div phx-click="ir_a_producto_sin_stock" phx-value-tipo={p.codigo_tipo} phx-value-nombre={p.nombre} phx-value-color={p.codigo_color} phx-value-talle={p.codigo_talle} style="flex-shrink: 0; width: 106px; border-radius: 16px; overflow: hidden; border: 1px solid #f5e9c8; box-shadow: 0 3px 10px rgba(166,124,0,0.08); background: white; cursor: pointer;">
                      <div style="aspect-ratio: 3/4; background: #fdf9ee; display: flex; align-items: center; justify-content: center; overflow: hidden; position: relative;">
                        <%= if p.imagen do %>
                          <img src={p.imagen} style="width: 100%; height: 100%; object-fit: cover;" />
                        <% else %>
                          <svg width="55%" height="55%" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" style="opacity: 0.5;">
                            {raw(icono_svg_por_codigo(p.codigo_tipo, @categorias))}
                          </svg>
                        <% end %>
                        <span style={"position: absolute; top: 6px; right: 6px; width: 12px; height: 12px; border-radius: 50%; background: #{color_hex_por_codigo(p.codigo_color)}; box-shadow: 0 0 0 2px white; #{if p.codigo_color == "21", do: "border: 1.5px solid #333;", else: ""}"}></span>
                      </div>
                      <div style="padding: 7px 9px;">
                        <p style="font-size: 10.5px; font-weight: 700; color: #111; margin: 0 0 2px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;"><%= p.nombre %></p>
                        <p style="font-size: 10px; color: #a67c00; margin: 0; font-weight: 600;">Talle <%= StockItem.nombre_talle(p.codigo_talle) %> · <%= p.cantidad %> u.</p>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          <% else %>
            <p style="font-size: 11.5px; font-weight: 800; color: #186904; margin: 0 0 10px; text-transform: uppercase; letter-spacing: 0.6px;">Talles cargados</p>
            <div style="display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 18px;">
              <%= for %{nombre: nombre} <- @talles_fijos_render do %>
                <span style="padding: 7px 15px; border-radius: 16px; background: #186904; color: white; font-size: 12.5px; font-weight: 700;"><%= nombre %></span>
              <% end %>
              <%= for t <- @talles_custom do %>
                <span style="padding: 7px 15px; border-radius: 16px; background: #186904; color: white; font-size: 12.5px; font-weight: 700;"><%= t.nombre %></span>
              <% end %>
              <button type="button" phx-click="abrir_modal_talle" style="width: 30px; height: 30px; border-radius: 50%; border: 1.5px dashed #b8d4b3; background: white; color: #186904; cursor: pointer; font-size: 16px; font-weight: 300; display: flex; align-items: center; justify-content: center;">+</button>
            </div>

            <div style="display: flex; flex-direction: column;">
              <%= for {_codigo, nombre, total} <- @talles_totales do %>
                <div style="display: flex; align-items: center; gap: 10px; padding: 9px 2px; border-bottom: 1px solid #eef4ec;">
                  <span style="width: 3px; height: 16px; border-radius: 2px; background: #186904; flex-shrink: 0;"></span>
                  <span style="font-size: 12.5px; color: #666; font-weight: 500; flex: 1;">Talle <%= nombre %></span>
                  <span style="font-size: 15px; font-weight: 800; color: #186904;"><%= total %></span>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>

      <%= if is_nil(@categoria_seleccionada) do %>
        <p style="font-size: 12px; font-weight: 700; color: #186904; margin: 0 0 12px; text-transform: uppercase; letter-spacing: 1px;">Categorías</p>
        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 14px;">
          <%= for cat <- @categorias do %>
            <div style="position: relative; border-radius: 22px; overflow: hidden; border: 1.5px solid #eef0ea; box-shadow: 0 6px 18px rgba(24,105,4,0.10); background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%);">
              <%= if cat.codigo_tipo != "99" do %>
                <button type="button" phx-click="abrir_modal_editar" phx-value-id={cat.id} style="position: absolute; top: 8px; left: 8px; z-index: 5; width: 26px; height: 26px; border-radius: 50%; background: white; border: 1px solid #eee; cursor: pointer; display: flex; align-items: center; justify-content: center; box-shadow: 0 2px 6px rgba(0,0,0,0.08);">
                  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
                </button>
              <% end %>

              <button type="button" phx-click="elegir_categoria" phx-value-tipo={cat.codigo_tipo} phx-value-nombre={cat.nombre} style="width: 100%; background: none; border: none; cursor: pointer; padding: 0; text-align: left;">
                <div style="aspect-ratio: 3/4; display: flex; align-items: center; justify-content: center; overflow: hidden;">
                  <%= if cat.imagen_url do %>
                    <img src={cat.imagen_url} style="width: 100%; height: 100%; object-fit: cover;" />
                  <% else %>
                    <svg width="55%" height="55%" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                      {raw(icono_svg(cat.icono))}
                    </svg>
                  <% end %>
                </div>
                <div style="padding: 10px 14px 14px;">
                  <p style="font-size: 14px; font-weight: 700; margin: 0; color: #111;"><%= cat.nombre %></p>
                </div>
              </button>
            </div>
          <% end %>

          <button type="button" phx-click="abrir_modal_categoria" style="border-radius: 22px; overflow: hidden; border: 1.5px dashed #d8dcd2; background: #fbfbf9; display: flex; flex-direction: column; cursor: pointer; padding: 0;">
            <div style="aspect-ratio: 3/4; display: flex; align-items: center; justify-content: center;">
              <span style="font-size: 40px; color: #bbb; font-weight: 300; line-height: 1;">+</span>
            </div>
            <div style="padding: 10px 14px 14px;">
              <p style="font-size: 14px; font-weight: 700; margin: 0; color: transparent; user-select: none;">.</p>
            </div>
          </button>
        </div>
      <% end %>

        </div>
        <div id="stock-panel-1" style="flex: 0 0 100%; min-width: 100%; scroll-snap-align: start; scroll-snap-stop: always; box-sizing: border-box; background: #ffffff; transform: translateZ(0);">
          <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 20px;">
            <p style="font-size: 26px; font-weight: 800; color: #186904; margin: 0;">Stock Inteligente</p>
            <.link navigate="/mi-tienda/stock/configuracion" style="background: none; border: none; padding: 0; cursor: pointer; display: flex; align-items: center; text-decoration: none;">
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                <circle cx="12" cy="12" r="3"/>
                <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>
              </svg>
            </.link>
          </div>

          <p style="font-size: 11px; font-weight: 700; color: #999; margin: 0 0 10px; text-transform: uppercase; letter-spacing: 1px; font-family: Poppins, sans-serif;">Gestión</p>

          <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 20px; padding: 14px; margin-bottom: 16px; box-shadow: 0 4px 14px rgba(24,105,4,0.10);">
            <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 12px; padding: 0 8px;">
              <p style="font-size: 11.5px; font-weight: 800; color: #186904; margin: 0; text-transform: uppercase; letter-spacing: 1.2px;">Bitácora</p>
              <div style="display: flex; align-items: center; gap: 6px;">
                <span style="font-size: 9.5px; font-weight: 800; color: #186904; background: #eef4ec; padding: 3px 8px; border-radius: 8px; text-transform: uppercase; letter-spacing: 0.6px;">Premium</span>
                <div style="position: relative; width: 24px; height: 24px;">
                  <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="pointer-events: none;">
                    <rect x="3" y="4" width="18" height="18" rx="3"/>
                    <line x1="16" y1="2" x2="16" y2="6"/>
                    <line x1="8" y1="2" x2="8" y2="6"/>
                    <line x1="3" y1="10" x2="21" y2="10"/>
                  </svg>
                  <form phx-change="filtrar_bitacora_fecha" style="position: absolute; top: 0; left: 0; margin: 0;">
                    <input type="date" id="input-fecha-bitacora" name="fecha" value={@fecha_filtro_bitacora} style="width: 24px; height: 24px; opacity: 0; cursor: pointer; border: none; padding: 0;" />
                  </form>
                </div>
                <%= if @fecha_filtro_bitacora do %>
                  <button type="button" phx-click="filtrar_bitacora_fecha" phx-value-fecha="" style="border: none; background: none; padding: 0; cursor: pointer; display: flex; align-items: center;">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
                  </button>
                <% end %>
              </div>
            </div>
            <div style="background: white; border-radius: 14px; padding: 8px; height: 220px; overflow-y: auto; -webkit-overflow-scrolling: touch; margin-bottom: 12px;">
              <%= if @movimientos_stock == [] do %>
                <div style="display: flex; align-items: center; justify-content: center; min-height: 204px; text-align: center;">
                  <p style="font-size: 14px; color: #999; margin: 0; font-family: Poppins, sans-serif; max-width: 220px;">Acá vas a ver qué cambió, cuándo y quién lo hizo.</p>
                </div>
              <% else %>
                <%
                  colores_bitacora = ["#E91E8C", "#186904", "#2b2b2b", "#0066cc", "#e67e22", "#8e44ad", "#c0392b", "#16a085"]
                %>
                <%= for mov <- @movimientos_stock do %>
                  <%
                    usuario_mov = mov.user_id && Map.get(@usuarios_bitacora, mov.user_id)
                    es_vos = mov.user_id && mov.user_id == @user_id
                    color_avatar = if usuario_mov, do: Enum.at(colores_bitacora, rem(usuario_mov.id, length(colores_bitacora))), else: "#bbb"
                    nombre_mov =
                      cond do
                        es_vos -> "Vos"
                        usuario_mov ->
                          apellido = usuario_mov.apellido_visible
                          nombre_p = usuario_mov.nombre_visible
                          cond do
                            apellido && apellido != "" && nombre_p && nombre_p != "" -> "#{nombre_p} #{apellido}"
                            nombre_p && nombre_p != "" -> nombre_p
                            true -> usuario_mov.name || "Alguien"
                          end
                        true -> "Alguien"
                      end
                  %>
                  <div style="display: flex; align-items: flex-start; gap: 12px; padding: 12px 8px; border-bottom: 1px solid #f2f2f2;">
                    <div style={"width: 40px; height: 40px; border-radius: 50%; background: #{color_avatar}; display: flex; align-items: flex-end; justify-content: center; overflow: hidden; flex-shrink: 0;"}>
                      <svg width="34" height="34" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">
                        <path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/>
                        <path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>
                      </svg>
                    </div>
                    <div style="flex: 1; min-width: 0;">
                      <div style="display: flex; align-items: baseline; justify-content: space-between; gap: 8px; margin: 0 0 3px;">
                        <p style="font-size: 13px; font-weight: 700; color: #111; margin: 0; font-family: Poppins, sans-serif;"><%= nombre_mov %></p>
                        <p style="font-size: 10.5px; color: #aaa; margin: 0; font-family: Poppins, sans-serif; white-space: nowrap; flex-shrink: 0;"><%= formato_fecha_movimiento(mov.inserted_at) %></p>
                      </div>
                      <p style="font-size: 13px; color: #555; margin: 0; font-family: Poppins, sans-serif;"><%= mov.descripcion %></p>
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>
            <.link navigate="/mi-tienda/stock/bitacora" style="display: block; width: 100%; text-align: center; background: none; border: 1.5px solid #186904; border-radius: 12px; padding: 10px 0; font-family: Poppins, sans-serif; font-weight: 700; font-size: 13px; color: #186904; text-decoration: none; box-sizing: border-box;">Bitácora detallada</.link>
          </div>

          <p style="font-size: 11px; font-weight: 700; color: #999; margin: 0 0 10px; text-transform: uppercase; letter-spacing: 1px; font-family: Poppins, sans-serif;">Datos de Mi Stock</p>

          <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 20px; padding: 14px; margin-bottom: 16px; box-shadow: 0 4px 14px rgba(24,105,4,0.10);">
            <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 12px; padding: 0 8px;">
              <p style="font-size: 11.5px; font-weight: 800; color: #186904; margin: 0; text-transform: uppercase; letter-spacing: 1.2px;">Más y Menos Vendido</p>
              <span style="font-size: 9.5px; font-weight: 800; color: #186904; background: #eef4ec; padding: 3px 8px; border-radius: 8px; text-transform: uppercase; letter-spacing: 0.6px;">Premium</span>
            </div>
            <p style="font-size: 11px; color: #999; margin: 10px 0 12px; padding: 0 8px; font-family: Poppins, sans-serif; line-height: 1.4;">Quién lidera el ranking de ventas y quién se está quedando atrás, según el período que elijas.</p>
            <div style="display: inline-flex; padding: 3px; background: #eef4ec; border-radius: 10px; gap: 3px; box-shadow: inset 0 1px 3px rgba(24,105,4,0.10); margin: 0 8px 14px;">
              <button type="button" phx-click="cambiar_periodo_ventas" phx-value-periodo="mensual" style={"padding: 6px 12px; border-radius: 8px; border: none; cursor: pointer; font-family: Poppins, sans-serif; font-size: 11px; font-weight: 700; transition: all 0.15s; background: #{if @periodo_ventas == "mensual", do: "#186904", else: "transparent"}; color: #{if @periodo_ventas == "mensual", do: "white", else: "#5c7a56"};"}>Mensual</button>
              <button type="button" phx-click="cambiar_periodo_ventas" phx-value-periodo="trimestral" style={"padding: 6px 12px; border-radius: 8px; border: none; cursor: pointer; font-family: Poppins, sans-serif; font-size: 11px; font-weight: 700; transition: all 0.15s; background: #{if @periodo_ventas == "trimestral", do: "#186904", else: "transparent"}; color: #{if @periodo_ventas == "trimestral", do: "white", else: "#5c7a56"};"}>Trimestral</button>
              <button type="button" phx-click="cambiar_periodo_ventas" phx-value-periodo="anual" style={"padding: 6px 12px; border-radius: 8px; border: none; cursor: pointer; font-family: Poppins, sans-serif; font-size: 11px; font-weight: 700; transition: all 0.15s; background: #{if @periodo_ventas == "anual", do: "#186904", else: "transparent"}; color: #{if @periodo_ventas == "anual", do: "white", else: "#5c7a56"};"}>Anual</button>
            </div>
            <div style="background: white; border-radius: 14px; padding: 12px;">
              <p style="font-size: 10.5px; font-weight: 800; color: #999; margin: 0 0 10px; text-transform: uppercase; letter-spacing: 0.8px; font-family: Poppins, sans-serif;">Más Vendido</p>
              <%= if @top_vendidos == [] do %>
                <div style="display: flex; align-items: center; justify-content: center; min-height: 100px; text-align: center;">
                  <p style="font-size: 13px; color: #999; margin: 0; font-family: Poppins, sans-serif; max-width: 220px;">Todavía no hay ventas registradas.</p>
                </div>
              <% else %>
                <%= for {item, i} <- Enum.with_index(@top_vendidos) do %>
                  <div style={"display: flex; align-items: center; gap: 10px; padding: 9px 4px; #{if i < length(@top_vendidos) - 1, do: "border-bottom: 1px solid #f2f2f2;", else: ""}"}>
                    <div style="width: 18px; flex-shrink: 0; display: flex; align-items: center; justify-content: center;">
                      <%= cond do %>
                        <% i == 0 -> %>
                          <div id="corona-oro-mas-vendido" phx-hook=".BrilloCoronaOro" style="display: flex; align-items: center; justify-content: center;">
                            <svg width="16" height="16" viewBox="0 0 24 24" fill="#f5b301" stroke="#f5b301"><path d="M2 18h20l-2-9-5 4-3-7-3 7-5-4-2 9z"/></svg>
                          </div>
                        <% i == 1 -> %>
                          <svg width="16" height="16" viewBox="0 0 24 24" fill="#b0b0b0" stroke="#b0b0b0"><path d="M2 18h20l-2-9-5 4-3-7-3 7-5-4-2 9z"/></svg>
                        <% i == 2 -> %>
                          <svg width="16" height="16" viewBox="0 0 24 24" fill="#c17a3f" stroke="#c17a3f"><path d="M2 18h20l-2-9-5 4-3-7-3 7-5-4-2 9z"/></svg>
                        <% true -> %>
                          <span style="font-size: 12px; font-weight: 800; color: #186904;"><%= i + 1 %></span>
                      <% end %>
                    </div>
                    <style>
                      @keyframes coronaBrilloPulso {
                        0% { transform: scale(1); filter: drop-shadow(0 0 0 rgba(245,179,1,0)); }
                        50% { transform: scale(1.4); filter: drop-shadow(0 0 8px rgba(245,179,1,0.9)); }
                        100% { transform: scale(1); filter: drop-shadow(0 0 0 rgba(245,179,1,0)); }
                      }
                      .corona-brillo-activa { animation: coronaBrilloPulso 0.9s ease; }
                    </style>
                    <script :type={Phoenix.LiveView.ColocatedHook} name=".BrilloCoronaOro">
                      export default {
                        mounted() {
                          var el = this.el;
                          var yaAnimado = false;
                          var observer = new IntersectionObserver(function(entries) {
                            entries.forEach(function(entry) {
                              if (entry.isIntersecting && !yaAnimado) {
                                yaAnimado = true;
                                el.classList.add('corona-brillo-activa');
                                setTimeout(function() { el.classList.remove('corona-brillo-activa'); }, 900);
                              }
                            });
                          }, { threshold: 0.6 });
                          observer.observe(el);
                        }
                      }
                    </script>
                    <p style="font-size: 13.5px; font-weight: 600; color: #111; margin: 0; font-family: Poppins, sans-serif; flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;"><%= item.producto_nombre %></p>
                    <span style="font-size: 11.5px; font-weight: 700; color: #186904; background: #eef4ec; padding: 3px 9px; border-radius: 8px; flex-shrink: 0;"><%= item.cantidad %> <%= if item.cantidad == 1, do: "venta", else: "ventas" %></span>
                  </div>
                <% end %>
              <% end %>

              <div style="height: 1px; background: #eee; margin: 14px 4px;"></div>

              <p style="font-size: 10.5px; font-weight: 800; color: #999; margin: 0 0 10px; text-transform: uppercase; letter-spacing: 0.8px; font-family: Poppins, sans-serif;">Menos Vendido</p>
              <%= if @menos_vendidos == [] do %>
                <div style="display: flex; align-items: center; justify-content: center; min-height: 60px; text-align: center;">
                  <p style="font-size: 13px; color: #999; margin: 0; font-family: Poppins, sans-serif; max-width: 220px;">Todos tus productos activos tuvieron al menos una venta.</p>
                </div>
              <% else %>
                <%= for {producto, i} <- Enum.with_index(@menos_vendidos) do %>
                  <div style={"display: flex; align-items: center; gap: 10px; padding: 9px 4px; #{if i < length(@menos_vendidos) - 1, do: "border-bottom: 1px solid #f2f2f2;", else: ""}"}>
                    <p style="font-size: 13.5px; font-weight: 600; color: #111; margin: 0; font-family: Poppins, sans-serif; flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;"><%= producto.name %></p>
                    <span style="font-size: 11.5px; font-weight: 700; color: #c0392b; background: #fdecea; padding: 3px 9px; border-radius: 8px; flex-shrink: 0;">0 ventas</span>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>

          <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 20px; padding: 14px; margin-bottom: 16px; box-shadow: 0 4px 14px rgba(24,105,4,0.10);">
            <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 4px; padding: 0 8px;">
              <p style="font-size: 11.5px; font-weight: 800; color: #186904; margin: 0; text-transform: uppercase; letter-spacing: 1.2px;">Menos Rotación</p>
              <span style="font-size: 9.5px; font-weight: 800; color: #186904; background: #eef4ec; padding: 3px 8px; border-radius: 8px; text-transform: uppercase; letter-spacing: 0.6px;">Premium</span>
            </div>
            <p style="font-size: 11px; color: #999; margin: 10px 0 14px; padding: 0 8px; font-family: Poppins, sans-serif; line-height: 1.4;">Productos que llevan más tiempo sin venderse. Capaz conviene bajarles el precio o sacarlos de la vidriera.</p>
            <div style="background: white; border-radius: 14px; padding: 16px 10px 12px;">
              <%= if @menos_rotacion == [] do %>
                <div style="display: flex; align-items: center; justify-content: center; min-height: 120px; text-align: center;">
                  <p style="font-size: 13px; color: #999; margin: 0; font-family: Poppins, sans-serif; max-width: 220px;">Ningún producto lleva más de 30 días sin venderse. ¡Buena señal!</p>
                </div>
              <% else %>
                <%
                  max_dias = @menos_rotacion |> List.first() |> Map.get(:dias)
                  max_dias = if max_dias > 0, do: max_dias, else: 1
                %>
                <div style="display: flex; align-items: flex-end; justify-content: space-around; gap: 12px; padding: 38px 6px 0;">
                  <%= for item <- @menos_rotacion do %>
                    <% alto_px = max(56, round(item.dias / max_dias * 120)) %>
                    <div style="display: flex; flex-direction: column; align-items: center; flex: 1; min-width: 0; max-width: 58px;">
                      <div style="position: relative; width: 100%;">
                        <span style="position: absolute; top: -24px; left: 50%; transform: translateX(-50%); font-size: 12px; font-weight: 800; color: #186904; font-family: Poppins, sans-serif; white-space: nowrap;"><%= item.dias %>d</span>
                        <div style={"width: 100%; height: #{alto_px}px; background: #186904; border-radius: 14px 14px 6px 6px; box-shadow: 0 4px 10px rgba(24,105,4,0.22);"}></div>
                        <div style="position: absolute; bottom: -14px; left: 50%; transform: translateX(-50%); width: 36px; height: 36px; border-radius: 50%; overflow: hidden; background: white; border: 2.5px solid white; box-shadow: 0 2px 6px rgba(0,0,0,0.15);">
                          <%= if item.producto.image do %>
                            <img src={item.producto.image} style="width: 100%; height: 100%; object-fit: cover;" />
                          <% else %>
                            <div style={"width: 100%; height: 100%; display: flex; align-items: center; justify-content: center; background: #{color_hex_por_codigo(item.codigo_color)};"}>
                              <svg width="60%" height="60%" viewBox="0 0 24 24" fill="none" stroke={if item.codigo_color == "21", do: "#333", else: "white"} stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                                {raw(icono_svg_por_codigo(item.producto.codigo_tipo, @categorias))}
                              </svg>
                            </div>
                          <% end %>
                        </div>
                      </div>
                      <span style="margin-top: 22px; font-size: 9.5px; font-weight: 700; color: #186904; background: #eef4ec; padding: 2px 7px; border-radius: 6px;"><%= DaleApp.Products.StockItem.nombre_talle(item.codigo_talle) %></span>
                    </div>
                  <% end %>
                </div>
                <p style="text-align: center; font-size: 10px; color: #bbb; margin: 8px 0 0; font-family: Poppins, sans-serif;">días sin ventas</p>
              <% end %>
            </div>
          </div>

          <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 20px; padding: 14px; margin-bottom: 16px; box-shadow: 0 4px 14px rgba(24,105,4,0.10);">
            <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 4px; padding: 0 8px;">
              <p style="font-size: 11.5px; font-weight: 800; color: #186904; margin: 0; text-transform: uppercase; letter-spacing: 1.2px;">Sell-Through</p>
              <span style="font-size: 9.5px; font-weight: 800; color: #186904; background: #eef4ec; padding: 3px 8px; border-radius: 8px; text-transform: uppercase; letter-spacing: 0.6px;">Premium</span>
            </div>
            <p style="font-size: 11px; color: #999; margin: 10px 0 14px; padding: 0 8px; font-family: Poppins, sans-serif; line-height: 1.4;">Qué porcentaje de lo que tenés cargado ya se vendió en los últimos 30 días.</p>
            <div style="background: white; border-radius: 14px; padding: 20px 16px;">
              <%
                {color_barra, etiqueta_estado} =
                  cond do
                    @sell_through.porcentaje < 40 -> {"#c0392b", "Bajo — revisá qué no está rotando"}
                    @sell_through.porcentaje < 65 -> {"#a67c00", "Medio — puede mejorar"}
                    @sell_through.porcentaje <= 85 -> {"#186904", "Saludable"}
                    true -> {"#1565c0", "Muy alto — capaz te falta stock"}
                  end
              %>
              <div style="display: flex; align-items: baseline; gap: 6px; margin-bottom: 10px;">
                <span style={"font-size: 34px; font-weight: 800; color: #{color_barra}; font-family: Poppins, sans-serif;"}><%= @sell_through.porcentaje %></span>
                <span style={"font-size: 18px; font-weight: 800; color: #{color_barra};"}>%</span>
              </div>
              <div style="width: 100%; height: 10px; background: #f0f0f0; border-radius: 6px; overflow: hidden; margin-bottom: 10px;">
                <div style={"width: #{min(@sell_through.porcentaje, 100)}%; height: 100%; background: #{color_barra}; border-radius: 6px; transition: width 0.3s;"}></div>
              </div>
              <p style={"font-size: 12.5px; font-weight: 700; color: #{color_barra}; margin: 0 0 10px; font-family: Poppins, sans-serif;"}><%= etiqueta_estado %></p>
              <p style="font-size: 11px; color: #999; margin: 0; font-family: Poppins, sans-serif;"><%= @sell_through.vendidas %> vendidas de <%= @sell_through.vendidas + @sell_through.stock_actual %> unidades disponibles este mes</p>

              <button type="button" phx-click="toggle_consejos_sell_through" style="width: 100%; margin-top: 14px; background: #eef4ec; color: #186904; border: none; border-radius: 12px; padding: 11px 0; font-size: 13px; font-weight: 700; font-family: Poppins, sans-serif; cursor: pointer;">
                <%= if @mostrar_consejos_sell_through, do: "Ocultar", else: "¿Y ahora qué hago?" %>
              </button>

              <%= if @mostrar_consejos_sell_through do %>
                <div style="margin-top: 12px; display: flex; flex-direction: column; gap: 8px;">
                  <%= cond do %>
                    <% @sell_through.porcentaje < 40 -> %>
                      <p style="font-size: 12.5px; color: #555; margin: 0; font-family: Poppins, sans-serif; line-height: 1.5;">→ Mirá la ficha "Menos Rotación" de acá arriba y bajale el precio a lo que hace más de 30 días que no se mueve.</p>
                      <p style="font-size: 12.5px; color: #555; margin: 0; font-family: Poppins, sans-serif; line-height: 1.5;">→ Activá el "Ocultamiento automático" en Configuración de stock para que lo que no tiene unidades no le ocupe lugar a lo que sí vende en tu vidriera, o reemplazá productos por otros en tu stand.</p>
                      <p style="font-size: 12.5px; color: #555; margin: 0; font-family: Poppins, sans-serif; line-height: 1.5;">→ Si tus fotos no son buenas, esa es la primera razón por la que no se venden. Mejorá las fotos antes que nada.</p>
                    <% @sell_through.porcentaje < 65 -> %>
                      <p style="font-size: 12.5px; color: #555; margin: 0; font-family: Poppins, sans-serif; line-height: 1.5;">→ Revisá qué talles se están quedando estancados en "Menos Rotación" antes de pedir más del mismo talle la próxima vez.</p>
                      <p style="font-size: 12.5px; color: #555; margin: 0; font-family: Poppins, sans-serif; line-height: 1.5;">→ Vas bien, pero todavía hay margen. Fijate en "Menos Vendido" cuáles productos no arrancaron y pensá si conviene bajarles el precio.</p>
                    <% @sell_through.porcentaje <= 85 -> %>
                      <p style="font-size: 12.5px; color: #555; margin: 0; font-family: Poppins, sans-serif; line-height: 1.5;">→ Vas bien. Anotá qué funcionó este mes (mirá "Más Vendido") para repetirlo en tu próximo pedido a proveedores.</p>
                      <p style="font-size: 12.5px; color: #555; margin: 0; font-family: Poppins, sans-serif; line-height: 1.5;">→ Este es el rango sano de la industria. No hace falta tocar nada, solo sostenerlo.</p>
                    <% true -> %>
                      <p style="font-size: 12.5px; color: #555; margin: 0; font-family: Poppins, sans-serif; line-height: 1.5;">→ Estás vendiendo casi todo lo que tenés. Puede que estés perdiendo ventas por falta de stock — mirá "Poco stock" en Panorama y reponé pronto.</p>
                      <p style="font-size: 12.5px; color: #555; margin: 0; font-family: Poppins, sans-serif; line-height: 1.5;">→ Considerá pedirle más cantidad al proveedor de lo que ya sabés que se vende rápido.</p>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>

          <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 20px; padding: 14px; margin-bottom: 16px; box-shadow: 0 4px 14px rgba(24,105,4,0.10);">
            <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 4px; padding: 0 8px;">
              <p style="font-size: 11.5px; font-weight: 800; color: #186904; margin: 0; text-transform: uppercase; letter-spacing: 1.2px;">Talles Incompletos</p>
              <span style="font-size: 9.5px; font-weight: 800; color: #186904; background: #eef4ec; padding: 3px 8px; border-radius: 8px; text-transform: uppercase; letter-spacing: 0.6px;">Premium</span>
            </div>
            <p style="font-size: 11px; color: #999; margin: 10px 0 12px; padding: 0 8px; font-family: Poppins, sans-serif; line-height: 1.4;">Productos a los que ya se les fueron ciertos talles. Un cliente que busca justo ese talle se va sin comprar.</p>

            <div style="display: flex; gap: 6px; padding: 0 8px; margin-bottom: 12px;">
              <button type="button" phx-click="cambiar_orden_talles_incompletos" phx-value-orden="severidad" style={"padding: 6px 12px; border-radius: 8px; border: 1.5px solid #{if @orden_talles_incompletos == "severidad", do: "#186904", else: "#e0e0e0"}; background: #{if @orden_talles_incompletos == "severidad", do: "#186904", else: "white"}; color: #{if @orden_talles_incompletos == "severidad", do: "white", else: "#555"}; cursor: pointer; font-family: Poppins, sans-serif; font-size: 11px; font-weight: 700;"}>Más faltantes</button>
              <button type="button" phx-click="cambiar_orden_talles_incompletos" phx-value-orden="vendido" style={"padding: 6px 12px; border-radius: 8px; border: 1.5px solid #{if @orden_talles_incompletos == "vendido", do: "#186904", else: "#e0e0e0"}; background: #{if @orden_talles_incompletos == "vendido", do: "#186904", else: "white"}; color: #{if @orden_talles_incompletos == "vendido", do: "white", else: "#555"}; cursor: pointer; font-family: Poppins, sans-serif; font-size: 11px; font-weight: 700;"}>Más vendido</button>
              <button type="button" phx-click="cambiar_orden_talles_incompletos" phx-value-orden="precio" style={"padding: 6px 12px; border-radius: 8px; border: 1.5px solid #{if @orden_talles_incompletos == "precio", do: "#186904", else: "#e0e0e0"}; background: #{if @orden_talles_incompletos == "precio", do: "#186904", else: "white"}; color: #{if @orden_talles_incompletos == "precio", do: "white", else: "#555"}; cursor: pointer; font-family: Poppins, sans-serif; font-size: 11px; font-weight: 700;"}>Precio</button>
            </div>

            <div style="background: white; border-radius: 14px; padding: 8px;">
              <%= if @talles_incompletos_lista == [] do %>
                <div style="display: flex; align-items: center; justify-content: center; min-height: 90px; text-align: center;">
                  <p style="font-size: 13px; color: #999; margin: 0; font-family: Poppins, sans-serif; max-width: 220px;">Todos tus productos tienen todos sus talles disponibles. ¡Buena señal!</p>
                </div>
              <% else %>
                <div style="position: relative;">
                  <div id="lista-talles-incompletos" phx-hook=".BarritaScrollTalles" style="height: 320px; overflow-y: scroll; -webkit-overflow-scrolling: touch; box-sizing: border-box; padding-right: 10px;">
                <%= for {item, i} <- Enum.with_index(@talles_incompletos_lista) do %>
                  <div style={"display: flex; align-items: center; gap: 10px; padding: 10px 4px; #{if i < length(@talles_incompletos_lista) - 1, do: "border-bottom: 1px solid #f2f2f2;", else: ""}"}>
                    <div style="width: 34px; height: 34px; border-radius: 8px; overflow: hidden; background: #f0f0f0; flex-shrink: 0;">
                      <%= if item.producto.image do %>
                        <img src={item.producto.image} style="width: 100%; height: 100%; object-fit: cover;" />
                      <% else %>
                        <div style="width: 100%; height: 100%; display: flex; align-items: center; justify-content: center; background: #e6f4e6;">
                          <span style="font-size: 12px; font-weight: 800; color: #186904;"><%= String.first(item.producto.name || "?") %></span>
                        </div>
                      <% end %>
                    </div>
                    <div style="flex: 1; min-width: 0;">
                      <div style="display: flex; align-items: center; justify-content: space-between; gap: 6px; margin-bottom: 4px;">
                        <p style="font-size: 12.5px; font-weight: 700; color: #111; margin: 0; font-family: Poppins, sans-serif; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; display: flex; align-items: center; gap: 6px; min-width: 0;">
                          <span style={"width: 9px; height: 9px; border-radius: 50%; background: #{color_hex_por_codigo(item.codigo_color)}; flex-shrink: 0; #{if item.codigo_color == "21", do: "border: 1.5px solid #222;", else: ""}"}></span>
                          <span style="overflow: hidden; text-overflow: ellipsis;"><%= item.producto.name %></span>
                        </p>
                        <span style="font-size: 10.5px; font-weight: 700; color: #186904; flex-shrink: 0;">$<%= formatear_precio(item.producto.price) %></span>
                      </div>
                      <div style="display: flex; flex-wrap: wrap; gap: 4px;">
                        <%= for talle <- item.talles do %>
                          <% {bg_t, texto_t} = if talle.cantidad > 0, do: {"#e6f4e6", "#186904"}, else: {"#fdecea", "#c0392b"} %>
                          <span style={"font-size: 10px; font-weight: 700; padding: 2px 6px; border-radius: 6px; background: #{bg_t}; color: #{texto_t};"}><%= StockItem.nombre_talle(talle.codigo_talle) %></span>
                        <% end %>
                      </div>
                    </div>
                  </div>
                <% end %>
                <div id="centinela-talles-incompletos" phx-hook=".CentinelaTallesIncompletos"></div>
                  </div>
                  <div style="position: absolute; top: 0; right: 0; bottom: 0; width: 4px; background: #f0f0f0; border-radius: 10px;">
                    <div id="pulgar-scroll-talles" style="position: absolute; top: 0; left: 0; width: 100%; background: #186904; border-radius: 10px; transition: top 0.05s linear;"></div>
                  </div>
                </div>
                <script :type={Phoenix.LiveView.ColocatedHook} name=".BarritaScrollTalles">
                  export default {
                    mounted() {
                      var el = this.el;
                      var pulgar = document.getElementById('pulgar-scroll-talles');

                      function actualizar() {
                        if (!pulgar) return;
                        var scrollH = el.scrollHeight;
                        var clientH = el.clientHeight;
                        if (scrollH <= clientH) {
                          pulgar.style.height = '100%';
                          pulgar.style.top = '0';
                          return;
                        }
                        var pctAlto = clientH / scrollH;
                        var pctTop = el.scrollTop / scrollH;
                        pulgar.style.height = (pctAlto * 100) + '%';
                        pulgar.style.top = (pctTop * 100) + '%';
                      }

                      el.addEventListener('scroll', actualizar);
                      actualizar();

                      this.updated = actualizar;
                    }
                  }
                </script>
              <% end %>
            </div>

            <script :type={Phoenix.LiveView.ColocatedHook} name=".CentinelaTallesIncompletos">
              export default {
                mounted() {
                  var el = this.el;
                  var pushEventFn = this.pushEvent.bind(this);
                  var observer = new IntersectionObserver(function(entries) {
                    entries.forEach(function(entry) {
                      if (entry.isIntersecting) {
                        pushEventFn("cargar_mas_talles_incompletos", {});
                      }
                    });
                  }, { root: el.closest('[style*="overflow-y: auto"]'), threshold: 0.1 });
                  observer.observe(el);
                }
              }
            </script>

            <div style="height: 1px; background: #eee; margin: 16px 4px;"></div>

            <p style="font-size: 10.5px; font-weight: 800; color: #999; margin: 0 0 10px; padding: 0 8px; text-transform: uppercase; letter-spacing: 0.8px; font-family: Poppins, sans-serif;">Rendimiento por talle</p>
            <div style="display: flex; gap: 6px; flex-wrap: wrap; padding: 0 8px; margin-bottom: 14px;">
              <%= for {codigo, nombre, _total} <- @talles_totales do %>
                <button type="button" phx-click="seleccionar_talla_rendimiento" phx-value-talla={codigo} style={"padding: 7px 13px; border-radius: 20px; border: 1.5px solid #{if @talla_seleccionada_rendimiento == codigo, do: "#186904", else: "#e0e0e0"}; background: #{if @talla_seleccionada_rendimiento == codigo, do: "#186904", else: "white"}; color: #{if @talla_seleccionada_rendimiento == codigo, do: "white", else: "#555"}; cursor: pointer; font-family: Poppins, sans-serif; font-size: 12px; font-weight: 700;"}><%= nombre %></button>
              <% end %>
            </div>

            <div style="background: white; border-radius: 14px; padding: 16px 10px;">
              <%
                total_comparacion = @rendimiento_talla.stock_actual + @rendimiento_talla.vendidas
                {pct_stock, pct_vendidas} =
                  if total_comparacion > 0 do
                    ps = round(@rendimiento_talla.stock_actual / total_comparacion * 100)
                    {ps, 100 - ps}
                  else
                    {0, 0}
                  end
              %>
              <div style="display: flex; align-items: flex-end; justify-content: center; gap: 24px; height: 110px; margin-bottom: 12px;">
                <div style="display: flex; flex-direction: column; align-items: center; gap: 6px;">
                  <span style="font-size: 11px; font-weight: 800; color: #555; font-family: Poppins, sans-serif;"><%= @rendimiento_talla.stock_actual %></span>
                  <div style={"width: 44px; background: #ccc; height: #{if @rendimiento_talla.stock_actual == 0, do: 4, else: max(10, round(pct_stock * 0.9))}px; border-radius: 8px 8px 4px 4px;"}></div>
                  <span style="font-size: 10px; color: #999; font-family: Poppins, sans-serif;">En stock</span>
                </div>
                <div style="display: flex; flex-direction: column; align-items: center; gap: 6px;">
                  <span style="font-size: 11px; font-weight: 800; color: #186904; font-family: Poppins, sans-serif;"><%= @rendimiento_talla.vendidas %></span>
                  <div style={"width: 44px; background: #186904; height: #{if @rendimiento_talla.vendidas == 0, do: 4, else: max(10, round(pct_vendidas * 0.9))}px; border-radius: 8px 8px 4px 4px;"}></div>
                  <span style="font-size: 10px; color: #999; font-family: Poppins, sans-serif;">Vendidas</span>
                </div>
              </div>
              <p style="text-align: center; font-size: 11.5px; color: #666; margin: 0; font-family: Poppins, sans-serif;">De todo lo que pasó por este talle, se vendió el <strong style="color: #186904;"><%= pct_vendidas %>%</strong></p>
            </div>
          </div>
        </div>
      </div>
      <script>
        (function() {
          var slider = document.getElementById('stock-slider');
          var dots = [document.getElementById('punto-slider-stock-0'), document.getElementById('punto-slider-stock-1')];
          if (slider && !slider.dataset.sliderInit) {
            slider.dataset.sliderInit = "1";

            if ("<%= @panel_inicial %>" === "avanzado") {
              slider.scrollLeft = slider.clientWidth;
            }

            slider.addEventListener('scroll', function() {
              var maxScroll = slider.scrollWidth - slider.clientWidth;
              var frac = maxScroll > 0 ? Math.min(1, Math.max(0, slider.scrollLeft / maxScroll)) : 0;
              var idx = Math.round(frac);
              dots.forEach(function(d, i) {
                if (d) d.classList.toggle('activo', i === idx);
              });

              var url = new URL(window.location.href);
              if (idx === 1) {
                url.searchParams.set('panel', 'avanzado');
              } else {
                url.searchParams.delete('panel');
              }
              window.history.replaceState({}, '', url);
            });
          }
        })();
      </script>
      <% end %>
      <%= if @mostrar_modal_talle do %>
        <div style="position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.45); z-index: 9999; display: flex; align-items: center; justify-content: center;">
          <div style="background: #fff; border-radius: 24px; width: 300px; max-width: 88%; padding: 24px 20px; box-shadow: 0 12px 40px rgba(0,0,0,0.25);">
            <p style="font-size: 18px; font-weight: 700; color: #186904; margin: 0 0 14px; text-align: center;">Nuevo talle</p>
            <form phx-submit="crear_talle">
              <input type="text" name="nombre" placeholder="Ej: 38, Único, 2XL" autocomplete="off" style="width: 100%; box-sizing: border-box; padding: 12px 14px; border: 1.5px solid #e0e0e0; border-radius: 14px; font-family: Poppins, sans-serif; font-size: 14px; outline: none; margin-bottom: 12px;" />
              <%= if @error_talle do %>
                <p style="color: #c0392b; font-size: 12px; margin: 0 0 10px; font-family: Poppins, sans-serif;"><%= @error_talle %></p>
              <% end %>
              <button type="submit" style="width: 100%; background: #186904; color: white; border: none; border-radius: 14px; padding: 12px 0; font-size: 14px; font-weight: 700; font-family: Poppins, sans-serif; cursor: pointer;">Crear talle</button>
            </form>
            <button type="button" phx-click="cerrar_modal_talle" style="width: 100%; margin-top: 8px; background: none; color: #999; border: none; padding: 8px 0; font-size: 13px; font-family: Poppins, sans-serif; cursor: pointer;">Cancelar</button>
          </div>
        </div>
      <% end %>

      <%= if @categoria_seleccionada && !@mostrar_formulario_producto do %>
        <button type="button" phx-click="abrir_formulario_producto" style="width: 100%; display: flex; align-items: center; gap: 12px; padding: 16px; border: 1.5px solid #186904; border-radius: 16px; background: white; cursor: pointer; font-size: 15px; font-weight: 600; color: #186904; margin-bottom: 24px;">
          <span style="font-size: 28px; line-height: 1; font-weight: 300;">+</span>
          Crear producto en <%= @categoria_seleccionada.nombre %>
        </button>
      <% end %>

      <%= if @categoria_seleccionada && !@mostrar_formulario_producto do %>
        <%= for {nombre_articulo, filas} <- filas_de_categoria(@productos_todos, @categoria_seleccionada.codigo) do %>
          <div phx-click="editar_articulo" phx-value-nombre={nombre_articulo} style="display: flex; flex-direction: column; gap: 10px; margin-bottom: 18px; cursor: pointer;">
            <%= for fila <- filas do %>
              <div style="display: flex; align-items: center; gap: 12px; padding: 10px; border: 1px solid #eee; border-radius: 14px; background: white;">
                <div style="width: 52px; height: 52px; border-radius: 10px; overflow: hidden; background: #f5f5f5; flex-shrink: 0; display: flex; align-items: center; justify-content: center; position: relative;">
                  <%= if fila.producto.image do %>
                    <img src={fila.producto.image} style="width: 100%; height: 100%; object-fit: cover;" />
                  <% else %>
                    <svg width="55%" height="55%" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" style="opacity: 0.5;">
                      {raw(icono_svg_por_codigo(@categoria_seleccionada.codigo, @categorias))}
                    </svg>
                  <% end %>
                  <%= if fila.codigo_color do %>
                    <span style={"position: absolute; bottom: 2px; right: 2px; width: 12px; height: 12px; border-radius: 50%; background: #{color_hex_por_codigo(fila.codigo_color)}; border: 1.5px solid white; box-shadow: 0 1px 3px rgba(0,0,0,0.25);"}></span>
                  <% end %>
                </div>
                <div style="flex: 1; min-width: 0;">
                  <p style="margin: 0 0 6px; font-size: 14px; font-weight: 700; color: #222; font-family: Poppins, sans-serif; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">
                    <%= nombre_articulo %>
                  </p>
                  <div style="display: flex; flex-wrap: wrap; gap: 5px;">
                    <%= if fila.talles == [] do %>
                      <span style="font-size: 11px; color: #bbb; font-family: Poppins, sans-serif;">Sin talles cargados</span>
                    <% end %>
                    <%= for {codigo_talle, cantidad} <- fila.talles do %>
                      <% {bg, texto} = estado_talle(cantidad, @brand.umbral_poco_stock) %>
                      <span style={"font-size: 11px; font-weight: 700; padding: 3px 8px; border-radius: 8px; background: #{bg}; color: #{texto}; font-family: Poppins, sans-serif;"}>
                        <%= StockItem.nombre_talle(codigo_talle) %>
                      </span>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      <% end %>

      <%= if @categoria_seleccionada && @mostrar_formulario_producto do %>
        <div id="form-producto-stock" phx-hook=".FormularioProductoStock" data-codigo-tipo={@categoria_seleccionada && @categoria_seleccionada.codigo} data-numero-preview={@categoria_seleccionada && @categoria_seleccionada.numero_preview} data-articulo={if @articulo_editando, do: Jason.encode!(@articulo_editando), else: ""} data-mostrar-imprimir={to_string(@mostrar_pantalla_imprimir)} data-combo-destacado={@combo_destacado_stock || ""} data-dalestand-fijo={to_string(@categoria_seleccionada && @categoria_seleccionada.codigo == "99")} style="margin-bottom: 24px;">
          <div id="contenido-formulario-producto-stock" style={"display: #{if @mostrar_pantalla_imprimir, do: "none", else: "block"};"}>
          <div style="border-radius: 16px; overflow: hidden; border: 1px solid #f2f2f2; position: relative; box-shadow: 0 3px 10px rgba(0,0,0,0.06); margin-bottom: 16px;">
            <div id="caja-foto-stock" style="aspect-ratio: 16/9; background: #f0f0f0; position: relative; overflow: hidden; transition: aspect-ratio 0.2s;">
              <img id="preview-img-fondo-stock" src={@articulo_editando && @articulo_editando.imagen} style={"position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; filter: blur(20px) brightness(0.8); transform: scale(1.15); display: #{if @articulo_editando && @articulo_editando.imagen, do: "block", else: "none"};"}/>
              <img id="preview-img-stock" src={@articulo_editando && @articulo_editando.imagen} style={"position: relative; width: 100%; height: 100%; object-fit: contain; display: #{if @articulo_editando && @articulo_editando.imagen, do: "block", else: "none"};"}/>
              <div id="preview-placeholder-stock" style={"width: 100%; height: 100%; display: #{if @articulo_editando && @articulo_editando.imagen, do: "none", else: "flex"}; align-items: center; justify-content: center; cursor: pointer;"} onclick="document.getElementById('file-input-stock').click()">
                <svg width="20%" height="20%" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" style="opacity: 0.5;">
                  <%= if @categoria_seleccionada do %>
                    {raw(icono_svg_por_codigo(@categoria_seleccionada.codigo, @categorias))}
                  <% end %>
                </svg>
              </div>
              <input type="file" id="file-input-stock" accept="image/*" style="display: none;" onchange="previsualizarImagenStock(this)"/>
            </div>
            <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); padding: 10px 14px; border-top: 1.5px solid #d9ead9;">
              <p id="prev-nombre-stock" style="font-size: 13px; font-weight: 700; margin: 0; color: #111; min-height: 16px;"><%= @articulo_editando && @articulo_editando.nombre %></p>
              <p id="prev-precio-stock" style="font-size: 14px; font-weight: 800; color: #186904; margin: 2px 0 0; min-height: 17px;"><%= if @articulo_editando && @articulo_editando.precio, do: "$" <> formatear_precio(@articulo_editando.precio) %></p>
            </div>
          </div>

          <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 18px; padding: 18px; box-shadow: 0 4px 14px rgba(24,105,4,0.10);">
            <p style="font-size: 12.5px; font-weight: 700; color: #186904; margin: 0 0 6px;">Nombre del producto</p>
            <input id="input-nombre-stock" type="text" placeholder="Ej: Buzo oversize" value={@articulo_editando && @articulo_editando.nombre} oninput="actualizarPreviewStock()" style="width: 100%; padding: 13px 16px; border: 1.5px solid #cfe4cf; border-radius: 16px; font-family: Poppins, sans-serif; font-size: 14px; box-sizing: border-box; outline: none; background: white;"/>

            <p style="font-size: 12.5px; font-weight: 700; color: #186904; margin: 16px 0 6px;">Precio del producto</p>
            <input id="input-precio-stock" type="number" placeholder="$" value={@articulo_editando && @articulo_editando.precio} oninput="actualizarPreviewStock()" style="width: 100%; padding: 13px 16px; border: 1.5px solid #cfe4cf; border-radius: 16px; font-family: Poppins, sans-serif; font-size: 14px; box-sizing: border-box; outline: none; background: white;"/>

            <p style="font-size: 12.5px; font-weight: 700; color: #186904; margin: 16px 0 6px;">Descripción (opcional)</p>
            <textarea id="input-descripcion-stock" placeholder="Detalles del producto" oninput="limitarPalabrasStock(this); this.style.height='auto'; this.style.height=(this.scrollHeight)+'px';" style="width: 100%; padding: 13px 16px; border: 1.5px solid #cfe4cf; border-radius: 16px; font-family: Poppins, sans-serif; font-size: 14px; box-sizing: border-box; resize: none; height: 70px; min-height: 70px; outline: none; background: white; overflow: hidden;"><%= @articulo_editando && @articulo_editando.descripcion %></textarea>
            <p id="contador-palabras-stock" style="font-size: 11px; color: #aaa; margin: 4px 0 0; text-align: right; font-family: Poppins, sans-serif;">0/500 palabras</p>
          </div>

          <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 18px; padding: 18px; box-shadow: 0 4px 14px rgba(24,105,4,0.10); margin-top: 16px;">
            <%
              talles_seleccionados_editando =
                if @articulo_editando do
                  @articulo_editando.variantes
                  |> Map.keys()
                  |> Enum.map(fn clave -> clave |> String.split("_") |> List.last() end)
                  |> Enum.uniq()
                else
                  []
                end
              multi_talle_activo_editando = length(talles_seleccionados_editando) > 1
            %>
            <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 20px;">
              <p style="font-size: 12.5px; font-weight: 700; color: #186904; margin: 0;">Talles</p>
              <div style="display: flex; align-items: center; gap: 8px;">
                <span style="font-size: 11px; color: #888; font-family: Poppins, sans-serif;">¿Más de un talle?</span>
                <button type="button" id="switch-multi-talle-stock" onclick="toggleMultiTalleStock()" style={"width: 38px; height: 22px; border-radius: 20px; border: none; cursor: pointer; padding: 2px; display: flex; align-items: center; background: #{if multi_talle_activo_editando, do: "#186904", else: "#ccc"}; justify-content: #{if multi_talle_activo_editando, do: "flex-end", else: "flex-start"}; transition: background 0.2s;"}>
                  <div style="width: 18px; height: 18px; border-radius: 50%; background: white; box-shadow: 0 1px 3px rgba(0,0,0,0.3); transition: transform 0.2s;"></div>
                </button>
              </div>
            </div>

            <div style="display: flex; gap: 8px; margin-bottom: 14px;">
              <button type="button" id="btn-modo-letra-stock" onclick="cambiarModoTalleStock('letra')" style="flex: 1; padding: 9px; border-radius: 12px; border: 1.5px solid #186904; background: #186904; color: white; cursor: pointer; font-size: 13px; font-weight: 700; font-family: Poppins, sans-serif;">Letra</button>
              <button type="button" id="btn-modo-numerico-stock" onclick="cambiarModoTalleStock('numerico')" style="flex: 1; padding: 9px; border-radius: 12px; border: 1.5px solid #cfe4cf; background: white; color: #186904; cursor: pointer; font-size: 13px; font-weight: 700; font-family: Poppins, sans-serif;">Numérico</button>
            </div>

            <div id="talles-letra-stock" style="display: flex; flex-wrap: wrap; gap: 8px;">
              <%= for %{nombre: nombre, codigo: codigo} <- @talles_fijos_render do %>
                <% talle_activo = codigo in talles_seleccionados_editando %>
                <button type="button" data-talle={nombre} data-codigo-talle={codigo} onclick="toggleTalleStock(this)" style={"padding: 8px 16px; border-radius: 20px; border: 1.5px solid #{if talle_activo, do: "#186904", else: "#cfe4cf"}; background: #{if talle_activo, do: "#186904", else: "white"}; color: #{if talle_activo, do: "white", else: "#186904"}; cursor: pointer; font-size: 13px; font-weight: 600; font-family: Poppins, sans-serif;"}>
                  <%= nombre %>
                </button>
              <% end %>
              <%= for t <- @talles_custom do %>
                <% talle_activo = t.codigo_talle in talles_seleccionados_editando %>
                <button type="button" data-talle={t.nombre} data-codigo-talle={t.codigo_talle} onclick="toggleTalleStock(this)" style={"padding: 8px 16px; border-radius: 20px; border: 1.5px solid #{if talle_activo, do: "#186904", else: "#cfe4cf"}; background: #{if talle_activo, do: "#186904", else: "white"}; color: #{if talle_activo, do: "white", else: "#186904"}; cursor: pointer; font-size: 13px; font-weight: 600; font-family: Poppins, sans-serif;"}>
                  <%= t.nombre %>
                </button>
              <% end %>
            </div>

            <div id="talles-numerico-stock" style="display: none;">
              <input id="input-talle-numerico-stock" type="text" placeholder="Ej: 38, 40, 42" style="width: 100%; padding: 12px 16px; border: 1.5px solid #cfe4cf; border-radius: 16px; font-family: Poppins, sans-serif; font-size: 14px; box-sizing: border-box; outline: none; background: white;"/>
            </div>
          </div>

          <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 18px; padding: 18px; box-shadow: 0 4px 14px rgba(24,105,4,0.10); margin-top: 16px;">
            <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 20px;">
              <p style="font-size: 12.5px; font-weight: 700; color: #186904; margin: 0;">Color Principal</p>
              <div style="display: flex; align-items: center; gap: 8px;">
                <%
                  multi_color_activo_editando =
                    if @articulo_editando do
                      @articulo_editando.variantes
                      |> Map.keys()
                      |> Enum.map(fn clave -> clave |> String.split("_") |> List.first() end)
                      |> Enum.uniq()
                      |> length()
                      |> Kernel.>(1)
                    else
                      false
                    end
                %>
                <span style="font-size: 11px; color: #888; font-family: Poppins, sans-serif;">¿Más de un color?</span>
                <button type="button" id="switch-multi-color-stock" onclick="toggleMultiColorStock()" style={"width: 38px; height: 22px; border-radius: 20px; border: none; cursor: pointer; padding: 2px; display: flex; align-items: center; background: #{if multi_color_activo_editando, do: "#186904", else: "#ccc"}; justify-content: #{if multi_color_activo_editando, do: "flex-end", else: "flex-start"}; transition: background 0.2s;"}>
                  <div style="width: 18px; height: 18px; border-radius: 50%; background: white; box-shadow: 0 1px 3px rgba(0,0,0,0.3); transition: transform 0.2s;"></div>
                </button>
              </div>
            </div>
            <div id="colores-stock" style="display: grid; grid-template-columns: repeat(6, 1fr); gap: 16px 10px; justify-items: center;">
              <%
                mapa_hex_colores = %{
                  "Negro" => "#1a1a1a", "Blanco" => "#ffffff", "Gris" => "#9e9e9e", "Beige" => "#e8dcc8",
                  "Rojo" => "#d32f2f", "Bordó" => "#6d1b1b", "Rosa" => "#e91e8c", "Naranja" => "#f57c00",
                  "Amarillo" => "#fbc02d", "Verde" => "#43a047", "Verde oscuro" => "#1b5e20", "Celeste" => "#4fc3f7",
                  "Azul" => "#1565c0", "Azul marino" => "#0d1b4c", "Violeta" => "#7b1fa2", "Marrón" => "#5d3a1a",
                  "Dorado" => "#c9a227", "Plateado" => "#b0b0b0"
                }
              %>
              <%
                colores_seleccionados_editando =
                  if @articulo_editando do
                    @articulo_editando.variantes
                    |> Map.keys()
                    |> Enum.map(fn clave -> clave |> String.split("_") |> List.first() end)
                    |> Enum.uniq()
                  else
                    []
                  end
              %>
              <%= for {codigo_c, nombre} <- Enum.sort_by(DaleApp.Products.StockItem.colores(), fn {c, _n} -> c end) do %>
                <% color_activo = codigo_c in colores_seleccionados_editando %>
                <button type="button" data-color={nombre} data-codigo-color={codigo_c} onclick="seleccionarColorStock(this)" title={nombre} style={"width: 36px; height: 36px; border-radius: 50%; padding: 0; cursor: pointer; position: relative; background: none; border: none;"}>
                  <span class="anillo-color-stock" style={"position: absolute; inset: -4px; border-radius: 50%; border: 2.5px solid #{if color_activo, do: "#186904", else: "transparent"}; transition: border-color 0.15s;"}></span>
                  <span style={"position: absolute; inset: 0; border-radius: 50%; background: #{Map.get(mapa_hex_colores, nombre, "#ccc")}; box-shadow: 0 2px 5px rgba(0,0,0,0.18); #{if nombre == "Blanco", do: "border: 1.5px solid #e2e2e2;", else: ""}"}></span>
                  <svg class="check-color-stock" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke={if nombre in ["Blanco", "Amarillo", "Beige", "Plateado"], do: "#333", else: "white"} stroke-width="3" stroke-linecap="round" stroke-linejoin="round" style={"position: absolute; inset: 0; margin: auto; opacity: #{if color_activo, do: "1", else: "0"}; transition: opacity 0.15s;"}>
                    <polyline points="20 6 9 17 4 12"/>
                  </svg>
                </button>
              <% end %>
            </div>
            <p id="color-elegido-texto-stock" style="font-size: 12px; color: #999; margin: 14px 0 0; font-family: Poppins, sans-serif;"><%= texto_colores_elegidos(colores_seleccionados_editando) %></p>
          </div>

          <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 18px; padding: 18px; box-shadow: 0 4px 14px rgba(24,105,4,0.10); margin-top: 16px;">
            <p style="font-size: 12.5px; font-weight: 700; color: #186904; margin: 0 0 14px;">Cantidad de Stock</p>
            <div id="filas-cantidad-stock" style="display: flex; flex-direction: column; gap: 10px;">
              <%= if @articulo_editando && @articulo_editando.variantes != %{} do %>
                <%= for {clave, cantidad} <- Enum.sort(@articulo_editando.variantes) do %>
                  <% [codigo_color_fila, codigo_talle_fila] = String.split(clave, "_") %>
                  <% nombre_talle_fila = DaleApp.Products.StockItem.nombre_talle(codigo_talle_fila) %>
                  <% nombre_color_fila = DaleApp.Products.StockItem.nombre_color(codigo_color_fila) %>
                  <% hex_fila = Map.get(mapa_hex_colores, nombre_color_fila, "#ccc") %>
                  <div style="display: flex; align-items: center; gap: 10px; padding: 8px 10px; background: #f9f9f9; border-radius: 12px;">
                    <span style={"width: 22px; height: 22px; border-radius: 50%; background: #{hex_fila}; flex-shrink: 0; #{if codigo_color_fila == "21", do: "border: 1.5px solid #e0e0e0;", else: ""}"}></span>
                    <span style="font-size: 13px; font-weight: 700; color: #333; flex: 1;"><%= nombre_talle_fila %></span>
                    <div style="display: flex; align-items: center; gap: 6px;">
                      <button type="button" onclick={"cambiarCantidadStock('#{clave}', -1)"} style="width: 26px; height: 26px; border-radius: 8px; border: 1.5px solid #cfe4cf; background: white; color: #186904; font-size: 16px; cursor: pointer; display: flex; align-items: center; justify-content: center; padding: 0;">-</button>
                      <input type="number" id={"cantidad-input-#{clave}"} value={cantidad} min="0" max="9999" oninput={"setCantidadStock('#{clave}', this.value)"} style="width: 48px; text-align: center; padding: 5px 2px; border: 1.5px solid #cfe4cf; border-radius: 8px; font-family: Poppins, sans-serif; font-size: 13px; outline: none;"/>
                      <button type="button" onclick={"cambiarCantidadStock('#{clave}', 1)"} style="width: 26px; height: 26px; border-radius: 8px; border: 1.5px solid #cfe4cf; background: white; color: #186904; font-size: 16px; cursor: pointer; display: flex; align-items: center; justify-content: center; padding: 0;">+</button>
                      <button type="button" onclick={"pedirEliminarFilaStock('#{clave}', '#{nombre_talle_fila}', '#{nombre_color_fila}')"} style="width: 26px; height: 26px; border-radius: 8px; border: none; background: none; color: #c0392b; cursor: pointer; display: flex; align-items: center; justify-content: center; padding: 0;">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1 -2 2h-8a2 2 0 0 1 -2 -2l-1 -14"/><path d="M10 11v6"/><path d="M14 11v6"/><path d="M9 6v-2a1 1 0 0 1 1 -1h4a1 1 0 0 1 1 1v2"/></svg>
                      </button>
                    </div>
                  </div>
                <% end %>
              <% else %>
                <p style="font-size: 12px; color: #bbb; text-align: center; margin: 8px 0; font-family: Poppins, sans-serif;">Elegí talle y color para cargar cantidad</p>
              <% end %>
            </div>
          </div>

          <%= if @categoria_seleccionada do %>
            <% es_dalestand_fijo = @categoria_seleccionada.codigo == "99" %>
            <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 18px; padding: 18px; box-shadow: 0 4px 14px rgba(24,105,4,0.10); margin-top: 16px;">
              <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 10px;">
                <p style="font-size: 12.5px; font-weight: 700; color: #186904; margin: 0;">DaleStand</p>
                <button type="button" id="switch-dalestand-stock" onclick={if es_dalestand_fijo, do: nil, else: "toggleAgregarDaleStand()"} style={"width: 38px; height: 22px; border-radius: 20px; border: none; padding: 2px; display: flex; align-items: center; transition: background 0.2s; #{if es_dalestand_fijo, do: "background: #a8c4a5; justify-content: flex-end; cursor: default; opacity: 0.7;", else: "background: #ccc; justify-content: flex-start; cursor: pointer;"}"}>
                  <div style="width: 18px; height: 18px; border-radius: 50%; background: white; box-shadow: 0 1px 3px rgba(0,0,0,0.3); transition: transform 0.2s;"></div>
                </button>
              </div>
              <p style="font-size: 12px; color: #666; margin: 0 0 12px; line-height: 1.4;">
                <%= if es_dalestand_fijo do %>
                  Este producto va a estar en tu Stand Dale, tu local virtual dentro de la app.
                <% else %>
                  ¿Querés agregar este producto a tu Stand Dale, tu local virtual dentro de la app?
                <% end %>
              </p>
              <p style="font-size: 11px; color: #999; margin: 0 0 12px; font-weight: 600;">
                <%= (@panel && @panel.productos_dale) || 0 %>/<%= (@panel && @panel.limite_dale) || 12 %> espacios usados
              </p>
              <div id="titulo-imagenes-por-color-stock" style="display: none;">
                <p style="font-size: 11.5px; font-weight: 800; color: #186904; margin: 0 0 10px; text-transform: uppercase; letter-spacing: 0.6px;">Imágenes del producto</p>
              </div>
              <div id="imagenes-por-color-stock" style="display: none; flex-direction: column; gap: 10px;"></div>
            </div>
          <% end %>

          <%
            combos_editando =
              if @articulo_editando, do: @articulo_editando.variantes |> Map.keys() |> Enum.sort(), else: []
            combo_activo_editando = List.first(combos_editando)
            codigo9_activo_editando =
              if @articulo_editando && combo_activo_editando && @categoria_seleccionada do
                codigo_completo_combo(combo_activo_editando, @categoria_seleccionada.codigo, @articulo_editando)
              else
                nil
              end
            ean13_activo_editando = codigo9_activo_editando && StockItem.a_ean13(codigo9_activo_editando)

            qrs_por_combo =
              if @articulo_editando && @categoria_seleccionada do
                combos_editando
                |> Enum.map(fn clave ->
                  [codigo_color_q, codigo_talle_q] = String.split(clave, "_")
                  codigo9 = codigo_completo_combo(clave, @categoria_seleccionada.codigo, @articulo_editando)
                  svg = codigo9 && (EQRCode.encode(codigo9) |> EQRCode.svg(width: 100))

                  etiqueta =
                    String.downcase(StockItem.nombre_color(codigo_color_q)) <>
                      " " <> String.downcase(StockItem.nombre_talle(codigo_talle_q))

                  if svg do
                    {clave, %{svg: svg, etiqueta: etiqueta}}
                  else
                    nil
                  end
                end)
                |> Enum.reject(&is_nil/1)
                |> Map.new()
              else
                %{}
              end

            barras_por_combo =
              if @articulo_editando && @categoria_seleccionada do
                combos_editando
                |> Enum.map(fn clave ->
                  [codigo_color_b, codigo_talle_b] = String.split(clave, "_")
                  codigo9_b = codigo_completo_combo(clave, @categoria_seleccionada.codigo, @articulo_editando)
                  codigo_ean13_b = codigo9_b && StockItem.a_ean13(codigo9_b)
                  svg_dale9_b = codigo_de_barras_svg(codigo9_b, :code128)
                  svg_ean13_b = codigo_de_barras_svg(codigo_ean13_b, :ean13)
                  etiqueta_b =
                    String.downcase(StockItem.nombre_color(codigo_color_b)) <>
                      " " <> String.downcase(StockItem.nombre_talle(codigo_talle_b))
                  if svg_dale9_b && svg_ean13_b do
                    {clave,
                     %{
                       svg_dale9: svg_dale9_b,
                       codigo_dale9: formatear_dale9_espaciado(codigo9_b),
                       svg_ean13: svg_ean13_b,
                       codigo_ean13: codigo_ean13_b,
                       etiqueta: etiqueta_b
                     }}
                  else
                    nil
                  end
                end)
                |> Enum.reject(&is_nil/1)
                |> Map.new()
              else
                %{}
              end
          %>

          <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 18px; padding: 18px; box-shadow: 0 4px 14px rgba(24,105,4,0.10); margin-top: 16px; text-align: center;">
            <p style="font-size: 12.5px; font-weight: 700; color: #186904; margin: 0 0 10px;">Código DALE9</p>
            <div id="selector-combos-codigo-stock-wrap" style={"display: #{if length(combos_editando) > 1, do: "block", else: "none"}; margin-bottom: 16px; padding-bottom: 14px; border-bottom: 1px dashed #d9ead9;"}>
              <p style="font-size: 10.5px; color: #999; margin: 0 0 8px; font-family: Poppins, sans-serif;">Mostrando el código de:</p>
              <div id="selector-combos-codigo-stock" style="display: flex; flex-wrap: wrap; gap: 6px; justify-content: center;">
                <%= for clave <- combos_editando do %>
                  <% [cc_fila, ct_fila] = String.split(clave, "_") %>
                  <% combo_activo = clave == combo_activo_editando %>
                  <button type="button" onclick={"seleccionarComboCodigoStock('#{clave}')"} style={"display: flex; align-items: center; gap: 6px; padding: 6px 12px; border-radius: 16px; border: 1.5px solid #{if combo_activo, do: "#186904", else: "#cfe4cf"}; background: #{if combo_activo, do: "#186904", else: "white"}; color: #{if combo_activo, do: "white", else: "#186904"}; cursor: pointer; font-size: 12px; font-weight: 600; font-family: Poppins, sans-serif;"}>
                    <span style={"width: 14px; height: 14px; border-radius: 50%; background: #{Map.get(mapa_hex_colores, StockItem.nombre_color(cc_fila), "#ccc")}; #{if cc_fila == "21", do: "border: 1px solid #ccc;", else: ""}"}></span>
                    <%= StockItem.nombre_talle(ct_fila) %>
                  </button>
                <% end %>
              </div>
            </div>
            <div id="barras-dale9-stock" style="display: flex; justify-content: center; min-height: 60px; align-items: center;">
              <%= if svg_dale9 = codigo_de_barras_svg(codigo9_activo_editando || "000000000", :code128) do %>
                {raw(svg_dale9)}
              <% else %>
                <span style="font-size: 11px; color: #ccc;">Sin vista previa</span>
              <% end %>
            </div>
            <p id="texto-dale9-stock" style="font-size: 13px; font-weight: 700; color: #333; letter-spacing: 2px; margin: 6px 0 0; font-family: monospace;"><%= formatear_dale9_espaciado(codigo9_activo_editando) %></p>
            <button type="button" id="boton-imprimir-dale9-stock" onclick="abrirImpresionTermica('dale9')" style={"display: #{if @articulo_editando, do: "inline-block", else: "none"}; margin: 8px auto 0; background: #186904; color: white; border: none; border-radius: 12px; padding: 8px 20px; font-size: 12.5px; font-weight: 700; font-family: Poppins, sans-serif; cursor: pointer;"}>Imprimir</button>
          </div>

          <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 18px; padding: 18px; box-shadow: 0 4px 14px rgba(24,105,4,0.10); margin-top: 16px; text-align: center;">
            <p style="font-size: 12.5px; font-weight: 700; color: #186904; margin: 0 0 10px;">Código EAN-13</p>
            <div id="barras-ean13-stock" style="display: flex; justify-content: center; min-height: 60px; align-items: center;">
              <%= if svg_ean13 = codigo_de_barras_svg(ean13_activo_editando || StockItem.a_ean13("000000000"), :ean13) do %>
                {raw(svg_ean13)}
              <% else %>
                <span style="font-size: 11px; color: #ccc;">Sin vista previa</span>
              <% end %>
            </div>
            <p id="texto-ean13-stock" style="font-size: 13px; font-weight: 700; color: #333; letter-spacing: 2px; margin: 6px 0 0; font-family: monospace;"><%= ean13_activo_editando || "···· ·· ···· ··· ·· ·" %></p>
            <button type="button" id="boton-imprimir-ean13-stock" onclick="abrirImpresionTermica('ean13')" style={"display: #{if @articulo_editando, do: "inline-block", else: "none"}; margin: 8px auto 0; background: #186904; color: white; border: none; border-radius: 12px; padding: 8px 20px; font-size: 12.5px; font-weight: 700; font-family: Poppins, sans-serif; cursor: pointer;"}>Imprimir</button>
          </div>

          <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 18px; padding: 18px; box-shadow: 0 4px 14px rgba(24,105,4,0.10); margin-top: 16px; text-align: center;">
            <p style="font-size: 12.5px; font-weight: 700; color: #186904; margin: 0 0 10px;">Código QR</p>
            <div id="qr-dale9-stock" style="display: flex; justify-content: center;">
              {raw(EQRCode.encode(codigo9_activo_editando || "DALE9-preview") |> EQRCode.svg(width: 110))}
            </div>
            <p id="texto-vista-previa-qr-stock" style={"display: #{if @articulo_editando, do: "none", else: "block"}; font-size: 11px; color: #aaa; margin: 8px 0 0; font-family: Poppins, sans-serif;"}>Vista previa</p>
            <button type="button" id="boton-imprimir-qr-stock" onclick="abrirImpresionQRStock()" style={"display: #{if @articulo_editando, do: "inline-block", else: "none"}; margin: 8px auto 0; background: #186904; color: white; border: none; border-radius: 12px; padding: 8px 20px; font-size: 12.5px; font-weight: 700; font-family: Poppins, sans-serif; cursor: pointer;"}>Imprimir</button>
          </div>

          <button id="boton-guardar-stock" onclick="guardarProductoStock()" style="width: 100%; margin-top: 20px; background: #186904; color: white; border: none; border-radius: 16px; padding: 15px; font-size: 15px; font-weight: 700; cursor: pointer; font-family: Poppins, sans-serif; box-shadow: 0 3px 10px rgba(24,105,4,0.25);">
            Guardar producto
          </button>
          </div>

          <div id="pantalla-imprimir-stock" style={"display: #{if @mostrar_pantalla_imprimir, do: "block", else: "none"};"}>
            <p style="font-size: 22px; font-weight: 800; color: #186904; margin: 0 0 4px;">Imprimir códigos</p>
            <p style="font-size: 13px; color: #999; margin: 0 0 24px;">Elegí qué productos imprimir y en qué tamaño</p>

            <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 18px; padding: 18px; box-shadow: 0 4px 14px rgba(24,105,4,0.10); margin-bottom: 20px;">
              <p style="font-size: 12.5px; font-weight: 700; color: #186904; margin: 0 0 14px;">Tamaño</p>

              <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; margin-bottom: 20px;">
                <button type="button" data-tamano="chico" data-ancho-mm="25" data-alto-mm="30" onclick="elegirTamanoImprimir(this)" class="tarjeta-tamano-imprimir" style="display: flex; flex-direction: column; align-items: center; gap: 8px; padding: 14px 8px; border-radius: 16px; border: 1.5px solid #186904; background: #e6f4e6; cursor: pointer; font-family: Poppins, sans-serif;">
                  <span style="width: 14px; height: 14px; border-radius: 4px; background: #186904;"></span>
                  <span style="font-size: 13px; font-weight: 700; color: #186904;">Chico</span>
                  <span style="font-size: 10px; color: #999;">25×30mm</span>
                </button>

                <button type="button" data-tamano="mediano" data-ancho-mm="30" data-alto-mm="38" onclick="elegirTamanoImprimir(this)" class="tarjeta-tamano-imprimir" style="display: flex; flex-direction: column; align-items: center; gap: 8px; padding: 14px 8px; border-radius: 16px; border: 1.5px solid #cfe4cf; background: white; cursor: pointer; font-family: Poppins, sans-serif;">
                  <span style="width: 22px; height: 22px; border-radius: 5px; background: #186904;"></span>
                  <span style="font-size: 13px; font-weight: 700; color: #186904;">Mediano</span>
                  <span style="font-size: 10px; color: #999;">30×38mm</span>
                </button>

                <button type="button" data-tamano="grande" data-ancho-mm="50" data-alto-mm="50" onclick="elegirTamanoImprimir(this)" class="tarjeta-tamano-imprimir" style="display: flex; flex-direction: column; align-items: center; gap: 8px; padding: 14px 8px; border-radius: 16px; border: 1.5px solid #cfe4cf; background: white; cursor: pointer; font-family: Poppins, sans-serif;">
                  <span style="width: 30px; height: 30px; border-radius: 6px; background: #186904;"></span>
                  <span style="font-size: 13px; font-weight: 700; color: #186904;">Grande</span>
                  <span style="font-size: 10px; color: #999;">50×50mm</span>
                </button>
              </div>

              <div id="hojas-preview-imprimir-container" style="display: flex; flex-direction: column; align-items: center; gap: 20px;">
                <div style="width: 100%; max-width: 260px;">
                  <div style="display: grid; grid-template-columns: repeat(7, 1fr); gap: 2px; width: 100%; aspect-ratio: 210 / 297; border: 1.5px solid #ddd; border-radius: 4px; box-shadow: 0 2px 10px rgba(0,0,0,0.08); padding: 3.5%; box-sizing: border-box; background: white;">
                    <%= for _i <- 1..capacidad_hoja_mm(25, 30) do %>
                      <div style="background: #186904; opacity: 0.75; border-radius: 2px;"></div>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>

            <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 18px; padding: 18px; box-shadow: 0 4px 14px rgba(24,105,4,0.10);">
              <p style="font-size: 12.5px; font-weight: 700; color: #186904; margin: 0 0 4px;">Cantidad de QRs</p>
              <p id="texto-espacios-restantes-imprimir" style="font-size: 11.5px; color: #666; margin: 0 0 14px;">Te quedan <%= capacidad_hoja_mm(25, 30) %> de <%= capacidad_hoja_mm(25, 30) %> espacios</p>
              <div id="filas-cantidad-qr-imprimir" style="display: flex; flex-direction: column; gap: 10px;">
                <%= if @articulo_editando do %>
                  <%= for clave <- Enum.sort(Map.keys(@articulo_editando.variantes)) do %>
                    <% [cc_qr, ct_qr] = String.split(clave, "_") %>
                    <% nombre_talle_qr = StockItem.nombre_talle(ct_qr) %>
                    <% nombre_color_qr = StockItem.nombre_color(cc_qr) %>
                    <% hex_qr = Map.get(mapa_hex_colores, nombre_color_qr, "#186904") %>
                    <div style="display: flex; align-items: center; gap: 10px; padding: 8px 10px; background: #f9f9f9; border-radius: 12px;">
                      <span data-fila-talle-qr={clave} data-letra-talle={nombre_talle_qr} style={"width: 22px; height: 22px; border-radius: 50%; background: #{hex_qr}; flex-shrink: 0; #{if cc_qr == "21", do: "border: 1.5px solid #e0e0e0;", else: ""}"}></span>
                      <span style="font-size: 13px; font-weight: 700; color: #333; flex: 1;"><%= nombre_color_qr %> · <%= nombre_talle_qr %></span>
                      <div style="display: flex; align-items: center; gap: 6px;">
                        <button type="button" onclick={"cambiarCantidadQR('#{clave}', -1)"} style="width: 26px; height: 26px; border-radius: 8px; border: 1.5px solid #cfe4cf; background: white; color: #186904; font-size: 16px; cursor: pointer; display: flex; align-items: center; justify-content: center; padding: 0;">-</button>
                        <input type="number" id={"cantidad-qr-input-#{clave}"} value="0" min="0" max="9999" oninput={"setCantidadQR('#{clave}', this.value)"} style="width: 52px; text-align: center; padding: 5px 2px; border: 1.5px solid #cfe4cf; border-radius: 8px; font-family: Poppins, sans-serif; font-size: 13px; outline: none;"/>
                        <button type="button" onclick={"cambiarCantidadQR('#{clave}', 1)"} style="width: 26px; height: 26px; border-radius: 8px; border: 1.5px solid #cfe4cf; background: white; color: #186904; font-size: 16px; cursor: pointer; display: flex; align-items: center; justify-content: center; padding: 0;">+</button>
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>

            <div id="imprimir-fisico-container" data-qrs={Jason.encode!(qrs_por_combo)} style="display: none;"></div>
            <div id="imprimir-termico-container" data-barras={Jason.encode!(barras_por_combo)} style="display: none;"></div>

            <style>
              @media print {
                @page { margin: 0; }
                * { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
                html, body { background: white !important; margin: 0 !important; padding: 0 !important; }
                #app-wrapper { display: none !important; }
                #imprimir-fisico-clon { display: block !important; margin: 0; padding: 0; }
                .hoja-imprimir-pagina { margin: 0; }
                .hoja-imprimir-pagina:not(:last-child) { page-break-after: always; }
                .hoja-imprimir-pagina svg { width: 100%; height: 100%; display: block; }
                #imprimir-termico-clon { display: block !important; margin: 0; padding: 0; }
                .etiqueta-termica-pagina { margin: 0; }
                .etiqueta-termica-pagina svg { width: 100% !important; height: auto !important; display: block; }
              }
            </style>

            <button type="button" onclick="imprimirHojaFisica()" style="width: 100%; margin-top: 20px; background: #186904; color: white; border: none; border-radius: 16px; padding: 15px; font-size: 15px; font-weight: 700; cursor: pointer; font-family: Poppins, sans-serif; box-shadow: 0 3px 10px rgba(24,105,4,0.25);">Imprimir</button>
          </div>

          <div id="pantalla-imprimir-termico-stock" style="display: none;">
            <p id="titulo-imprimir-termico-stock" style="font-size: 22px; font-weight: 800; color: #186904; margin: 0 0 4px;">Imprimir código de barras</p>
            <p style="font-size: 13px; color: #999; margin: 0 0 24px;">Etiquetas para impresora térmica</p>

            <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 18px; padding: 18px; box-shadow: 0 4px 14px rgba(24,105,4,0.10); margin-bottom: 20px;">
              <p style="font-size: 12.5px; font-weight: 700; color: #186904; margin: 0 0 14px;">Ancho del rollo</p>
              <div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 10px; margin-bottom: 20px;">
                <button type="button" data-ancho-mm="58" onclick="elegirAnchoTermico(this)" class="tarjeta-ancho-termico" style="padding: 14px 8px; border-radius: 16px; border: 1.5px solid #186904; background: #e6f4e6; cursor: pointer; font-family: Poppins, sans-serif;">
                  <span style="font-size: 13px; font-weight: 700; color: #186904;">58mm</span>
                </button>
                <button type="button" data-ancho-mm="80" onclick="elegirAnchoTermico(this)" class="tarjeta-ancho-termico" style="padding: 14px 8px; border-radius: 16px; border: 1.5px solid #cfe4cf; background: white; cursor: pointer; font-family: Poppins, sans-serif;">
                  <span style="font-size: 13px; font-weight: 700; color: #186904;">80mm</span>
                </button>
              </div>

              <div id="preview-termico-container" style="display: flex; flex-direction: column; align-items: center; gap: 6px; max-height: 320px; overflow-y: auto; background: #f4f4f4; border-radius: 10px; padding: 10px;">
                <span style="font-size: 11px; color: #999;">Cargá cantidades abajo para ver la vista previa</span>
              </div>
            </div>

            <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 18px; padding: 18px; box-shadow: 0 4px 14px rgba(24,105,4,0.10);">
              <p style="font-size: 12.5px; font-weight: 700; color: #186904; margin: 0 0 14px;">Cantidad de etiquetas</p>
              <div id="filas-cantidad-termico-imprimir" style="display: flex; flex-direction: column; gap: 10px;">
                <%= if @articulo_editando do %>
                  <%= for clave <- Enum.sort(Map.keys(@articulo_editando.variantes)) do %>
                    <% [cc_term, ct_term] = String.split(clave, "_") %>
                    <% nombre_talle_term = StockItem.nombre_talle(ct_term) %>
                    <% nombre_color_term = StockItem.nombre_color(cc_term) %>
                    <% hex_term = Map.get(mapa_hex_colores, nombre_color_term, "#186904") %>
                    <div style="display: flex; align-items: center; gap: 10px; padding: 8px 10px; background: #f9f9f9; border-radius: 12px;">
                      <span style={"width: 22px; height: 22px; border-radius: 50%; background: #{hex_term}; flex-shrink: 0; #{if cc_term == "21", do: "border: 1.5px solid #e0e0e0;", else: ""}"}></span>
                      <span style="font-size: 13px; font-weight: 700; color: #333; flex: 1;"><%= nombre_color_term %> · <%= nombre_talle_term %></span>
                      <div style="display: flex; align-items: center; gap: 6px;">
                        <button type="button" onclick={"cambiarCantidadTermico('#{clave}', -1)"} style="width: 26px; height: 26px; border-radius: 8px; border: 1.5px solid #cfe4cf; background: white; color: #186904; font-size: 16px; cursor: pointer; display: flex; align-items: center; justify-content: center; padding: 0;">-</button>
                        <input type="number" id={"cantidad-termico-input-#{clave}"} value="0" min="0" max="9999" oninput={"setCantidadTermico('#{clave}', this.value)"} style="width: 52px; text-align: center; padding: 5px 2px; border: 1.5px solid #cfe4cf; border-radius: 8px; font-family: Poppins, sans-serif; font-size: 13px; outline: none;"/>
                        <button type="button" onclick={"cambiarCantidadTermico('#{clave}', 1)"} style="width: 26px; height: 26px; border-radius: 8px; border: 1.5px solid #cfe4cf; background: white; color: #186904; font-size: 16px; cursor: pointer; display: flex; align-items: center; justify-content: center; padding: 0;">+</button>
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>

            <div id="imprimir-termico-fisico-container" style="display: none;"></div>

            <button type="button" onclick="cerrarPantallaImprimirTermico()" style="width: 100%; margin-top: 12px; background: white; color: #186904; border: 1.5px solid #186904; border-radius: 16px; padding: 13px; font-size: 14px; font-weight: 700; cursor: pointer; font-family: Poppins, sans-serif;">Volver</button>
            <button type="button" onclick="imprimirHojaTermica()" style="width: 100%; margin-top: 10px; background: #186904; color: white; border: none; border-radius: 16px; padding: 15px; font-size: 15px; font-weight: 700; cursor: pointer; font-family: Poppins, sans-serif; box-shadow: 0 3px 10px rgba(24,105,4,0.25);">Imprimir</button>
          </div>

          <script :type={Phoenix.LiveView.ColocatedHook} name=".FormularioProductoStock">
            export default {
              mounted() {
                let codigoTipo = this.el.dataset.codigoTipo || "";
                const codigoTipoOriginal = codigoTipo;
                const breadcrumbNombreCategoria = document.getElementById('breadcrumb-nombre-categoria-stock');
                const nombreCategoriaOriginal = breadcrumbNombreCategoria ? breadcrumbNombreCategoria.textContent : '';
                const numeroPreview = this.el.dataset.numeroPreview || "";
                let imagenBlobStock = null;
                let tallesSeleccionadosStock = [];
                let editandoArticuloActivo = false;
                let datosOriginalesStock = null;
                let productosPorColorEditando = {};
                const csrfTokenStock = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");

                window.previsualizarImagenStock = (input) => {
                  const file = input.files[0];
                  if (!file) return;
                  imagenBlobStock = file;
                  const reader = new FileReader();
                  reader.onload = (e) => {
                    const imgFondo = document.getElementById('preview-img-fondo-stock');
                    const imgPreview = document.getElementById('preview-img-stock');
                    imgFondo.src = e.target.result;
                    imgFondo.style.display = 'block';
                    imgPreview.src = e.target.result;
                    imgPreview.style.display = 'block';
                    document.getElementById('preview-placeholder-stock').style.display = 'none';
                  };
                  reader.readAsDataURL(file);
                };

                window.limitarPalabrasStock = (textarea) => {
                  const palabras = textarea.value.trim().split(/\s+/).filter(p => p.length > 0);
                  if (palabras.length > 500) {
                    textarea.value = palabras.slice(0, 500).join(' ');
                  }
                  const contador = document.getElementById('contador-palabras-stock');
                  if (contador) contador.textContent = Math.min(palabras.length, 500) + '/500 palabras';
                };

                window.actualizarPreviewStock = () => {
                  const nombre = document.getElementById('input-nombre-stock').value;
                  const precio = document.getElementById('input-precio-stock').value;
                  document.getElementById('prev-nombre-stock').textContent = nombre;
                  document.getElementById('prev-precio-stock').textContent = precio ? '$' + parseInt(precio).toLocaleString() : '';
                };

                let colorCodigoElegido = null;
                let talleCodigoElegido = null;
                let claveCodigoPreview = null;

                window.actualizarPreviewCodigoStock = () => {
                  actualizarSelectorCombosCodigo();

                  const tipo = codigoTipo || '\u00b7\u00b7';
                  let color, talle;

                  if (claveCodigoPreview) {
                    const partes = claveCodigoPreview.split('_');
                    color = partes[0];
                    talle = partes[1];
                  } else {
                    color = colorCodigoElegido || '\u00b7\u00b7';
                    talle = talleCodigoElegido;

                    const divNum = document.getElementById('talles-numerico-stock');
                    const modoNumerico = divNum && divNum.style.display !== 'none';
                    if (modoNumerico) {
                      const valorNum = document.getElementById('input-talle-numerico-stock').value.trim();
                      talle = valorNum ? valorNum.padStart(2, '0').slice(-2) : '\u00b7\u00b7';
                    } else if (!talle) {
                      talle = '\u00b7\u00b7';
                    }
                  }

                  const numero = numeroPreview || '\u00b7\u00b7\u00b7';

                  const resaltado = claveCodigoPreview ? 'color:#E91E8C; font-weight:800;' : '';
                  const textoEl = document.getElementById('texto-dale9-stock');
                  if (textoEl) textoEl.innerHTML = tipo + ' <span style="' + resaltado + '">' + color + '</span> ' + numero + ' <span style="' + resaltado + '">' + talle + '</span>';

                  const completo = [tipo, color, numero, talle].every(p => !p.includes('\u00b7'));
                  const ean13El = document.getElementById('texto-ean13-stock');
                  if (completo && ean13El) {
                    const codigo9 = tipo + color + numero + talle;
                    const base = '20' + codigo9 + '0';
                    let suma = 0;
                    for (let i = 0; i < 12; i++) {
                      const peso = (i % 2 === 0) ? 1 : 3;
                      suma += parseInt(base[i]) * peso;
                    }
                    const digitoControl = (10 - (suma % 10)) % 10;
                    const ean13Completo = base.slice(0, 12) + digitoControl;
                    const antesColor = ean13Completo.slice(0, 4);
                    const parteColor = ean13Completo.slice(4, 6);
                    const entreMedio = ean13Completo.slice(6, 9);
                    const parteTalle = ean13Completo.slice(9, 11);
                    const resto = ean13Completo.slice(11);
                    ean13El.innerHTML = antesColor + '<span style="' + resaltado + '">' + parteColor + '</span>' + entreMedio + '<span style="' + resaltado + '">' + parteTalle + '</span>' + resto;
                  } else if (ean13El) {
                    ean13El.textContent = '\u00b7\u00b7\u00b7\u00b7 \u00b7\u00b7 \u00b7\u00b7\u00b7\u00b7 \u00b7\u00b7\u00b7 \u00b7\u00b7 \u00b7';
                  }
                  actualizarFilasCantidadStock();
                };

                let multiTalleActivo = false;
                let multiColorActivo = false;
                let agregarADaleStandActivo = this.el.dataset.dalestandFijo === 'true';

                let imagenesPorColorStock = {};

                window.toggleAgregarDaleStand = () => {
                  agregarADaleStandActivo = !agregarADaleStandActivo;
                  codigoTipo = agregarADaleStandActivo ? '99' : codigoTipoOriginal;
                  if (breadcrumbNombreCategoria) {
                    breadcrumbNombreCategoria.textContent = agregarADaleStandActivo ? 'Productos DaleStand' : nombreCategoriaOriginal;
                  }
                  const sw = document.getElementById('switch-dalestand-stock');
                  if (sw) {
                    sw.style.background = agregarADaleStandActivo ? '#186904' : '#ccc';
                    sw.style.justifyContent = agregarADaleStandActivo ? 'flex-end' : 'flex-start';
                  }
                  actualizarImagenesPorColorStock();
                };

                window.actualizarImagenesPorColorStock = () => {
                  const cont = document.getElementById('imagenes-por-color-stock');
                  const titulo = document.getElementById('titulo-imagenes-por-color-stock');
                  if (!cont) return;

                  if (!agregarADaleStandActivo) {
                    cont.style.display = 'none';
                    if (titulo) titulo.style.display = 'none';
                    return;
                  }
                  cont.style.display = 'flex';
                  if (titulo) titulo.style.display = 'block';

                  const colores = multiColorActivo ? coloresElegidos : (colorCodigoElegido ? [colorCodigoElegido] : []);

                  Object.keys(imagenesPorColorStock).forEach(cod => {
                    if (!colores.includes(cod)) delete imagenesPorColorStock[cod];
                  });

                  let html = '';
                  colores.forEach(cod => {
                    if (!imagenesPorColorStock[cod]) imagenesPorColorStock[cod] = [];
                    const hex = mapaHexColores[cod] || '#ccc';
                    const nombreColorFila = nombreColorPorCodigoStock(cod);
                    const fotos = imagenesPorColorStock[cod];

                    html += '<div style="display: flex; align-items: center; gap: 10px; padding: 10px; background: white; border-radius: 12px; border: 1px solid #eef4ec;">' +
                      '<span style="width: 22px; height: 22px; border-radius: 50%; background: ' + hex + '; flex-shrink: 0; ' + (cod === '21' ? 'border: 1.5px solid #e0e0e0;' : '') + '"></span>' +
                      '<span style="font-size: 12.5px; font-weight: 700; color: #333; flex: 1;">' + nombreColorFila + '</span>' +
                      '<div style="display: flex; gap: 6px;">';

                    for (let i = 0; i < 2; i++) {
                      if (fotos[i]) {
                        html += '<div style="position: relative; width: 44px; height: 44px; border-radius: 8px; overflow: hidden; background: #f5f5f5;">' +
                          '<img src="' + fotos[i].previewUrl + '" style="width: 100%; height: 100%; object-fit: cover;" />' +
                          '<button type="button" onclick="quitarImagenColorStock(\'' + cod + '\', ' + i + ')" style="position: absolute; top: -3px; right: -3px; width: 16px; height: 16px; border-radius: 50%; background: #c0392b; color: white; border: none; font-size: 10px; line-height: 1; cursor: pointer; display: flex; align-items: center; justify-content: center; padding: 0;">×</button>' +
                          '</div>';
                      } else {
                        html += '<button type="button" onclick="document.getElementById(\'file-color-' + cod + '-' + i + '\').click()" style="width: 44px; height: 44px; border-radius: 8px; border: 1.5px dashed #b8d4b3; background: white; color: #186904; cursor: pointer; font-size: 18px; font-weight: 300; display: flex; align-items: center; justify-content: center; padding: 0;">+</button>' +
                          '<input type="file" id="file-color-' + cod + '-' + i + '" accept="image/*" style="display:none;" onchange="agregarImagenColorStock(this, \'' + cod + '\', ' + i + ')" />';
                      }
                    }

                    html += '</div></div>';
                  });

                  cont.innerHTML = html || '<p style="font-size: 11px; color: #bbb; margin: 0;">Elegí al menos un color para cargar fotos.</p>';
                };

                window.agregarImagenColorStock = (input, colorCod, slot) => {
                  const file = input.files[0];
                  if (!file) return;
                  if (!imagenesPorColorStock[colorCod]) imagenesPorColorStock[colorCod] = [];
                  const reader = new FileReader();
                  reader.onload = (e) => {
                    imagenesPorColorStock[colorCod][slot] = { file, previewUrl: e.target.result };
                    actualizarImagenesPorColorStock();
                  };
                  reader.readAsDataURL(file);
                };

                window.quitarImagenColorStock = (colorCod, slot) => {
                  if (imagenesPorColorStock[colorCod]) {
                    imagenesPorColorStock[colorCod][slot] = null;
                    actualizarImagenesPorColorStock();
                  }
                };
                let tallesElegidos = [];
                let coloresElegidos = [];
                let cantidadesStock = {};
                let clavesExcluidasStock = new Set();

                const mapaHexColores = {
                  '11': '#1a1a1a', '21': '#ffffff', '31': '#9e9e9e', '41': '#e8dcc8',
                  '51': '#d32f2f', '61': '#6d1b1b', '71': '#e91e8c', '81': '#f57c00',
                  '91': '#fbc02d', '12': '#43a047', '22': '#1b5e20', '32': '#4fc3f7',
                  '42': '#1565c0', '52': '#0d1b4c', '62': '#7b1fa2', '72': '#5d3a1a',
                  '82': '#c9a227', '92': '#b0b0b0'
                };

                window.actualizarSelectorCombosCodigo = () => {
                  const cont = document.getElementById('selector-combos-codigo-stock');
                  const wrap = document.getElementById('selector-combos-codigo-stock-wrap');
                  if (!cont || !wrap) return;

                  const talles = tallesElegidos.length > 0 ? tallesElegidos : (talleCodigoElegido ? [talleCodigoElegido] : []);
                  const colores = coloresElegidos.length > 0 ? coloresElegidos : (colorCodigoElegido ? [colorCodigoElegido] : []);

                  const combos = [];
                  colores.forEach(colorCod => {
                    talles.forEach(talleCod => {
                      const clave = colorCod + '_' + talleCod;
                      if (clavesExcluidasStock.has(clave)) return;
                      combos.push(clave);
                    });
                  });

                  if (combos.length <= 1) {
                    wrap.style.display = 'none';
                    cont.innerHTML = '';
                    claveCodigoPreview = combos.length === 1 ? combos[0] : null;
                    return;
                  }

                  if (!claveCodigoPreview || !combos.includes(claveCodigoPreview)) {
                    claveCodigoPreview = combos[0];
                  }

                  wrap.style.display = 'block';
                  let html = '';
                  combos.forEach(clave => {
                    const partes = clave.split('_');
                    const colorCod = partes[0];
                    const talleCod = partes[1];
                    const hex = mapaHexColores[colorCod] || '#ccc';
                    const btnTalle = document.querySelector('#talles-letra-stock button[data-codigo-talle="' + talleCod + '"]');
                    const nombreTalle = btnTalle ? btnTalle.getAttribute('data-talle') : talleCod;
                    const activo = clave === claveCodigoPreview;
                    html += '<button type="button" onclick="seleccionarComboCodigoStock(\'' + clave + '\')" style="display: flex; align-items: center; gap: 6px; padding: 6px 12px; border-radius: 16px; border: 1.5px solid ' + (activo ? '#186904' : '#cfe4cf') + '; background: ' + (activo ? '#186904' : 'white') + '; color: ' + (activo ? 'white' : '#186904') + '; cursor: pointer; font-size: 12px; font-weight: 600; font-family: Poppins, sans-serif;">' +
                      '<span style="width: 14px; height: 14px; border-radius: 50%; background: ' + hex + '; ' + (colorCod === '21' ? 'border: 1px solid #ccc;' : '') + '"></span>' +
                      nombreTalle +
                      '</button>';
                  });
                  cont.innerHTML = html;
                };

                window.seleccionarComboCodigoStock = (clave) => {
                  claveCodigoPreview = clave;
                  actualizarPreviewCodigoStock();
                };

                const ANCHO_HOJA_MM_IMPRIMIR = 210;
                const ALTO_HOJA_MM_IMPRIMIR = 297;
                const MARGEN_MM_IMPRIMIR = 10;
                let tamanoSeleccionadoImprimir = { anchoMm: 25, altoMm: 30 };
                let cantidadesQR = {};
                let ultimoArticuloImprimir = null;

                window.imprimirHojaFisica = () => {
                  const original = document.getElementById('imprimir-fisico-container');
                  if (!original) { window.print(); return; }

                  const existente = document.getElementById('imprimir-fisico-clon');
                  if (existente) existente.remove();

                  const clon = original.cloneNode(true);
                  clon.id = 'imprimir-fisico-clon';
                  clon.style.display = 'none';
                  document.body.appendChild(clon);

                  window.print();

                  setTimeout(() => {
                    const clonViejo = document.getElementById('imprimir-fisico-clon');
                    if (clonViejo) clonViejo.remove();
                  }, 2000);
                };

                window.elegirTamanoImprimir = (btn) => {
                  document.querySelectorAll('.tarjeta-tamano-imprimir').forEach(b => {
                    b.style.borderColor = '#cfe4cf';
                    b.style.background = 'white';
                  });
                  btn.style.borderColor = '#186904';
                  btn.style.background = '#e6f4e6';

                  tamanoSeleccionadoImprimir = {
                    anchoMm: parseFloat(btn.dataset.anchoMm),
                    altoMm: parseFloat(btn.dataset.altoMm)
                  };

                  actualizarPreviewImprimir();
                };

                window.cambiarCantidadQR = (clave, delta) => {
                  const actual = cantidadesQR[clave] || 0;
                  const nuevo = Math.max(0, Math.min(9999, actual + delta));
                  cantidadesQR[clave] = nuevo;
                  const input = document.getElementById('cantidad-qr-input-' + clave);
                  if (input) input.value = nuevo;
                  actualizarPreviewImprimir();
                };

                window.setCantidadQR = (clave, valor) => {
                  let n = parseInt(valor) || 0;
                  n = Math.max(0, Math.min(9999, n));
                  cantidadesQR[clave] = n;
                  const input = document.getElementById('cantidad-qr-input-' + clave);
                  if (input) input.value = n;
                  actualizarPreviewImprimir();
                };

                window.actualizarPreviewImprimir = () => {
                  const { anchoMm, altoMm } = tamanoSeleccionadoImprimir;
                  const areaAnchoMm = ANCHO_HOJA_MM_IMPRIMIR - (MARGEN_MM_IMPRIMIR * 2);
                  const areaAltoMm = ALTO_HOJA_MM_IMPRIMIR - (MARGEN_MM_IMPRIMIR * 2);
                  const GAP_MM_IMPRIMIR = 2;
                  const cols = Math.floor((areaAnchoMm + GAP_MM_IMPRIMIR) / (anchoMm + GAP_MM_IMPRIMIR));
                  const rows = Math.floor((areaAltoMm + GAP_MM_IMPRIMIR) / (altoMm + GAP_MM_IMPRIMIR));
                  const capacidad = cols * rows;

                  const cuadros = [];
                  Object.keys(cantidadesQR).sort().forEach(clave => {
                    const cantidad = cantidadesQR[clave] || 0;
                    if (cantidad <= 0) return;
                    const partes = clave.split('_');
                    const colorCod = partes[0];
                    const circulo = document.querySelector('[data-fila-talle-qr="' + clave + '"]');
                    const letra = circulo ? circulo.getAttribute('data-letra-talle') : '';
                    const hex = mapaHexColores[colorCod] || '#186904';
                    for (let i = 0; i < cantidad; i++) {
                      cuadros.push({ hex, letra, clave, colorCod });
                    }
                  });

                  const total = cuadros.length;
                  const hojasNecesarias = Math.max(1, Math.ceil(total / capacidad));
                  const texto = document.getElementById('texto-espacios-restantes-imprimir');
                  if (texto) {
                    if (total <= capacidad) {
                      texto.textContent = 'Te quedan ' + (capacidad - total) + ' de ' + capacidad + ' espacios';
                      texto.style.color = '#666';
                    } else {
                      texto.textContent = 'Vas a necesitar ' + hojasNecesarias + ' hojas (' + total + ' etiquetas, ' + capacidad + ' por hoja)';
                      texto.style.color = '#c0392b';
                    }
                  }

                  const contenedor = document.getElementById('hojas-preview-imprimir-container');
                  const contenedorFisico = document.getElementById('imprimir-fisico-container');
                  if (!contenedor) return;
                  contenedor.innerHTML = '';
                  if (contenedorFisico) contenedorFisico.innerHTML = '';

                  for (let h = 0; h < hojasNecesarias; h++) {
                    const wrap = document.createElement('div');
                    wrap.style.width = '100%';
                    wrap.style.maxWidth = '260px';

                    if (hojasNecesarias > 1) {
                      const etiqueta = document.createElement('p');
                      etiqueta.textContent = 'Hoja ' + (h + 1) + ' de ' + hojasNecesarias;
                      etiqueta.style.cssText = 'font-size: 11px; font-weight: 700; color: #186904; text-align: center; margin: 0 0 6px;';
                      wrap.appendChild(etiqueta);
                    }

                    const hojaDiv = document.createElement('div');
                    hojaDiv.style.cssText = 'display: flex; align-items: center; justify-content: center; overflow: hidden; width: 100%; aspect-ratio: 210 / 297; background: white; border: 1.5px solid #ddd; border-radius: 4px; box-shadow: 0 2px 10px rgba(0,0,0,0.08);';
                    wrap.appendChild(hojaDiv);
                    contenedor.appendChild(wrap);

                    const escala = hojaDiv.clientWidth / ANCHO_HOJA_MM_IMPRIMIR;
                    const anchoCeldaPx = anchoMm * escala;
                    const altoCeldaPx = altoMm * escala;
                    const tamanoLetra = Math.max(8, Math.min(anchoCeldaPx, altoCeldaPx) * 0.4);

                    const desde = h * capacidad;
                    const cuadrosHoja = cuadros.slice(desde, desde + capacidad);

                    let html = '';
                    for (let i = 0; i < capacidad; i++) {
                      if (i < cuadrosHoja.length) {
                        const esBlancoPantalla = cuadrosHoja[i].colorCod === '21';
                        html += '<div style="display: flex; align-items: center; justify-content: center; background: ' + cuadrosHoja[i].hex + '; border-radius: 2px; color: ' + (esBlancoPantalla ? '#111' : 'white') + '; font-weight: 700; font-family: Poppins, sans-serif; font-size: ' + tamanoLetra + 'px; ' + (esBlancoPantalla ? 'border: 1px solid #333;' : '') + '">' + cuadrosHoja[i].letra + '</div>';
                      } else {
                        html += '<div style="background: #186904; opacity: 0.75; border-radius: 2px;"></div>';
                      }
                    }

                    hojaDiv.innerHTML = '<div style="display: grid; grid-template-columns: repeat(' + cols + ', ' + anchoCeldaPx + 'px); grid-template-rows: repeat(' + rows + ', ' + altoCeldaPx + 'px); gap: 2px;">' + html + '</div>';

                    if (contenedorFisico) {
                      const qrsPorComboRaw = contenedorFisico.dataset.qrs;
                      let qrsPorCombo = {};
                      try { qrsPorCombo = qrsPorComboRaw ? JSON.parse(qrsPorComboRaw) : {}; } catch (e) { qrsPorCombo = {}; }

                      const hojaFisica = document.createElement('div');
                      hojaFisica.className = 'hoja-imprimir-pagina';
                      hojaFisica.style.cssText = 'width: 210mm; height: 297mm; padding: 10mm; box-sizing: border-box; display: grid; grid-template-columns: repeat(' + cols + ', ' + anchoMm + 'mm); grid-template-rows: repeat(' + rows + ', ' + altoMm + 'mm); gap: 2mm; justify-content: center; align-content: center;';

                      let htmlFisico = '';
                      for (let i = 0; i < capacidad; i++) {
                        if (i < cuadrosHoja.length) {
                          const datosQr = qrsPorCombo[cuadrosHoja[i].clave];
                          if (datosQr) {
                            htmlFisico += '<div style="display: flex; flex-direction: column; align-items: center; justify-content: center; background: white; overflow: hidden; height: 100%; width: 100%; box-sizing: border-box; border: 0.3mm solid #186904; border-radius: 1mm; padding: 1mm;">' +
                              '<div style="flex: 1; width: 100%; min-height: 0; display: flex; align-items: center; justify-content: flex-end;">' + datosQr.svg + '</div>' +
                              '<div style="margin-top: 0.6mm; margin-bottom: 0.6mm; font-size: 2.2mm; font-family: Poppins, sans-serif; font-weight: 700; color: #111; text-align: center; line-height: 1; white-space: nowrap; text-transform: uppercase;">' + datosQr.etiqueta + '</div>' +
                              '</div>';
                          } else {
                            const esBlancoFisico = cuadrosHoja[i].colorCod === '21';
                            htmlFisico += '<div style="display: flex; align-items: center; justify-content: center; background: ' + cuadrosHoja[i].hex + '; color: ' + (esBlancoFisico ? '#111' : 'white') + '; font-weight: 700; font-family: Poppins, sans-serif; font-size: 3mm; ' + (esBlancoFisico ? 'border: 0.3mm solid #333; box-sizing: border-box;' : '') + '">' + cuadrosHoja[i].letra + '</div>';
                          }
                        } else {
                          htmlFisico += '<div></div>';
                        }
                      }
                      hojaFisica.innerHTML = htmlFisico;
                      contenedorFisico.appendChild(hojaFisica);
                    }
                  }
                };

                let scrollYAntesDeImprimirStock = 0;

                window.abrirImpresionQRStock = () => {
                  const articuloActualImprimir = this.el.dataset.articulo || '';
                  if (articuloActualImprimir !== ultimoArticuloImprimir) {
                    cantidadesQR = {};
                    document.querySelectorAll('[id^="cantidad-qr-input-"]').forEach(input => { input.value = 0; });
                    ultimoArticuloImprimir = articuloActualImprimir;
                  }
                  scrollYAntesDeImprimirStock = window.scrollY;
                  document.getElementById('contenido-formulario-producto-stock').style.display = 'none';
                  document.getElementById('pantalla-imprimir-stock').style.display = 'block';
                  const breadcrumb = document.getElementById('breadcrumb-stock-categoria');
                  if (breadcrumb) breadcrumb.style.display = 'none';
                  const tarjetaChico = document.querySelector('.tarjeta-tamano-imprimir[data-tamano="chico"]');
                  if (tarjetaChico) elegirTamanoImprimir(tarjetaChico);
                  window.scrollTo(0, 0);
                  const botonAbrirImprimirReal = document.getElementById('boton-abrir-pantalla-imprimir-real-stock');
                  if (botonAbrirImprimirReal) botonAbrirImprimirReal.click();


                };

                window.cerrarPantallaImprimirStock = () => {
                  document.getElementById('pantalla-imprimir-stock').style.display = 'none';
                  document.getElementById('contenido-formulario-producto-stock').style.display = 'block';
                  const breadcrumb = document.getElementById('breadcrumb-stock-categoria');
                  if (breadcrumb) breadcrumb.style.display = 'block';
                  window.scrollTo(0, scrollYAntesDeImprimirStock);
                  const botonCerrarImprimirReal = document.getElementById('boton-cerrar-pantalla-imprimir-real-stock');
                  if (botonCerrarImprimirReal) botonCerrarImprimirReal.click();
                };

                let modoImpresionTermicoActual = 'dale9';
                let anchoTermicoSeleccionado = 58;
                let cantidadesTermico = {};
                let ultimoArticuloTermico = null;
                let scrollYAntesDeImprimirTermico = 0;

                window.abrirImpresionTermica = (modo) => {
                  modoImpresionTermicoActual = modo;
                  const articuloActualTermico = this.el.dataset.articulo || '';
                  if (articuloActualTermico !== ultimoArticuloTermico) {
                    cantidadesTermico = {};
                    document.querySelectorAll('[id^="cantidad-termico-input-"]').forEach(input => { input.value = 0; });
                    ultimoArticuloTermico = articuloActualTermico;
                  }
                  const titulo = document.getElementById('titulo-imprimir-termico-stock');
                  if (titulo) titulo.textContent = modo === 'ean13' ? 'Imprimir código EAN-13' : 'Imprimir código DALE9';
                  scrollYAntesDeImprimirTermico = window.scrollY;
                  document.getElementById('contenido-formulario-producto-stock').style.display = 'none';
                  document.getElementById('pantalla-imprimir-termico-stock').style.display = 'block';
                  const breadcrumb = document.getElementById('breadcrumb-stock-categoria');
                  if (breadcrumb) breadcrumb.style.display = 'none';
                  actualizarPreviewTermico();
                  window.scrollTo(0, 0);
                };

                window.cerrarPantallaImprimirTermico = () => {
                  document.getElementById('pantalla-imprimir-termico-stock').style.display = 'none';
                  document.getElementById('contenido-formulario-producto-stock').style.display = 'block';
                  const breadcrumb = document.getElementById('breadcrumb-stock-categoria');
                  if (breadcrumb) breadcrumb.style.display = 'block';
                  window.scrollTo(0, scrollYAntesDeImprimirTermico);
                };

                window.elegirAnchoTermico = (btn) => {
                  document.querySelectorAll('.tarjeta-ancho-termico').forEach(b => {
                    b.style.borderColor = '#cfe4cf';
                    b.style.background = 'white';
                  });
                  btn.style.borderColor = '#186904';
                  btn.style.background = '#e6f4e6';
                  anchoTermicoSeleccionado = parseFloat(btn.dataset.anchoMm);
                  actualizarPreviewTermico();
                };

                window.cambiarCantidadTermico = (clave, delta) => {
                  const actual = cantidadesTermico[clave] || 0;
                  const nuevo = Math.max(0, Math.min(9999, actual + delta));
                  cantidadesTermico[clave] = nuevo;
                  const input = document.getElementById('cantidad-termico-input-' + clave);
                  if (input) input.value = nuevo;
                  actualizarPreviewTermico();
                };

                window.setCantidadTermico = (clave, valor) => {
                  let n = parseInt(valor) || 0;
                  n = Math.max(0, Math.min(9999, n));
                  cantidadesTermico[clave] = n;
                  const input = document.getElementById('cantidad-termico-input-' + clave);
                  if (input) input.value = n;
                  actualizarPreviewTermico();
                };

                window.actualizarPreviewTermico = () => {
                  const contenedorDatos = document.getElementById('imprimir-termico-container');
                  const previewContainer = document.getElementById('preview-termico-container');
                  const fisicoContainer = document.getElementById('imprimir-termico-fisico-container');
                  if (!contenedorDatos || !previewContainer || !fisicoContainer) return;

                  let barrasPorCombo = {};
                  try { barrasPorCombo = JSON.parse(contenedorDatos.dataset.barras || '{}'); } catch (e) { barrasPorCombo = {}; }

                  const cuadros = [];
                  Object.keys(cantidadesTermico).sort().forEach(clave => {
                    const cantidad = cantidadesTermico[clave] || 0;
                    if (cantidad <= 0) return;
                    for (let i = 0; i < cantidad; i++) cuadros.push(clave);
                  });

                  previewContainer.innerHTML = '';
                  fisicoContainer.innerHTML = '';

                  if (cuadros.length === 0) {
                    previewContainer.innerHTML = '<span style="font-size: 11px; color: #999;">Cargá cantidades abajo para ver la vista previa</span>';
                  }

                  const anchoPreviewPx = Math.min(260, anchoTermicoSeleccionado * 3.4);

                  cuadros.forEach(clave => {
                    const datos = barrasPorCombo[clave];
                    if (!datos) return;
                    const svg = modoImpresionTermicoActual === 'ean13' ? datos.svg_ean13 : datos.svg_dale9;
                    const codigoTexto = modoImpresionTermicoActual === 'ean13' ? datos.codigo_ean13 : datos.codigo_dale9;

                    const etiquetaPreview = document.createElement('div');
                    etiquetaPreview.style.cssText = 'width: ' + anchoPreviewPx + 'px; background: white; border: 1px dashed #ccc; border-radius: 4px; padding: 6px; text-align: center; flex-shrink: 0;';
                    etiquetaPreview.innerHTML = svg + '<div style="font-size: 9px; font-family: monospace; letter-spacing: 1px; margin-top: 2px; color: #333;">' + codigoTexto + '</div><div style="font-size: 8px; color: #999; text-transform: uppercase; margin-top: 1px;">' + datos.etiqueta + '</div>';
                    previewContainer.appendChild(etiquetaPreview);

                    const etiquetaFisica = document.createElement('div');
                    etiquetaFisica.className = 'etiqueta-termica-pagina';
                    etiquetaFisica.style.cssText = 'width: ' + anchoTermicoSeleccionado + 'mm; box-sizing: border-box; padding: 2mm; text-align: center; border-bottom: 0.2mm dashed #999;';
                    etiquetaFisica.innerHTML = svg + '<div style="font-size: 2.6mm; font-family: monospace; letter-spacing: 0.5mm; margin-top: 0.5mm; color: #000;">' + codigoTexto + '</div><div style="font-size: 2.2mm; color: #333; text-transform: uppercase; margin-top: 0.3mm;">' + datos.etiqueta + '</div>';
                    fisicoContainer.appendChild(etiquetaFisica);
                  });

                  let estiloPagina = document.getElementById('estilo-pagina-termica');
                  if (!estiloPagina) {
                    estiloPagina = document.createElement('style');
                    estiloPagina.id = 'estilo-pagina-termica';
                    document.head.appendChild(estiloPagina);
                  }
                  estiloPagina.textContent = '@page { size: ' + anchoTermicoSeleccionado + 'mm auto; margin: 0; }';
                };

                window.imprimirHojaTermica = () => {
                  const original = document.getElementById('imprimir-termico-fisico-container');
                  if (!original || !original.children.length) { window.print(); return; }

                  const existente = document.getElementById('imprimir-termico-clon');
                  if (existente) existente.remove();

                  const clon = original.cloneNode(true);
                  clon.id = 'imprimir-termico-clon';
                  clon.style.display = 'none';
                  document.body.appendChild(clon);

                  window.print();

                  setTimeout(() => {
                    const clonViejo = document.getElementById('imprimir-termico-clon');
                    if (clonViejo) clonViejo.remove();
                  }, 2000);
                };

                window.hayDatosSinGuardarStock = () => {
                  const nombre = (document.getElementById('input-nombre-stock')?.value || '').trim();
                  const precio = (document.getElementById('input-precio-stock')?.value || '').trim();
                  const descripcion = (document.getElementById('input-descripcion-stock')?.value || '').trim();
                  const tieneCantidades = Object.keys(cantidadesStock).length > 0;
                  return !!(nombre || precio || descripcion || imagenBlobStock || tieneCantidades);
                };

                window.manejarClickVolverFormularioStock = () => {
                  const pantallaImprimir = document.getElementById('pantalla-imprimir-stock');
                  const pantallaTermica = document.getElementById('pantalla-imprimir-termico-stock');
                  if (pantallaImprimir && pantallaImprimir.style.display !== 'none') {
                    cerrarPantallaImprimirStock();
                  } else if (pantallaTermica && pantallaTermica.style.display !== 'none') {
                    cerrarPantallaImprimirTermico();
                  } else {
                    const botonReal = document.getElementById('boton-cerrar-formulario-real-stock');
                    if (!editandoArticuloActivo && hayDatosSinGuardarStock()) {
                      mostrarAvisoStock(
                        'Aviso',
                        'Si salís ahora vas a perder todo lo que cargaste en este producto. ¿Estás seguro?',
                        () => { if (botonReal) botonReal.click(); },
                        'Salir sin guardar',
                        '#c0392b'
                      );
                    } else if (editandoArticuloActivo) {
                      const nombreActual = (document.getElementById('input-nombre-stock')?.value || '').trim();
                      const precioActual = parseInt((document.getElementById('input-precio-stock')?.value || '').trim()) || 0;
                      const descripcionActual = (document.getElementById('input-descripcion-stock')?.value || '').trim();
                      const cambios = calcularCambiosStock(nombreActual, precioActual, descripcionActual);
                      if (cambios.length > 0) {
                        mostrarAvisoStock(
                          'Aviso',
                          'Tenés cambios sin guardar en este producto:\n\n• ' + cambios.join('\n• ') + '\n\nSi salís ahora los vas a perder. ¿Estás seguro?',
                          () => { if (botonReal) botonReal.click(); },
                          'Salir sin guardar',
                          '#c0392b',
                          () => { enviarProductoStock(nombreActual, precioActual, descripcionActual); },
                          'Guardar cambios',
                          '#186904'
                        );
                      } else {
                        if (botonReal) botonReal.click();
                      }
                    } else {
                      if (botonReal) botonReal.click();
                    }
                  }
                };

                window.actualizarFilasCantidadStock = () => {
                  const cont = document.getElementById('filas-cantidad-stock');
                  if (!cont) return;

                  const talles = tallesElegidos.length > 0 ? tallesElegidos : (talleCodigoElegido ? [talleCodigoElegido] : []);
                  const colores = coloresElegidos.length > 0 ? coloresElegidos : (colorCodigoElegido ? [colorCodigoElegido] : []);

                  if (talles.length === 0 || colores.length === 0) {
                    cont.innerHTML = '<p style="font-size: 12px; color: #bbb; text-align: center; margin: 8px 0; font-family: Poppins, sans-serif;">Elegí talle y color para cargar cantidad</p>';
                    return;
                  }

                  const clavesNuevas = new Set();
                  let html = '';

                  colores.forEach(colorCod => {
                    talles.forEach(talleCod => {
                      const clave = colorCod + '_' + talleCod;
                      if (clavesExcluidasStock.has(clave)) return;
                      clavesNuevas.add(clave);
                      if (!(clave in cantidadesStock)) cantidadesStock[clave] = 0;

                      const hex = mapaHexColores[colorCod] || '#ccc';
                      const btnTalle = document.querySelector('#talles-letra-stock button[data-codigo-talle="' + talleCod + '"]');
                      const nombreTalle = btnTalle ? btnTalle.getAttribute('data-talle') : talleCod;
                      const btnColor = document.querySelector('#colores-stock button[data-codigo-color="' + colorCod + '"]');
                      const nombreColor = btnColor ? btnColor.getAttribute('data-color') : colorCod;
                      const cantidad = cantidadesStock[clave];

                      html += '<div style="display: flex; align-items: center; gap: 10px; padding: 8px 10px; background: #f9f9f9; border-radius: 12px;">' +
                        '<span style="width: 22px; height: 22px; border-radius: 50%; background: ' + hex + '; flex-shrink: 0; ' + (colorCod === '21' ? 'border: 1.5px solid #e0e0e0;' : '') + '"></span>' +
                        '<span style="font-size: 13px; font-weight: 700; color: #333; flex: 1;">' + nombreTalle + '</span>' +
                        '<div style="display: flex; align-items: center; gap: 6px;">' +
                        '<button type="button" onclick="cambiarCantidadStock(\'' + clave + '\', -1)" style="width: 26px; height: 26px; border-radius: 8px; border: 1.5px solid #cfe4cf; background: white; color: #186904; font-size: 16px; cursor: pointer; display: flex; align-items: center; justify-content: center; padding: 0;">-</button>' +
                        '<input type="number" id="cantidad-input-' + clave + '" value="' + cantidad + '" min="0" max="9999" oninput="setCantidadStock(\'' + clave + '\', this.value)" style="width: 48px; text-align: center; padding: 5px 2px; border: 1.5px solid #cfe4cf; border-radius: 8px; font-family: Poppins, sans-serif; font-size: 13px; outline: none;"/>' +
                        '<button type="button" onclick="cambiarCantidadStock(\'' + clave + '\', 1)" style="width: 26px; height: 26px; border-radius: 8px; border: 1.5px solid #cfe4cf; background: white; color: #186904; font-size: 16px; cursor: pointer; display: flex; align-items: center; justify-content: center; padding: 0;">+</button>' +
                        '<button type="button" onclick="pedirEliminarFilaStock(\'' + clave + '\', \'' + nombreTalle + '\', \'' + nombreColor + '\')" style="width: 26px; height: 26px; border-radius: 8px; border: none; background: none; color: #c0392b; cursor: pointer; display: flex; align-items: center; justify-content: center; padding: 0;"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1 -2 2h-8a2 2 0 0 1 -2 -2l-1 -14"/><path d="M10 11v6"/><path d="M14 11v6"/><path d="M9 6v-2a1 1 0 0 1 1 -1h4a1 1 0 0 1 1 1v2"/></svg></button>' +
                        '</div></div>';
                    });
                  });

                  Object.keys(cantidadesStock).forEach(clave => {
                    if (!clavesNuevas.has(clave)) delete cantidadesStock[clave];
                  });

                  cont.innerHTML = html;
                  actualizarImagenesPorColorStock();
                };

                window.cambiarCantidadStock = (clave, delta) => {
                  const actual = cantidadesStock[clave] || 0;
                  const nuevo = Math.max(0, Math.min(9999, actual + delta));
                  cantidadesStock[clave] = nuevo;
                  const input = document.getElementById('cantidad-input-' + clave);
                  if (input) input.value = nuevo;
                };

                window.setCantidadStock = (clave, valor) => {
                  let n = parseInt(valor) || 0;
                  n = Math.max(0, Math.min(9999, n));
                  cantidadesStock[clave] = n;
                  const input = document.getElementById('cantidad-input-' + clave);
                  if (input) input.value = n;
                };

                let claveAEliminarStock = null;

                window.pedirEliminarFilaStock = (clave, nombreTalle, nombreColor) => {
                  claveAEliminarStock = clave;
                  const modal = document.getElementById('modal-confirmar-borrar-fila-stock');
                  const texto = document.getElementById('texto-confirmar-borrar-fila-stock');
                  if (texto) texto.textContent = '\u00bfEst\u00e1s seguro de eliminar ' + nombreColor + ' talle ' + nombreTalle + '?';
                  if (modal) modal.style.display = 'flex';
                };

                window.cerrarConfirmarBorrarFilaStock = () => {
                  claveAEliminarStock = null;
                  const modal = document.getElementById('modal-confirmar-borrar-fila-stock');
                  if (modal) modal.style.display = 'none';
                };

                window.confirmarEliminarFilaStock = () => {
                  if (!claveAEliminarStock) return;
                  clavesExcluidasStock.add(claveAEliminarStock);
                  delete cantidadesStock[claveAEliminarStock];

                  cerrarConfirmarBorrarFilaStock();
                  actualizarFilasCantidadStock();
                };

                window.toggleMultiTalleStock = () => {
                  multiTalleActivo = !multiTalleActivo;
                  const sw = document.getElementById('switch-multi-talle-stock');
                  if (multiTalleActivo) {
                    sw.style.background = '#186904'; sw.style.justifyContent = 'flex-end';
                  } else {
                    sw.style.background = '#ccc'; sw.style.justifyContent = 'flex-start';
                    tallesElegidos = [];
                    talleCodigoElegido = null;
                    document.querySelectorAll('#talles-letra-stock button').forEach(b => {
                      b.style.background = 'white'; b.style.color = '#186904'; b.style.borderColor = '#cfe4cf';
                    });
                  }
                  actualizarPreviewCodigoStock();
                };

                window.toggleMultiColorStock = () => {
                  multiColorActivo = !multiColorActivo;
                  const sw = document.getElementById('switch-multi-color-stock');
                  if (multiColorActivo) {
                    sw.style.background = '#186904'; sw.style.justifyContent = 'flex-end';
                  } else {
                    sw.style.background = '#ccc'; sw.style.justifyContent = 'flex-start';
                    coloresElegidos = [];
                    colorCodigoElegido = null;
                    document.querySelectorAll('#colores-stock button').forEach(b => {
                      const anillo = b.querySelector('.anillo-color-stock');
                      const check = b.querySelector('.check-color-stock');
                      if (anillo) anillo.style.borderColor = 'transparent';
                      if (check) check.style.opacity = '0';
                    });
                    const texto = document.getElementById('color-elegido-texto-stock');
                    if (texto) texto.textContent = '';
                  }
                  actualizarPreviewCodigoStock();
                };

                window.seleccionarColorStock = (btn) => {
                  const codigo = btn.getAttribute('data-codigo-color');
                  const yaElegidoAntes = multiColorActivo ? coloresElegidos.includes(codigo) : (colorCodigoElegido === codigo);

                  const coloresOriginales = datosOriginalesStock
                    ? new Set(Object.keys(datosOriginalesStock.variantes || {}).map(clave => clave.split('_')[0]))
                    : new Set();
                  const esColorNuevoDelProducto = editandoArticuloActivo && !yaElegidoAntes && !coloresOriginales.has(codigo);

                  if (esColorNuevoDelProducto) {
                    mostrarAvisoStock(
                      'Aviso',
                      '¿Estás seguro que querés agregar el color "' + btn.getAttribute('data-color') + '" a este producto?',
                      () => { aplicarSeleccionColorStock(btn, codigo); },
                      'Agregar color',
                      '#186904'
                    );
                    return;
                  }

                  aplicarSeleccionColorStock(btn, codigo);
                };

                window.aplicarSeleccionColorStock = (btn, codigo) => {
                  if (multiColorActivo) {
                    const yaElegido = coloresElegidos.includes(codigo);
                    if (yaElegido) {
                      coloresElegidos = coloresElegidos.filter(c => c !== codigo);
                      const anillo = btn.querySelector('.anillo-color-stock');
                      const check = btn.querySelector('.check-color-stock');
                      if (anillo) anillo.style.borderColor = 'transparent';
                      if (check) check.style.opacity = '0';
                    } else {
                      coloresElegidos.push(codigo);
                      const anillo = btn.querySelector('.anillo-color-stock');
                      const check = btn.querySelector('.check-color-stock');
                      if (anillo) anillo.style.borderColor = '#186904';
                      if (check) check.style.opacity = '1';
                    }
                    colorCodigoElegido = coloresElegidos.length === 1 ? coloresElegidos[0] : null;
                  } else {
                    document.querySelectorAll('#colores-stock button').forEach(b => {
                      const anillo = b.querySelector('.anillo-color-stock');
                      const check = b.querySelector('.check-color-stock');
                      if (anillo) anillo.style.borderColor = 'transparent';
                      if (check) check.style.opacity = '0';
                    });
                    const anillo = btn.querySelector('.anillo-color-stock');
                    const check = btn.querySelector('.check-color-stock');
                    if (anillo) anillo.style.borderColor = '#186904';
                    if (check) check.style.opacity = '1';
                    colorCodigoElegido = codigo;
                    coloresElegidos = [codigo];
                  }
                  const texto = document.getElementById('color-elegido-texto-stock');
                  if (texto) texto.textContent = coloresElegidos.length > 1 ? coloresElegidos.length + ' colores elegidos' : 'Color elegido: ' + btn.getAttribute('data-color');
                  actualizarPreviewCodigoStock();
                };

                window.cambiarModoTalleStock = (modo) => {
                  const btnLetra = document.getElementById('btn-modo-letra-stock');
                  const btnNumerico = document.getElementById('btn-modo-numerico-stock');
                  const divLetra = document.getElementById('talles-letra-stock');
                  const divNumerico = document.getElementById('talles-numerico-stock');
                  if (modo === 'letra') {
                    divLetra.style.display = 'flex';
                    divNumerico.style.display = 'none';
                    btnLetra.style.background = '#186904'; btnLetra.style.color = 'white';
                    btnNumerico.style.background = 'white'; btnNumerico.style.color = '#186904';
                  } else {
                    divLetra.style.display = 'none';
                    divNumerico.style.display = 'block';
                    btnNumerico.style.background = '#186904'; btnNumerico.style.color = 'white';
                    btnLetra.style.background = 'white'; btnLetra.style.color = '#186904';
                  }
                  actualizarPreviewCodigoStock();
                };

                window.toggleTalleStock = (btn) => {
                  const codigo = btn.getAttribute('data-codigo-talle');
                  const yaElegidoAntes = multiTalleActivo ? tallesElegidos.includes(codigo) : (talleCodigoElegido === codigo);

                  const tallesOriginales = datosOriginalesStock
                    ? new Set(Object.keys(datosOriginalesStock.variantes || {}).map(clave => clave.split('_')[1]))
                    : new Set();
                  const esTalleNuevoDelProducto = editandoArticuloActivo && !yaElegidoAntes && !tallesOriginales.has(codigo);

                  if (esTalleNuevoDelProducto) {
                    mostrarAvisoStock(
                      'Aviso',
                      '¿Estás seguro que querés agregar el talle "' + btn.textContent.trim() + '" a este producto?',
                      () => { aplicarToggleTalleStock(btn, codigo); },
                      'Agregar talle',
                      '#186904'
                    );
                    return;
                  }

                  aplicarToggleTalleStock(btn, codigo);
                };

                window.aplicarToggleTalleStock = (btn, codigo) => {
                  if (multiTalleActivo) {
                    const yaElegido = tallesElegidos.includes(codigo);
                    if (yaElegido) {
                      tallesElegidos = tallesElegidos.filter(t => t !== codigo);
                      btn.style.background = 'white'; btn.style.color = '#186904'; btn.style.borderColor = '#cfe4cf';
                    } else {
                      tallesElegidos.push(codigo);
                      btn.style.background = '#186904'; btn.style.color = 'white'; btn.style.borderColor = '#186904';
                    }
                    talleCodigoElegido = tallesElegidos.length === 1 ? tallesElegidos[0] : null;
                  } else {
                    document.querySelectorAll('#talles-letra-stock button').forEach(b => {
                      b.style.background = 'white'; b.style.color = '#186904'; b.style.borderColor = '#cfe4cf';
                    });
                    btn.style.background = '#186904'; btn.style.color = 'white'; btn.style.borderColor = '#186904';
                    talleCodigoElegido = codigo;
                    tallesElegidos = [codigo];
                  }
                  actualizarPreviewCodigoStock();
                };
                window.mostrarAvisoStock = (titulo, mensaje, onConfirmar, textoConfirmar, colorConfirmar, onAccionExtra, textoAccionExtra, colorAccionExtra) => {
                  let modal = document.getElementById('modal-aviso-generico-stock');
                  if (!modal) {
                    modal = document.createElement('div');
                    modal.id = 'modal-aviso-generico-stock';
                    modal.style.cssText = 'display: none; position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.45); z-index: 9999; align-items: center; justify-content: center;';
                    modal.innerHTML = '<div style="background: #fff; border-radius: 28px; width: 300px; max-width: 85%; padding: 28px 24px; box-shadow: 0 12px 40px rgba(0,0,0,0.25); text-align: center;">' +
                      '<p id="titulo-aviso-generico-stock" style="font-size: 13px; font-weight: 700; color: #186904; margin: 0 0 8px; text-transform: uppercase; letter-spacing: 1px; font-family: Poppins, sans-serif;"></p>' +
                      '<p id="texto-aviso-generico-stock" style="font-size: 14px; color: #111; margin: 0 0 20px; font-family: Poppins, sans-serif; white-space: pre-line; text-align: left;"></p>' +
                      '<div id="botones-aviso-generico-stock" style="display: flex; flex-direction: column; gap: 8px;"></div>' +
                      '</div>';
                    document.body.appendChild(modal);
                  }
                  document.getElementById('titulo-aviso-generico-stock').textContent = titulo;
                  document.getElementById('texto-aviso-generico-stock').textContent = mensaje;
                  const botones = document.getElementById('botones-aviso-generico-stock');
                  botones.innerHTML = '';

                  if (onAccionExtra) {
                    const btnExtra = document.createElement('button');
                    btnExtra.type = 'button';
                    btnExtra.textContent = textoAccionExtra || 'Guardar';
                    btnExtra.style.cssText = 'width: 100%; padding: 10px; border: none; border-radius: 8px; background: ' + (colorAccionExtra || '#186904') + '; color: white; cursor: pointer; font-size: 14px; font-weight: 600; font-family: Poppins, sans-serif;';
                    btnExtra.onclick = () => { modal.style.display = 'none'; onAccionExtra(); };
                    botones.appendChild(btnExtra);
                  }

                  if (onConfirmar) {
                    const btnConfirmar = document.createElement('button');
                    btnConfirmar.type = 'button';
                    btnConfirmar.textContent = textoConfirmar || 'Confirmar';
                    btnConfirmar.style.cssText = 'width: 100%; padding: 10px; border: 1.5px solid ' + (colorConfirmar || '#186904') + '; border-radius: 8px; background: white; color: ' + (colorConfirmar || '#186904') + '; cursor: pointer; font-size: 14px; font-weight: 600; font-family: Poppins, sans-serif;';
                    btnConfirmar.onclick = () => { modal.style.display = 'none'; onConfirmar(); };
                    botones.appendChild(btnConfirmar);
                  }

                  const btnCancelar = document.createElement('button');
                  btnCancelar.type = 'button';
                  btnCancelar.textContent = (onConfirmar || onAccionExtra) ? 'Seguir editando' : 'Entendido';
                  btnCancelar.style.cssText = 'width: 100%; padding: 10px; border: none; border-radius: 8px; background: none; color: #999; cursor: pointer; font-size: 13px; font-family: Poppins, sans-serif;';
                  btnCancelar.onclick = () => { modal.style.display = 'none'; };
                  botones.appendChild(btnCancelar);

                  modal.style.display = 'flex';
                };

                window.nombreColorPorCodigoStock = (cod) => {
                  const btn = document.querySelector('#colores-stock button[data-codigo-color="' + cod + '"]');
                  return btn ? btn.getAttribute('data-color') : cod;
                };

                window.nombreTallePorCodigoStock = (cod) => {
                  const btn = document.querySelector('#talles-letra-stock button[data-codigo-talle="' + cod + '"]');
                  return btn ? btn.getAttribute('data-talle') : cod;
                };

                window.calcularCambiosStock = (nombre, precio, descripcion) => {
                  const cambios = [];
                  if (!datosOriginalesStock) return cambios;

                  if (nombre !== datosOriginalesStock.nombre) {
                    cambios.push('Nombre: "' + datosOriginalesStock.nombre + '" → "' + nombre + '"');
                  }
                  if (precio !== datosOriginalesStock.precio) {
                    cambios.push('Precio: $' + datosOriginalesStock.precio + ' → $' + precio);
                  }
                  if (descripcion !== datosOriginalesStock.descripcion) {
                    cambios.push('Descripción modificada');
                  }

                  const clavesViejas = datosOriginalesStock.variantes || {};
                  const todasLasClaves = new Set([...Object.keys(clavesViejas), ...Object.keys(cantidadesStock)]);
                  todasLasClaves.forEach(clave => {
                    const [cc, ct] = clave.split('_');
                    const nombreCombo = nombreColorPorCodigoStock(cc) + ' ' + nombreTallePorCodigoStock(ct);
                    const cantVieja = clavesViejas[clave] || 0;
                    const cantNueva = cantidadesStock[clave] || 0;
                    if (cantVieja === 0 && cantNueva > 0) {
                      cambios.push('Agregado: ' + nombreCombo + ' (' + cantNueva + ' unidades)');
                    } else if (cantVieja > 0 && cantNueva === 0) {
                      cambios.push('Quitado: ' + nombreCombo);
                    } else if (cantVieja !== cantNueva) {
                      cambios.push(nombreCombo + ': ' + cantVieja + ' → ' + cantNueva + ' unidades');
                    }
                  });

                  return cambios;
                };

                window.guardarProductoStock = () => {
                  const nombre = document.getElementById('input-nombre-stock').value.trim();
                  const precioRaw = document.getElementById('input-precio-stock').value.trim();
                  const precio = parseInt(precioRaw) || 0;
                  const descripcion = document.getElementById('input-descripcion-stock').value.trim();

                  const faltantes = [];
                  if (!nombre) faltantes.push('El nombre del producto');
                  if (!precioRaw || precio <= 0) faltantes.push('El precio (no puede ser $0)');
                  const claves = Object.keys(cantidadesStock);
                  if (claves.length === 0) faltantes.push('Al menos un color y talle con cantidad cargada');
                  if (agregarADaleStandActivo && !imagenBlobStock) {
                    faltantes.push('Al menos una foto (obligatoria para productos en tu Stand Dale)');
                  }

                  if (faltantes.length > 0) {
                    mostrarAvisoStock('Faltan datos', 'Antes de guardar, completá:\n\n• ' + faltantes.join('\n• '), null);
                    return;
                  }

                  if (editandoArticuloActivo) {
                    const cambios = calcularCambiosStock(nombre, precio, descripcion);
                    if (cambios.length > 0) {
                      mostrarAvisoStock(
                        'Vas a guardar estos cambios',
                        '• ' + cambios.join('\n• '),
                        () => { enviarProductoStock(nombre, precio, descripcion); },
                        'Guardar cambios',
                        '#186904'
                      );
                      return;
                    }
                  }

                  enviarProductoStock(nombre, precio, descripcion);
                };

                const enviarProductoStock = async (nombre, precio, descripcion) => {
                  const formData = new FormData();
                  formData.append('_csrf_token', csrfTokenStock);
                  formData.append('nombre', nombre);
                  formData.append('precio_original', precio);
                  formData.append('precio_final', precio);
                  formData.append('descripcion', descripcion);
                  formData.append('codigo_tipo', codigoTipo);
                  formData.append('variantes', JSON.stringify(cantidadesStock));

                  const btn = document.getElementById('boton-guardar-stock');
                  btn.textContent = "Guardando..."; btn.disabled = true;

                  const url = editandoArticuloActivo ? '/mi-tienda/stock/actualizar-articulo' : '/mi-tienda/stock/crear-articulo';
                  if (editandoArticuloActivo) {
                    formData.append('productos_por_color', JSON.stringify(productosPorColorEditando));
                  }

                  const res = await fetch(url, { method: 'POST', body: formData });
                  const data = await res.json();

                  if (data.ok) {
                    if (imagenBlobStock && data.ids) {
                      const extension = imagenBlobStock.type && imagenBlobStock.type.includes('png') ? 'png'
                        : (imagenBlobStock.type && imagenBlobStock.type.includes('webp') ? 'webp' : 'jpg');
                      for (const id of data.ids) {
                        const imgForm = new FormData();
                        imgForm.append('_csrf_token', csrfTokenStock);
                        imgForm.append('imagen', imagenBlobStock, 'producto.' + extension);
                        await fetch('/mi-tienda/stock/productos/' + id + '/imagen', { method: 'POST', body: imgForm });
                      }
                    }
                    window.location.href = '/mi-tienda/stock?categoria=' + codigoTipo;
                  } else {
                    btn.textContent = editandoArticuloActivo ? "Guardar cambios" : "Guardar producto"; btn.disabled = false;
                    alert('Error al guardar.');
                  }
                };

                const datosArticuloRaw = this.el.dataset.articulo;
                if (datosArticuloRaw && datosArticuloRaw !== "") {
                  try {
                    const datos = JSON.parse(datosArticuloRaw);
                    if (datos && datos.variantes) {
                      editandoArticuloActivo = true;
                      productosPorColorEditando = datos.productos_por_color || {};
                      datosOriginalesStock = {
                        nombre: datos.nombre || '',
                        precio: datos.precio || 0,
                        descripcion: datos.descripcion || '',
                        variantes: JSON.parse(JSON.stringify(datos.variantes || {}))
                      };

                      document.getElementById('input-nombre-stock').value = datos.nombre || '';
                      document.getElementById('input-precio-stock').value = datos.precio || '';
                      document.getElementById('input-descripcion-stock').value = datos.descripcion || '';
                      actualizarPreviewStock();
                      limitarPalabrasStock(document.getElementById('input-descripcion-stock'));

                      if (datos.imagen) {
                        const imgFondo = document.getElementById('preview-img-fondo-stock');
                        const imgPreview = document.getElementById('preview-img-stock');
                        imgFondo.src = datos.imagen; imgFondo.style.display = 'block';
                        imgPreview.src = datos.imagen; imgPreview.style.display = 'block';
                        document.getElementById('preview-placeholder-stock').style.display = 'none';
                      }

                      const clavesColorTalle = Object.keys(datos.variantes);
                      const coloresUnicos = [...new Set(clavesColorTalle.map(c => c.split('_')[0]))];
                      const tallesUnicos = [...new Set(clavesColorTalle.map(c => c.split('_')[1]))];

                      if (tallesUnicos.length > 1) window.toggleMultiTalleStock();
                      tallesUnicos.forEach(codigo => {
                        const btn = document.querySelector('#talles-letra-stock button[data-codigo-talle="' + codigo + '"]');
                        if (btn) btn.click();
                      });

                      if (coloresUnicos.length > 1) window.toggleMultiColorStock();
                      coloresUnicos.forEach(codigo => {
                        const btn = document.querySelector('#colores-stock button[data-codigo-color="' + codigo + '"]');
                        if (btn) btn.click();
                      });

                      clavesColorTalle.forEach(clave => {
                        window.setCantidadStock(clave, datos.variantes[clave]);
                      });

                      const btnGuardar = document.getElementById('boton-guardar-stock');
                      if (btnGuardar) btnGuardar.textContent = 'Guardar cambios';

                      const textoVistaPrevia = document.getElementById('texto-vista-previa-qr-stock');
                      const botonImprimir = document.getElementById('boton-imprimir-qr-stock');
                      if (textoVistaPrevia) textoVistaPrevia.style.display = 'none';
                      if (botonImprimir) botonImprimir.style.display = 'inline-block';
                    }
                  } catch (e) { /* noop */ }
                }

                actualizarImagenesPorColorStock();
                if (this.el.dataset.mostrarImprimir === 'true') {
                  const tarjetaChico = document.querySelector('.tarjeta-tamano-imprimir[data-tamano="chico"]');
                  if (tarjetaChico) elegirTamanoImprimir(tarjetaChico);
                }
                const comboDestacado = this.el.dataset.comboDestacado;
                if (comboDestacado) {
                  setTimeout(() => {
                    const inputDestacado = document.getElementById('cantidad-input-' + comboDestacado);
                    const filaDestacada = inputDestacado ? inputDestacado.closest('div[style*="background: #f9f9f9"]') : null;
                    if (filaDestacada) {
                      filaDestacada.scrollIntoView({ behavior: 'smooth', block: 'center' });
                      const colorOriginal = filaDestacada.style.background;
                      filaDestacada.style.transition = 'background 0.3s ease';
                      filaDestacada.style.background = '#fdecea';
                      setTimeout(() => { filaDestacada.style.background = colorOriginal || '#f9f9f9'; }, 2200);
                    }
                  }, 400);
                }

                if (typeof ResizeObserver !== 'undefined') {
                  const contenedorObservadoImprimir = document.getElementById('hojas-preview-imprimir-container');
                  if (contenedorObservadoImprimir) {
                    const resizeObserverImprimir = new ResizeObserver(() => {
                      if (typeof window.actualizarPreviewImprimir === 'function') window.actualizarPreviewImprimir();
                    });
                    resizeObserverImprimir.observe(contenedorObservadoImprimir);
                  }
                }
              }
            }
          </script>

          <div id="modal-confirmar-borrar-fila-stock" style="display: none; position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.45); z-index: 9999; align-items: center; justify-content: center;">
            <div style="background: #fff; border-radius: 28px; width: 300px; max-width: 85%; padding: 28px 24px; box-shadow: 0 12px 40px rgba(0,0,0,0.25); text-align: center;">
              <p style="font-size: 13px; font-weight: 700; color: #186904; margin: 0 0 8px; text-transform: uppercase; letter-spacing: 1px; font-family: Poppins, sans-serif;">Aviso</p>
              <p id="texto-confirmar-borrar-fila-stock" style="font-size: 14px; color: #111; margin: 0 0 20px; font-family: Poppins, sans-serif;"></p>
              <div style="display: flex; gap: 10px;">
                <button type="button" onclick="cerrarConfirmarBorrarFilaStock()" style="flex: 1; padding: 10px; border: 1.5px solid #ddd; border-radius: 8px; background: white; cursor: pointer; font-size: 14px; font-family: Poppins, sans-serif;">Cancelar</button>
                <button type="button" onclick="confirmarEliminarFilaStock()" style="flex: 1; padding: 10px; border: none; border-radius: 8px; background: #c0392b; color: white; cursor: pointer; font-size: 14px; font-weight: 600; font-family: Poppins, sans-serif;">Borrar</button>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <%= if @mostrar_modal_categoria do %>
        <div style="position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.45); z-index: 9999; display: flex; align-items: center; justify-content: center;">
          <div style="background: #fff; border-radius: 24px; width: 320px; max-width: 88%; padding: 24px 20px; box-shadow: 0 12px 40px rgba(0,0,0,0.25); max-height: 88vh; overflow-y: auto;">
            <p style="font-size: 18px; font-weight: 700; color: #186904; margin: 0 0 6px; text-align: center;">
              <%= if @editando_categoria_id, do: "Editar categoría", else: "Nueva categoría" %>
            </p>

            <div id="preview-imagen-categoria" style="width: 100%; aspect-ratio: 3/4; max-height: 130px; border-radius: 18px; border: 1.5px solid #eef0ea; background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); display: flex; align-items: center; justify-content: center; margin: 14px 0; overflow: hidden;">
              <%= cond do %>
                <% @imagen_subida_url -> %>
                  <img src={@imagen_subida_url} style="width: 100%; height: 100%; object-fit: cover;" />
                <% @icono_elegido -> %>
                  <svg width="35%" height="35%" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                    {raw(icono_svg(@icono_elegido))}
                  </svg>
                <% true -> %>
                  <span style="font-size: 12px; color: #bbb; font-family: Poppins, sans-serif;">Elegí un ícono o subí una foto</span>
              <% end %>
            </div>

            <label for="input-imagen-categoria" style="display: block; width: 100%; box-sizing: border-box; text-align: center; background: white; color: #186904; border: 1.5px solid #186904; border-radius: 14px; padding: 10px; font-family: Poppins, sans-serif; font-size: 13px; font-weight: 700; cursor: pointer; margin-bottom: 14px;">
              Subir foto de mi galería
            </label>
            <input type="file" id="input-imagen-categoria" accept="image/*" style="display: none;" phx-hook=".SubidaImagenCategoria" data-categoria-id={@editando_categoria_id} />
            <script :type={Phoenix.LiveView.ColocatedHook} name=".SubidaImagenCategoria">
              export default {
                mounted() {
                  this.el.addEventListener('change', async (e) => {
                    const file = e.target.files[0];
                    if (!file) return;
                    const catId = this.el.dataset.categoriaId;
                    if (!catId) {
                      alert('Primero creá la categoría con un ícono, y después editala para subir la foto.');
                      return;
                    }
                    const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");
                    const formData = new FormData();
                    formData.append('_csrf_token', csrfToken);
                    formData.append('imagen', file, file.name);
                    const res = await fetch('/mi-tienda/categorias/' + catId + '/imagen', { method: 'POST', body: formData });
                    const data = await res.json();
                    if (data.ok) {
                      const preview = document.getElementById('preview-imagen-categoria');
                      if (preview) preview.innerHTML = '<img src="' + data.url + '" style="width:100%; height:100%; object-fit:cover;" />';
                    }
                  });
                }
              }
            </script>

            <p style="font-size: 11px; color: #999; text-align: center; margin: 0 0 10px; font-family: Poppins, sans-serif;">o elegí un ícono</p>

            <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; margin-bottom: 16px;">
              <%= for icono <- ["remera", "pantalon", "buzo", "campera", "anteojos", "bolso"] do %>
                <button type="button" phx-click="elegir_icono" phx-value-icono={icono} style={"padding: 10px; border-radius: 12px; border: 1.5px solid #{if @icono_elegido == icono, do: "#186904", else: "#e0e0e0"}; background: #{if @icono_elegido == icono, do: "rgba(24,105,4,0.06)", else: "white"}; cursor: pointer; display: flex; align-items: center; justify-content: center;"}>
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                    {raw(icono_svg(icono))}
                  </svg>
                </button>
              <% end %>
            </div>

            <form phx-submit="guardar_categoria">
              <input type="text" name="nombre" placeholder="Nombre de la categoría" autocomplete="off" value={if cat = Enum.find(@categorias, fn c -> c.id == @editando_categoria_id end), do: cat.nombre, else: ""} style="width: 100%; box-sizing: border-box; padding: 12px 14px; border: 1.5px solid #e0e0e0; border-radius: 14px; font-family: Poppins, sans-serif; font-size: 14px; outline: none; margin-bottom: 12px;" />

              <%= if @error_categoria do %>
                <p style="color: #c0392b; font-size: 12px; margin: 0 0 10px; font-family: Poppins, sans-serif;"><%= @error_categoria %></p>
              <% end %>

              <button type="submit" style="width: 100%; background: #186904; color: white; border: none; border-radius: 14px; padding: 12px 0; font-size: 14px; font-weight: 700; font-family: Poppins, sans-serif; cursor: pointer;">
                <%= if @editando_categoria_id, do: "Guardar cambios", else: "Crear categoría" %>
              </button>
            </form>
            <button type="button" phx-click="cerrar_modal_categoria" style="width: 100%; margin-top: 8px; background: none; color: #999; border: none; padding: 8px 0; font-size: 13px; font-family: Poppins, sans-serif; cursor: pointer;">Cancelar</button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
