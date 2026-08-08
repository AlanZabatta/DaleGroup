defmodule DaleAppWeb.StockPanoramicoLive do
  use DaleAppWeb, :live_view
  import Ecto.Query, only: [from: 2]
  alias DaleApp.Repo
  alias DaleApp.Brands.Brand
  alias DaleApp.Products.{Product, StockItem, CategoriaCustom, TalleCustom}

  @categorias_fijas [
    %{codigo: "01", nombre: "Remeras", icono: "remera"},
    %{codigo: "02", nombre: "Pantalones", icono: "pantalon"},
    %{codigo: "03", nombre: "Buzos", icono: "buzo"},
    %{codigo: "04", nombre: "Camperas", icono: "campera"}
  ]

  @talles_fijos [
    %{codigo: "02", nombre: "S"},
    %{codigo: "03", nombre: "M"},
    %{codigo: "04", nombre: "L"},
    %{codigo: "05", nombre: "XL"}
  ]

  def mount(_params, session, socket) do
    user_id = session["user_id"]
    brand = if user_id, do: Repo.get_by(Brand, user_id: user_id), else: nil
    if brand, do: asegurar_categorias_fijas(brand.id)
    productos_todos = if brand, do: listar_productos_con_stock(brand.id), else: []
    categorias = if brand, do: listar_categorias(brand.id), else: []
    talles_custom = if brand, do: listar_talles_custom(brand.id), else: []
    panel = if brand, do: calcular_panel(brand, productos_todos), else: nil
    talles_totales = if brand, do: calcular_talles_totales(brand.id, talles_custom), else: []

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
       ruta_actual: "/mi-tienda/stock"
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

    {:noreply,
     assign(socket,
       categoria_seleccionada: categoria_seleccionada,
       mostrar_formulario_producto: mostrar_formulario_producto,
       articulo_editando: articulo_editando
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
    div(area_ancho, ancho_mm) * div(area_alto, alto_mm)
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

  defp url_stock(categoria, forma \\ nil, articulo \\ nil) do
    params =
      [{"categoria", categoria}, {"form", forma}, {"articulo", articulo}]
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

    if cat do
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
      productos_todos
      |> Enum.filter(fn {p, total_stock, _c} -> p.active && total_stock == 0 end)
      |> Enum.map(fn {p, _t, _c} -> %{id: p.id, nombre: p.name, imagen: p.image, codigo_tipo: p.codigo_tipo} end)

    %{total: total, productos_dale: productos_dale, limite_dale: limite_dale, sin_stock: sin_stock}
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

  defp estado_talle(cantidad) when cantidad <= 0, do: {"#fdecea", "#c0392b"}
  defp estado_talle(cantidad) when cantidad < 5, do: {"#fff6d9", "#a67c00"}
  defp estado_talle(_cantidad), do: {"#e6f4e6", "#186904"}

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
        <% @categoria_seleccionada -> %>
          <button type="button" phx-click="volver_categorias" style="display: inline-flex; background: none; border: none; color: #186904; font-size: 22px; font-weight: 700; cursor: pointer; line-height: 1; padding: 0; margin-bottom: 16px;">&#x2715;</button>
        <% true -> %>
          <a href="/mi-tienda" style="display: inline-flex; background: none; border: none; color: #186904; font-size: 22px; font-weight: 700; cursor: pointer; line-height: 1; text-decoration: none; margin-bottom: 16px;">&#x2715;</a>
      <% end %>

      <%= if @categoria_seleccionada do %>
        <p id="breadcrumb-stock-categoria" style="font-size: 26px; font-weight: 800; margin: 0 0 20px;">
          <span style="color: #aaa; cursor: pointer;" phx-click="volver_categorias">Mi Stock</span>
          <span style="color: #aaa;">/</span>
          <span style="color: #186904;"><%= @categoria_seleccionada.nombre %></span>
        </p>
      <% else %>
        <p style="font-size: 26px; font-weight: 800; color: #186904; margin: 0 0 20px;">Mi Stock</p>
      <% end %>

      <style>
        @keyframes blurCambioBusqueda {
          0% { filter: blur(0px); opacity: 1; }
          45% { filter: blur(6px); opacity: 0.2; }
          55% { filter: blur(6px); opacity: 0.2; }
          100% { filter: blur(0px); opacity: 1; }
        }
        .busqueda-animada { animation: blurCambioBusqueda 0.6s ease; }
      </style>

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
        <div style="display: flex; gap: 6px; margin-bottom: 10px;">
          <button type="button" phx-click="cambiar_tab_panel" phx-value-tab="control" style={"padding: 8px 16px; border-radius: 12px 12px 0 0; border: none; cursor: pointer; font-family: Poppins, sans-serif; font-size: 12.5px; font-weight: 700; background: #{if @panel_tab == "control", do: "#186904", else: "#f0f0f0"}; color: #{if @panel_tab == "control", do: "white", else: "#888"};"}>Control</button>
          <button type="button" phx-click="cambiar_tab_panel" phx-value-tab="talle" style={"padding: 8px 16px; border-radius: 12px 12px 0 0; border: none; cursor: pointer; font-family: Poppins, sans-serif; font-size: 12.5px; font-weight: 700; background: #{if @panel_tab == "talle", do: "#186904", else: "#f0f0f0"}; color: #{if @panel_tab == "talle", do: "white", else: "#888"};"}>Talle</button>
        </div>

        <div style="border: 1.5px solid #f0f0f0; border-radius: 4px 18px 18px 18px; padding: 16px; margin-bottom: 16px; box-shadow: 0 3px 12px rgba(0,0,0,0.06); background: white;">
          <p style="font-size: 12px; font-weight: 700; color: #186904; margin: 0 0 12px; text-transform: uppercase; letter-spacing: 1px;">Panorama</p>

          <%= if @panel_tab == "control" do %>
            <p style="font-size: 13px; color: #555; margin: 0 0 8px;">Cantidad de productos: <span style="font-weight: 800; color: #186904;"><%= @panel.total %></span></p>
            <p style="font-size: 13px; color: #555; margin: 0 0 8px;">Cantidad de productos Dale: <span style="font-weight: 800; color: #186904;"><%= @panel.productos_dale %>/<%= @panel.limite_dale %></span></p>

            <%= if @panel.sin_stock != [] do %>
              <div style="border-top: 1px solid #f0f0f0; margin-top: 10px; padding-top: 12px;">
                <p style="font-size: 12px; font-weight: 700; color: #c0392b; margin: 0 0 10px;">⚠ Sin unidades cargadas (<%= length(@panel.sin_stock) %>)</p>
                <div style="display: flex; gap: 10px; overflow-x: auto; padding-bottom: 4px;">
                  <%= for p <- @panel.sin_stock do %>
                    <div style="flex-shrink: 0; width: 88px; border-radius: 14px; overflow: hidden; border: 1px solid #f2f2f2; box-shadow: 0 3px 8px rgba(0,0,0,0.06); background: white;">
                      <div style="aspect-ratio: 3/4; background: #faf5f4; display: flex; align-items: center; justify-content: center; overflow: hidden;">
                        <%= if p.imagen do %>
                          <img src={p.imagen} style="width: 100%; height: 100%; object-fit: cover;" />
                        <% else %>
                          <span style="font-size: 28px; font-weight: 800; color: #222;">?</span>
                        <% end %>
                      </div>
                      <div style="padding: 6px 8px;">
                        <p style="font-size: 10px; font-weight: 700; color: #111; margin: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;"><%= p.nombre %></p>
                        <p style="font-size: 9px; color: #c0392b; margin: 2px 0 0; font-weight: 700; text-transform: uppercase;">Sin stock</p>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          <% else %>
            <p style="font-size: 13px; color: #555; margin: 0 0 10px;">Talles:</p>
            <div style="display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 16px;">
              <%= for %{nombre: nombre} <- @talles_fijos_render do %>
                <span style="padding: 6px 14px; border-radius: 16px; background: #f7f5ef; color: #333; font-size: 12.5px; font-weight: 600;"><%= nombre %></span>
              <% end %>
              <%= for t <- @talles_custom do %>
                <span style="padding: 6px 14px; border-radius: 16px; background: #f7f5ef; color: #333; font-size: 12.5px; font-weight: 600;"><%= t.nombre %></span>
              <% end %>
              <button type="button" phx-click="abrir_modal_talle" style="width: 30px; height: 30px; border-radius: 50%; border: 1.5px dashed #ccc; background: white; color: #999; cursor: pointer; font-size: 16px; font-weight: 300; display: flex; align-items: center; justify-content: center;">+</button>
            </div>

            <div style="display: flex; flex-direction: column; gap: 6px;">
              <%= for {_codigo, nombre, total} <- @talles_totales do %>
                <div style="display: flex; align-items: center; justify-content: space-between; padding: 6px 2px; border-bottom: 1px solid #f5f5f5;">
                  <p style="font-size: 13px; color: #555; margin: 0;">Talle <%= nombre %>:</p>
                  <p style="font-size: 13px; font-weight: 700; color: #186904; margin: 0;"><%= total %></p>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
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
                      <% {bg, texto} = estado_talle(cantidad) %>
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
        <div id="form-producto-stock" phx-hook=".FormularioProductoStock" data-codigo-tipo={@categoria_seleccionada && @categoria_seleccionada.codigo} data-numero-preview={@categoria_seleccionada && @categoria_seleccionada.numero_preview} data-articulo={if @articulo_editando, do: Jason.encode!(@articulo_editando), else: ""} style="margin-bottom: 24px;">
          <div id="contenido-formulario-producto-stock">
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
            <svg viewBox="0 0 200 60" style="width: 100%; max-width: 220px; height: 60px;">
              <%= for x <- [4,8,10,15,18,22,28,32,35,40,44,48,54,58,60,65,70,74,80,84,88,94,98,102,108,112,116,122,126,130,136,140,144,150,154,158,164,168,172,178,182,186,192,196] do %>
                <rect x={x} y="4" width={if rem(x, 3) == 0, do: "3", else: "2"} height="52" fill="#186904"/>
              <% end %>
            </svg>
            <p id="texto-dale9-stock" style="font-size: 13px; font-weight: 700; color: #333; letter-spacing: 2px; margin: 6px 0 0; font-family: monospace;"><%= formatear_dale9_espaciado(codigo9_activo_editando) %></p>
          </div>

          <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 18px; padding: 18px; box-shadow: 0 4px 14px rgba(24,105,4,0.10); margin-top: 16px; text-align: center;">
            <p style="font-size: 12.5px; font-weight: 700; color: #186904; margin: 0 0 10px;">Código EAN-13</p>
            <svg viewBox="0 0 200 60" style="width: 100%; max-width: 220px; height: 60px;">
              <%= for x <- [3,6,9,14,16,20,25,29,33,38,42,46,51,55,59,64,68,72,77,81,85,90,94,98,103,107,111,116,120,124,129,133,137,142,146,150,155,159,163,168,172,176,181,185,189,194] do %>
                <rect x={x} y="4" width={if rem(x, 4) == 0, do: "3", else: "2"} height="52" fill="#186904"/>
              <% end %>
            </svg>
            <p id="texto-ean13-stock" style="font-size: 13px; font-weight: 700; color: #333; letter-spacing: 2px; margin: 6px 0 0; font-family: monospace;"><%= ean13_activo_editando || "···· ·· ···· ··· ·· ·" %></p>
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

          <div id="pantalla-imprimir-stock" style="display: none;">
            <p style="font-size: 22px; font-weight: 800; color: #186904; margin: 0 0 4px;">Imprimir códigos</p>
            <p style="font-size: 13px; color: #999; margin: 0 0 24px;">Elegí qué productos imprimir y en qué tamaño</p>

            <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 18px; padding: 18px; box-shadow: 0 4px 14px rgba(24,105,4,0.10); margin-bottom: 20px;">
              <p style="font-size: 12.5px; font-weight: 700; color: #186904; margin: 0 0 14px;">Tamaño</p>

              <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; margin-bottom: 20px;">
                <button type="button" data-tamano="chico" data-ancho-mm="25" data-alto-mm="30" onclick="elegirTamanoImprimir(this)" class="tarjeta-tamano-imprimir" style="display: flex; flex-direction: column; align-items: center; gap: 8px; padding: 14px 8px; border-radius: 16px; border: 1.5px solid #cfe4cf; background: white; cursor: pointer; font-family: Poppins, sans-serif;">
                  <span style="width: 14px; height: 14px; border-radius: 4px; background: #186904;"></span>
                  <span style="font-size: 13px; font-weight: 700; color: #186904;">Chico</span>
                  <span style="font-size: 10px; color: #999;">25×30mm</span>
                </button>

                <button type="button" data-tamano="mediano" data-ancho-mm="40" data-alto-mm="45" onclick="elegirTamanoImprimir(this)" class="tarjeta-tamano-imprimir" style="display: flex; flex-direction: column; align-items: center; gap: 8px; padding: 14px 8px; border-radius: 16px; border: 1.5px solid #cfe4cf; background: white; cursor: pointer; font-family: Poppins, sans-serif;">
                  <span style="width: 22px; height: 22px; border-radius: 5px; background: #186904;"></span>
                  <span style="font-size: 13px; font-weight: 700; color: #186904;">Mediano</span>
                  <span style="font-size: 10px; color: #999;">40×45mm</span>
                </button>

                <button type="button" data-tamano="grande" data-ancho-mm="60" data-alto-mm="70" onclick="elegirTamanoImprimir(this)" class="tarjeta-tamano-imprimir" style="display: flex; flex-direction: column; align-items: center; gap: 8px; padding: 14px 8px; border-radius: 16px; border: 1.5px solid #cfe4cf; background: white; cursor: pointer; font-family: Poppins, sans-serif;">
                  <span style="width: 30px; height: 30px; border-radius: 6px; background: #186904;"></span>
                  <span style="font-size: 13px; font-weight: 700; color: #186904;">Grande</span>
                  <span style="font-size: 10px; color: #999;">60×70mm</span>
                </button>
              </div>

              <p id="texto-cantidad-hoja-imprimir" style="font-size: 11.5px; color: #666; text-align: center; margin: 0 0 10px;">Elegí un tamaño para ver la vista previa</p>

              <div style="display: flex; justify-content: center;">
                <div id="hoja-preview-imprimir" style="display: flex; align-items: center; justify-content: center; overflow: hidden; width: 100%; max-width: 260px; aspect-ratio: 210 / 297; background: white; border: 1.5px solid #ddd; border-radius: 4px; box-shadow: 0 2px 10px rgba(0,0,0,0.08);"></div>
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
          </div>

          <script :type={Phoenix.LiveView.ColocatedHook} name=".FormularioProductoStock">
            export default {
              mounted() {
                const codigoTipo = this.el.dataset.codigoTipo || "";
                const numeroPreview = this.el.dataset.numeroPreview || "";
                let imagenBlobStock = null;
                let tallesSeleccionadosStock = [];
                let editandoArticuloActivo = false;
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
                  const cols = Math.floor(areaAnchoMm / anchoMm);
                  const rows = Math.floor(areaAltoMm / altoMm);
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
                      cuadros.push({ hex, letra });
                    }
                  });

                  const total = cuadros.length;
                  const texto = document.getElementById('texto-espacios-restantes-imprimir');
                  if (texto) {
                    if (total <= capacidad) {
                      texto.textContent = 'Te quedan ' + (capacidad - total) + ' de ' + capacidad + ' espacios';
                      texto.style.color = '#666';
                    } else {
                      const hojas = Math.ceil(total / capacidad);
                      texto.textContent = 'Vas a necesitar ' + hojas + ' hojas (' + total + ' etiquetas, ' + capacidad + ' por hoja)';
                      texto.style.color = '#c0392b';
                    }
                  }

                  const hoja = document.getElementById('hoja-preview-imprimir');
                  if (!hoja) return;

                  const escala = hoja.clientWidth / ANCHO_HOJA_MM_IMPRIMIR;
                  const anchoCeldaPx = anchoMm * escala;
                  const altoCeldaPx = altoMm * escala;
                  const tamanoLetra = Math.max(8, Math.min(anchoCeldaPx, altoCeldaPx) * 0.4);

                  let html = '';
                  for (let i = 0; i < capacidad; i++) {
                    if (i < cuadros.length) {
                      html += '<div style="display: flex; align-items: center; justify-content: center; background: ' + cuadros[i].hex + '; border-radius: 2px; color: white; font-weight: 700; font-family: Poppins, sans-serif; font-size: ' + tamanoLetra + 'px;">' + cuadros[i].letra + '</div>';
                    } else {
                      html += '<div style="background: #186904; opacity: 0.75; border-radius: 2px;"></div>';
                    }
                  }

                  hoja.innerHTML = '<div style="display: grid; grid-template-columns: repeat(' + cols + ', ' + anchoCeldaPx + 'px); grid-template-rows: repeat(' + rows + ', ' + altoCeldaPx + 'px); gap: 2px;">' + html + '</div>';
                };

                let scrollYAntesDeImprimirStock = 0;

                window.abrirImpresionQRStock = () => {
                  scrollYAntesDeImprimirStock = window.scrollY;
                  document.getElementById('contenido-formulario-producto-stock').style.display = 'none';
                  document.getElementById('pantalla-imprimir-stock').style.display = 'block';
                  const breadcrumb = document.getElementById('breadcrumb-stock-categoria');
                  if (breadcrumb) breadcrumb.style.display = 'none';
                  const tarjetaChico = document.querySelector('.tarjeta-tamano-imprimir[data-tamano="chico"]');
                  if (tarjetaChico) elegirTamanoImprimir(tarjetaChico);
                  window.scrollTo(0, 0);
                };

                window.cerrarPantallaImprimirStock = () => {
                  document.getElementById('pantalla-imprimir-stock').style.display = 'none';
                  document.getElementById('contenido-formulario-producto-stock').style.display = 'block';
                  const breadcrumb = document.getElementById('breadcrumb-stock-categoria');
                  if (breadcrumb) breadcrumb.style.display = 'block';
                  window.scrollTo(0, scrollYAntesDeImprimirStock);
                };

                window.manejarClickVolverFormularioStock = () => {
                  const pantallaImprimir = document.getElementById('pantalla-imprimir-stock');
                  if (pantallaImprimir && pantallaImprimir.style.display !== 'none') {
                    cerrarPantallaImprimirStock();
                  } else {
                    const botonReal = document.getElementById('boton-cerrar-formulario-real-stock');
                    if (botonReal) botonReal.click();
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
                window.guardarProductoStock = () => {
                  const nombre = document.getElementById('input-nombre-stock').value.trim();
                  const precio = parseInt(document.getElementById('input-precio-stock').value) || 0;
                  const descripcion = document.getElementById('input-descripcion-stock').value.trim();

                  if (!nombre) { alert('Ponele un nombre al producto.'); return; }

                  const claves = Object.keys(cantidadesStock);
                  if (claves.length === 0) { alert('Elegí al menos un color y un talle con cantidad.'); return; }

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

      <%= if is_nil(@categoria_seleccionada) do %>
        <p style="font-size: 12px; font-weight: 700; color: #186904; margin: 0 0 12px; text-transform: uppercase; letter-spacing: 1px;">Categorías</p>
        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 14px;">
          <%= for cat <- @categorias do %>
            <div style="position: relative; border-radius: 22px; overflow: hidden; border: 1.5px solid #eef0ea; box-shadow: 0 6px 18px rgba(24,105,4,0.10); background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%);">
              <button type="button" phx-click="abrir_modal_editar" phx-value-id={cat.id} style="position: absolute; top: 8px; left: 8px; z-index: 5; width: 26px; height: 26px; border-radius: 50%; background: white; border: 1px solid #eee; cursor: pointer; display: flex; align-items: center; justify-content: center; box-shadow: 0 2px 6px rgba(0,0,0,0.08);">
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
              </button>

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
