defmodule DaleAppWeb.VentasLive do
  use DaleAppWeb, :live_view

  import Ecto.Query
  alias DaleApp.Repo
  alias DaleApp.Accounts
  alias DaleApp.Brands.Brand
  alias DaleApp.Products.Venta
  alias DaleApp.Products.Product
  alias DaleApp.Products.StockItem
  alias Phoenix.LiveView.JS

  def mount(params, session, socket) do
    user_id = session["user_id"]
    brand = if user_id, do: Repo.get_by(Brand, user_id: user_id), else: nil
    sede_actual = parse_sede_param(params["sede"])
    nombre_sede_badge = nombre_badge_sede(sede_actual)

    socket =
      socket
      |> assign(
        brand: brand,
        periodo: "mensual",
        filtro_fecha_ventas: nil,
        expandido_venta_id: nil,
        sede_actual: sede_actual,
        nombre_sede_badge: nombre_sede_badge
      )
      |> cargar_datos()

    {:ok, socket}
  end

  defp parse_sede_param(nil), do: nil
  defp parse_sede_param(""), do: nil
  defp parse_sede_param(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp nombre_badge_sede(nil), do: "Todas"

  defp nombre_badge_sede(sede_id) do
    case Repo.get(DaleApp.Brands.BrandLocation, sede_id) do
      nil -> "Todas"
      sede -> truncar_nombre_sede(if sede.nombre && sede.nombre != "", do: sede.nombre, else: "Sede ##{sede.id}")
    end
  end

  defp truncar_nombre_sede(nombre) when byte_size(nombre) > 12, do: String.slice(nombre, 0, 12) <> "..."
  defp truncar_nombre_sede(nombre), do: nombre

  defp usuarios_en_sede(sede_id) do
    from(es in DaleApp.Accounts.EmpleadoSede, where: es.brand_location_id == ^sede_id, select: es.user_id)
    |> Repo.all()
  end

  defp filtrar_por_sede(query, nil), do: query

  defp filtrar_por_sede(query, sede_id) do
    ids_empleados = usuarios_en_sede(sede_id)

    from(v in query,
      where: v.user_id in ^ids_empleados and (is_nil(v.brand_location_id) or v.brand_location_id == ^sede_id)
    )
  end

  def handle_event("cambiar_periodo", %{"periodo" => periodo}, socket) do
    {:noreply, socket |> assign(periodo: periodo) |> cargar_datos()}
  end

  def handle_event("filtrar_fecha_ventas", %{"fecha" => fecha}, socket) do
    filtro = if fecha == "", do: nil, else: fecha
    {:noreply, socket |> assign(filtro_fecha_ventas: filtro) |> cargar_datos()}
  end

  def handle_event("toggle_detalle_venta", %{"id" => id}, socket) do
    nuevo = if socket.assigns.expandido_venta_id == id, do: nil, else: id
    {:noreply, assign(socket, expandido_venta_id: nuevo)}
  end

  defp cargar_datos(socket) do
    brand = socket.assigns.brand
    if is_nil(brand) do
      assign(socket, ranking_completo: [], ventas_totales: 0, total_facturado: 0, registro_por_dia: [])
    else
      desde = fecha_desde_periodo(socket.assigns.periodo)
      ventas =
        from(v in Venta,
          where: v.brand_id == ^brand.id and v.inserted_at >= ^desde,
          order_by: [desc: v.inserted_at]
        )
        |> filtrar_por_sede(socket.assigns.sede_actual)
        |> Repo.all()
      cajeros = Accounts.list_cajeros(brand.id) |> Map.new(fn c -> {c.id, c} end)
      ranking_completo = calcular_ranking_completo(cajeros, ventas)
      ventas_totales = length(ventas)
      total_facturado = ventas |> Enum.map(& &1.precio_unitario) |> Enum.sum()

      ventas_para_registro =
        case socket.assigns.filtro_fecha_ventas do
          fecha_str when is_binary(fecha_str) and fecha_str != "" ->
            case Date.from_iso8601(fecha_str) do
              {:ok, dia} -> ventas_del_dia(brand.id, dia)
              :error -> ventas
            end
          _ -> ventas
        end

      product_ids = ventas_para_registro |> Enum.map(& &1.product_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()
      productos =
        from(p in Product, where: p.id in ^product_ids)
        |> Repo.all()
        |> Map.new(fn p -> {p.id, p} end)
      registro_por_dia = armar_registro_por_dia(ventas_para_registro, cajeros, productos)

      assign(socket,
        ranking_completo: ranking_completo,
        ventas_totales: ventas_totales,
        total_facturado: total_facturado,
        registro_por_dia: registro_por_dia
      )
    end
  end
  defp fecha_desde_periodo("mensual"), do: NaiveDateTime.add(NaiveDateTime.utc_now(), -30 * 86400, :second)
  defp fecha_desde_periodo("trimestral"), do: NaiveDateTime.add(NaiveDateTime.utc_now(), -90 * 86400, :second)
  defp fecha_desde_periodo("anual"), do: NaiveDateTime.add(NaiveDateTime.utc_now(), -365 * 86400, :second)
  defp fecha_desde_periodo(_), do: NaiveDateTime.add(NaiveDateTime.utc_now(), -30 * 86400, :second)

  defp ventas_del_dia(brand_id, dia) do
    inicio_utc = NaiveDateTime.new!(dia, ~T[00:00:00]) |> NaiveDateTime.add(3 * 3600, :second)
    fin_utc = NaiveDateTime.add(inicio_utc, 86400, :second)

    from(v in Venta,
      where: v.brand_id == ^brand_id and v.inserted_at >= ^inicio_utc and v.inserted_at < ^fin_utc,
      order_by: [desc: v.inserted_at]
    )
    |> Repo.all()
  end

  defp calcular_ranking_completo(cajeros, ventas) do
    ventas
    |> Enum.filter(fn v -> not is_nil(v.user_id) end)
    |> Enum.group_by(& &1.user_id)
    |> Enum.map(fn {user_id, ventas_del_user} ->
      cantidad_productos = length(ventas_del_user)
      monto_facturado = ventas_del_user |> Enum.map(& &1.precio_unitario) |> Enum.sum()
      {Map.get(cajeros, user_id), cantidad_productos, monto_facturado}
    end)
    |> Enum.reject(fn {cajero, _cant, _monto} -> is_nil(cajero) end)
    |> Enum.sort_by(fn {_cajero, cantidad, _monto} -> cantidad end, :desc)
  end
  defp armar_registro_por_dia(ventas, cajeros, productos) do
    hoy_ar = fecha_ar(NaiveDateTime.utc_now()) |> NaiveDateTime.to_date()

    ventas
    |> Enum.take(200)
    |> Enum.map(fn venta ->
      produto = Map.get(productos, venta.product_id)
      venta
      |> Map.put(:imagen_producto, produto && produto.image)
      |> Map.put(:nombre_color, venta.codigo_color && StockItem.nombre_color(venta.codigo_color))
      |> Map.put(:nombre_talle, venta.codigo_talle && StockItem.nombre_talle(venta.codigo_talle))
      |> Map.put(:codigo9, codigo9_de_venta(venta, produto))
    end)
    |> Enum.group_by(fn venta -> venta.grupo_venta || "venta_#{venta.id}" end)
    |> Enum.map(fn {clave_transaccion, ventas_transaccion} ->
      primera = Enum.min_by(ventas_transaccion, & &1.inserted_at, NaiveDateTime)
      cajero = Map.get(cajeros, primera.user_id)

      items =
        ventas_transaccion
        |> Enum.group_by(fn v -> {v.product_id, v.codigo_color, v.codigo_talle} end)
        |> Enum.map(fn {_clave_item, ventas_item} ->
          representante = List.first(ventas_item)
          %{
            product_id: representante.product_id,
            producto_nombre: representante.producto_nombre,
            codigo_tipo: representante.codigo_tipo,
            imagen_producto: representante.imagen_producto,
            nombre_color: representante.nombre_color,
            nombre_talle: representante.nombre_talle,
            codigo9: representante.codigo9,
            cantidad: length(ventas_item),
            monto: ventas_item |> Enum.map(& &1.precio_unitario) |> Enum.sum()
          }
        end)
        |> Enum.sort_by(& &1.producto_nombre)

      titulo =
        case items do
          [unico] -> unico.producto_nombre
          varios -> "#{length(varios)} productos distintos"
        end

      imagen_portada =
        case items do
          [unico] -> unico.imagen_producto
          _ -> nil
        end

      link_stock_unico =
        case items do
          [unico] -> url_stock_venta(unico.codigo_tipo, unico.producto_nombre)
          _ -> nil
        end

      %{
        id: clave_transaccion,
        inserted_at: primera.inserted_at,
        nombre_empleado: nombre_corto(cajero),
        cantidad_en_grupo: length(ventas_transaccion),
        precio_unitario: ventas_transaccion |> Enum.map(& &1.precio_unitario) |> Enum.sum(),
        titulo: titulo,
        imagen_portada: imagen_portada,
        link_stock_unico: link_stock_unico,
        items: items
      }
    end)
    |> Enum.sort_by(& &1.inserted_at, {:desc, NaiveDateTime})
    |> Enum.take(80)
    |> Enum.group_by(fn t -> etiqueta_dia(fecha_ar(t.inserted_at), hoy_ar) end)
    |> Enum.sort_by(
      fn {_etiqueta, [primera | _]} -> primera.inserted_at end,
      {:desc, NaiveDateTime}
    )
  end

  defp codigo9_de_venta(venta, produto) do
    cond do
      is_nil(produto) -> nil
      is_nil(venta.codigo_tipo) or is_nil(venta.codigo_color) or is_nil(venta.codigo_talle) -> nil
      is_nil(produto.codigo_numero) -> nil
      true -> StockItem.armar_codigo(venta.codigo_tipo, venta.codigo_color, produto.codigo_numero, venta.codigo_talle)
    end
  end

  defp formatear_dale9_espaciado(codigo9) when is_binary(codigo9) and byte_size(codigo9) == 9 do
    <<tipo::binary-size(2), color::binary-size(2), numero::binary-size(3), talle::binary-size(2)>> = codigo9
    "#{tipo} #{color} #{numero} #{talle}"
  end
  defp formatear_dale9_espaciado(_codigo9), do: "··· ·· ··· ··"

  defp hex_color(nombre_color) do
    mapa = %{
      "Negro" => "#1a1a1a", "Blanco" => "#ffffff", "Gris" => "#9e9e9e", "Beige" => "#e8dcc8",
      "Rojo" => "#d32f2f", "Bordó" => "#6d1b1b", "Rosa" => "#e91e8c", "Naranja" => "#f57c00",
      "Amarillo" => "#fbc02d", "Verde" => "#43a047", "Verde oscuro" => "#1b5e20", "Celeste" => "#4fc3f7",
      "Azul" => "#1565c0", "Azul marino" => "#0d1b4c", "Violeta" => "#7b1fa2", "Marrón" => "#5d3a1a",
      "Dorado" => "#c9a227", "Plateado" => "#b0b0b0"
    }
    Map.get(mapa, nombre_color, "#cccccc")
  end

  defp fecha_ar(naive_utc), do: NaiveDateTime.add(naive_utc, -3 * 3600, :second)

  defp etiqueta_dia(fecha_venta_ar, hoy_ar) do
    fecha_venta = NaiveDateTime.to_date(fecha_venta_ar)

    cond do
      Date.compare(fecha_venta, hoy_ar) == :eq -> "Hoy"
      Date.compare(fecha_venta, Date.add(hoy_ar, -1)) == :eq -> "Ayer"
      true -> Calendar.strftime(fecha_venta_ar, "%d/%m/%Y")
    end
  end

  defp nombre_corto(nil), do: "Empleado"

  defp nombre_corto(cajero) do
    cond do
      cajero.apellido_visible && cajero.apellido_visible != "" ->
        cajero.apellido_visible

      true ->
        apellido_del_name = (cajero.name || "") |> String.split(" ", parts: 2) |> Enum.at(1, "")

        if apellido_del_name != "" do
          apellido_del_name
        else
          (cajero.name || "") |> String.split(" ", parts: 2) |> List.first() || ""
        end
    end
  end

  def render(assigns) do
    ~H"""
    <div style="padding: 24px 18px 40px; font-family: Poppins, sans-serif; max-width: 600px; margin: 0 auto; background-color: white; min-height: 100vh;">
      <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 16px;">
        <.link navigate="/mi-tienda/cajeros" style="display: inline-flex; background: none; border: none; color: #186904; font-size: 22px; font-weight: 700; cursor: pointer; line-height: 1; text-decoration: none;">&#x2715;</.link>
        <div style="display: inline-flex; align-items: center; gap: 6px; background: #eef4ec; border: 1.5px solid #186904; border-radius: 20px; padding: 6px 12px;">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="#186904" xmlns="http://www.w3.org/2000/svg"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/></svg>
          <span style="font-size: 12px; font-weight: 700; color: #186904; font-family: Poppins, sans-serif;">Visualizando: <%= @nombre_sede_badge %></span>
        </div>
      </div>
      <p style="font-size: 26px; font-weight: 800; color: #186904; margin: 0 0 20px;">Ventas</p>

      <div style="display: flex; gap: 8px; margin-bottom: 20px;">
        <%= for {valor, etiqueta} <- [{"mensual", "Mensual"}, {"trimestral", "Trimestral"}, {"anual", "Anual"}] do %>
          <button type="button" phx-click="cambiar_periodo" phx-value-periodo={valor} style={"flex: 1; padding: 10px 0; border-radius: 12px; border: 1.5px solid #{if @periodo == valor, do: "#186904", else: "#e0e0e0"}; background: #{if @periodo == valor, do: "#186904", else: "white"}; color: #{if @periodo == valor, do: "white", else: "#666"}; cursor: pointer; font-family: Poppins, sans-serif; font-size: 13px; font-weight: 700;"}>
            <%= etiqueta %>
          </button>
        <% end %>
      </div>

      <div style="display: flex; gap: 10px; margin-bottom: 24px;">
        <div style="flex: 1; background: white; border: 1.5px solid #186904; border-radius: 16px; padding: 14px; box-shadow: 0 3px 12px rgba(24,105,4,0.08);">
          <p style="font-size: 10.5px; color: #999; margin: 0 0 4px; text-transform: uppercase; letter-spacing: 0.5px; font-family: Poppins, sans-serif;">Ventas totales</p>
          <p style="font-size: 20px; font-weight: 800; color: #186904; margin: 0; font-family: Poppins, sans-serif;"><%= formatear_entero(@ventas_totales) %></p>
        </div>
        <div style="flex: 1; background: white; border: 1.5px solid #186904; border-radius: 16px; padding: 14px; box-shadow: 0 3px 12px rgba(24,105,4,0.08);">
          <p style="font-size: 10.5px; color: #999; margin: 0 0 4px; text-transform: uppercase; letter-spacing: 0.5px; font-family: Poppins, sans-serif;">Total facturado</p>
          <p style="font-size: 20px; font-weight: 800; color: #186904; margin: 0; font-family: Poppins, sans-serif;">$<%= formatear_moneda(@total_facturado) %></p>
        </div>
      </div>

      <p style="font-size: 13px; font-weight: 700; color: #186904; margin: 0 0 12px; text-transform: uppercase; letter-spacing: 1px;">Ranking completo</p>

      <%= if Enum.empty?(@ranking_completo) do %>
        <p style="font-size: 13px; color: #999; text-align: center; padding: 20px 0; font-family: Poppins, sans-serif;">Todavía no hay ventas en este período.</p>
      <% else %>
        <%
          colores_ranking = ["#E91E8C", "#186904", "#2b2b2b", "#0066cc", "#e67e22", "#8e44ad", "#c0392b", "#16a085"]
        %>
        <%= for {{cajero, cantidad_productos, monto_facturado}, i} <- Enum.with_index(@ranking_completo) do %>
          <div style="background: white; border: 1.5px solid #f0f0f0; border-radius: 16px; padding: 14px; margin-bottom: 10px; box-shadow: 0 2px 8px rgba(0,0,0,0.05);">
            <div style="display: flex; align-items: center; gap: 10px; margin-bottom: 12px;">
              <div style="width: 22px; height: 22px; border-radius: 50%; background: #f2f2f2; display: flex; align-items: center; justify-content: center; flex-shrink: 0;">
                <p style="font-size: 11px; font-weight: 800; color: #999; margin: 0; font-family: Poppins, sans-serif;"><%= i + 1 %></p>
              </div>
              <div style={"width: 34px; height: 34px; border-radius: 50%; background: #{Enum.at(colores_ranking, rem(cajero.id, length(colores_ranking)))}; display: flex; align-items: flex-end; justify-content: center; overflow: hidden; flex-shrink: 0; box-shadow: 0 2px 6px rgba(0,0,0,0.1);"}>
                <svg width="27" height="27" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/>
                  <path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>
                </svg>
              </div>
              <p style="font-size: 14px; font-weight: 700; color: #111; margin: 0; font-family: Poppins, sans-serif;"><%= nombre_corto(cajero) %></p>
            </div>

            <div style="height: 1px; background: #f2f2f2; margin: 0 0 12px;"></div>

            <div style="display: flex; gap: 10px;">
              <div style="flex: 1; display: flex; align-items: center; gap: 8px; background: #f2f9f2; border-radius: 12px; padding: 8px 12px;">
                <div style="width: 26px; height: 26px; border-radius: 50%; background: #186904; display: flex; align-items: center; justify-content: center; flex-shrink: 0;">
                  <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M15 4l6 2v5h-3v8a1 1 0 0 1 -1 1h-10a1 1 0 0 1 -1 -1v-8h-3v-5l6 -2a3 3 0 0 0 6 0"/>
                  </svg>
                </div>
                <div>
                  <p style="font-size: 13px; font-weight: 800; color: #186904; margin: 0; font-family: Poppins, sans-serif; line-height: 1.1;"><%= formatear_entero(cantidad_productos) %></p>
                  <p style="font-size: 9.5px; color: #7a9e70; margin: 0; font-family: Poppins, sans-serif;">productos</p>
                </div>
              </div>
              <div style="flex: 1; display: flex; align-items: center; gap: 8px; background: #f2f9f2; border-radius: 12px; padding: 8px 12px;">
                <div style="width: 26px; height: 26px; border-radius: 50%; background: #186904; display: flex; align-items: center; justify-content: center; flex-shrink: 0;">
                  <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <rect x="3" y="6" width="18" height="12" rx="2"/>
                    <circle cx="12" cy="12" r="2"/>
                    <path d="M7 9v.01"/>
                    <path d="M17 15v.01"/>
                  </svg>
                </div>
                <div>
                  <p style="font-size: 13px; font-weight: 800; color: #186904; margin: 0; font-family: Poppins, sans-serif; line-height: 1.1;">$<%= formatear_moneda(monto_facturado) %></p>
                  <p style="font-size: 9.5px; color: #7a9e70; margin: 0; font-family: Poppins, sans-serif;">facturado</p>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      <% end %>

      <div style="height: 1px; background: #eee; margin: 24px 0 20px;"></div>
      <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 20px; padding: 14px; margin-bottom: 16px; box-shadow: 0 4px 14px rgba(24,105,4,0.10);">
        <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 4px; padding: 0 8px;">
          <p style="font-size: 11.5px; font-weight: 800; color: #186904; margin: 0; text-transform: uppercase; letter-spacing: 1.2px;">Registro de ventas</p>
          <div style="display: flex; align-items: center; gap: 6px;">
            <span style="font-size: 9.5px; font-weight: 800; color: #186904; background: #eef4ec; padding: 3px 8px; border-radius: 8px; text-transform: uppercase; letter-spacing: 0.6px;">Premium</span>
            <div style="position: relative; width: 24px; height: 24px;">
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="pointer-events: none;">
                <rect x="3" y="4" width="18" height="18" rx="3"/>
                <line x1="16" y1="2" x2="16" y2="6"/>
                <line x1="8" y1="2" x2="8" y2="6"/>
                <line x1="3" y1="10" x2="21" y2="10"/>
              </svg>
              <form phx-change="filtrar_fecha_ventas" style="position: absolute; top: 0; left: 0; margin: 0;">
                <input type="date" id="input-fecha-ventas" name="fecha" value={@filtro_fecha_ventas} style="width: 24px; height: 24px; opacity: 0; cursor: pointer; border: none; padding: 0;" />
              </form>
            </div>
            <%= if @filtro_fecha_ventas do %>
              <button type="button" phx-click="filtrar_fecha_ventas" phx-value-fecha="" style="border: none; background: none; padding: 0; cursor: pointer; display: flex; align-items: center;">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
              </button>
            <% end %>
          </div>
        </div>
        <p style="font-size: 11px; color: #999; margin: 0 0 12px; padding: 0 8px; font-family: Poppins, sans-serif; line-height: 1.4;">
          <%= if @filtro_fecha_ventas do %>
            Mostrando el <%= filtro_fecha_texto(@filtro_fecha_ventas) %>.
          <% else %>
            Cada venta con hora, empleado, producto, monto y si fue múltiple.
          <% end %>
        </p>
        <div style="background: white; border-radius: 14px; padding: 8px; height: 480px; overflow-y: auto; -webkit-overflow-scrolling: touch;">
          <%= if Enum.empty?(@registro_por_dia) do %>
            <div style="display: flex; align-items: center; justify-content: center; min-height: 464px; text-align: center;">
              <p style="font-size: 13px; color: #999; margin: 0; font-family: Poppins, sans-serif; max-width: 220px;">Todavía no hay ventas registradas.</p>
            </div>
          <% else %>
            <%= for {etiqueta_dia, ventas_del_dia} <- @registro_por_dia do %>
              <%
                es_hoy = etiqueta_dia == "Hoy"
              %>
              <p style={"font-size: 11.5px; font-weight: 800; margin: 16px 6px 8px; text-transform: uppercase; letter-spacing: 0.8px; font-family: Poppins, sans-serif; color: #{if es_hoy, do: "#186904", else: "#aaa"};"}><%= etiqueta_dia %></p>
              <%= for venta <- ventas_del_dia do %>
                <%
                  hay_un_solo_producto = venta.link_stock_unico != nil
                %>
                <div
                  phx-click={if hay_un_solo_producto, do: JS.navigate(venta.link_stock_unico), else: JS.push("toggle_detalle_venta", value: %{id: venta.id})}
                  style="display: flex; align-items: center; gap: 14px; padding: 14px 6px; border-bottom: 1px solid #f2f2f2; cursor: pointer;"
                >
                  <div style="width: 44px; height: 44px; border-radius: 10px; background: #f2f2f2; overflow: hidden; flex-shrink: 0; display: flex; align-items: center; justify-content: center;">
                    <%= if venta.imagen_portada do %>
                      <img src={venta.imagen_portada} style="width: 100%; height: 100%; object-fit: cover;" />
                    <% else %>
                      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#bbb" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                        <path d="M15 4l6 2v5h-3v8a1 1 0 0 1 -1 1h-10a1 1 0 0 1 -1 -1v-8h-3v-5l6 -2a3 3 0 0 0 6 0"/>
                      </svg>
                    <% end %>
                  </div>
                  <div style="flex: 1; min-width: 0;">
                    <p style="font-size: 14px; font-weight: 700; color: #111; margin: 0 0 3px; font-family: Poppins, sans-serif; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;"><%= venta.titulo %></p>
                    <div style="display: flex; align-items: center; gap: 6px; flex-wrap: wrap;">
                      <p style="font-size: 11.5px; color: #999; margin: 0; font-family: Poppins, sans-serif;"><%= venta.nombre_empleado %> · <%= Calendar.strftime(fecha_ar(venta.inserted_at), "%H:%M") %></p>
                      <%= if venta.cantidad_en_grupo > 1 do %>
                        <span style="font-size: 9px; font-weight: 800; color: #a67c00; background: #fff6d9; padding: 2px 7px; border-radius: 8px; font-family: Poppins, sans-serif; text-transform: uppercase;">x<%= venta.cantidad_en_grupo %></span>
                      <% end %>
                    </div>
                  </div>
                  <p style="font-size: 14px; font-weight: 800; color: #186904; margin: 0; font-family: Poppins, sans-serif; flex-shrink: 0;">$<%= formatear_moneda(venta.precio_unitario) %></p>
                  <%= if hay_un_solo_producto do %>
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#bbb" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round" style="flex-shrink: 0;">
                      <path d="M9 6l6 6-6 6"/>
                    </svg>
                  <% else %>
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#bbb" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style={"flex-shrink: 0; transition: transform 0.15s; transform: rotate(#{if @expandido_venta_id == venta.id, do: "180deg", else: "0deg"});"}>
                      <polyline points="6 9 12 15 18 9"/>
                    </svg>
                  <% end %>
                </div>
                <%= if !hay_un_solo_producto && @expandido_venta_id == venta.id do %>
                  <div style="padding: 4px 4px 14px;">
                    <%= for item <- venta.items do %>
                      <.link navigate={url_stock_venta(item.codigo_tipo, item.producto_nombre)} style="display: flex; align-items: center; gap: 12px; padding: 10px; margin-bottom: 8px; background: #f9fbf8; border-radius: 10px; text-decoration: none;">
                        <div style="background: white; border-radius: 8px; padding: 5px; flex-shrink: 0;">
                          <%= if item.codigo9 do %>
                            {raw(EQRCode.encode(item.codigo9) |> EQRCode.svg(width: 64))}
                          <% else %>
                            <div style="width: 64px; height: 64px; display: flex; align-items: center; justify-content: center;">
                              <p style="font-size: 9px; color: #ccc; text-align: center; margin: 0; font-family: Poppins, sans-serif;">Sin código</p>
                            </div>
                          <% end %>
                        </div>
                        <div style="flex: 1; min-width: 0;">
                          <div style="display: flex; align-items: center; gap: 6px; margin-bottom: 3px; flex-wrap: wrap;">
                            <p style="font-size: 13px; font-weight: 700; color: #111; margin: 0; font-family: Poppins, sans-serif;"><%= item.producto_nombre %></p>
                            <%= if item.cantidad > 1 do %>
                              <span style="font-size: 9px; font-weight: 800; color: #a67c00; background: #fff6d9; padding: 1px 6px; border-radius: 7px; font-family: Poppins, sans-serif; text-transform: uppercase;">x<%= item.cantidad %></span>
                            <% end %>
                          </div>
                          <%= if item.nombre_color do %>
                            <div style="display: flex; align-items: center; gap: 6px; margin-bottom: 4px;">
                              <span style={"width: 12px; height: 12px; border-radius: 50%; background: #{hex_color(item.nombre_color)}; border: 1px solid #ddd; flex-shrink: 0;"}></span>
                              <p style="font-size: 11.5px; color: #666; margin: 0; font-family: Poppins, sans-serif;"><%= item.nombre_color %><%= if item.nombre_talle, do: " · Talle #{item.nombre_talle}" %></p>
                            </div>
                          <% end %>
                          <p style="font-size: 12px; font-weight: 700; color: #186904; margin: 0; font-family: Poppins, sans-serif; letter-spacing: 0.5px;"><%= formatear_dale9_espaciado(item.codigo9) %></p>
                        </div>
                        <p style="font-size: 12.5px; font-weight: 800; color: #186904; margin: 0; flex-shrink: 0; font-family: Poppins, sans-serif;">$<%= formatear_moneda(item.monto) %></p>
                      </.link>
                    <% end %>
                  </div>
                <% end %>
              <% end %>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp url_stock_venta(nil, _nombre), do: "/mi-tienda/stock"
  defp url_stock_venta(_codigo_tipo, nil), do: "/mi-tienda/stock"
  defp url_stock_venta(codigo_tipo, nombre) do
    params = [{"categoria", codigo_tipo}, {"form", "editar"}, {"articulo", nombre}]
    "/mi-tienda/stock?" <> URI.encode_query(params)
  end

  defp filtro_fecha_texto(nil), do: "Elegir día"
  defp filtro_fecha_texto(""), do: "Elegir día"
  defp filtro_fecha_texto(fecha_str) do
    case Date.from_iso8601(fecha_str) do
      {:ok, dia} -> Calendar.strftime(dia, "%d/%m/%Y")
      :error -> "Elegir día"
    end
  end

  defp formatear_entero(numero) do
    numero
    |> trunc()
    |> abs()
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1.")
    |> String.reverse()
  end

  defp formatear_moneda(valor) do
    entero = trunc(valor)
    entero_str = formatear_entero(entero)
    "#{entero_str},00"
  end
end
