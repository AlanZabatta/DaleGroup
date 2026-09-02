defmodule DaleAppWeb.LibroVentasLive do
  use DaleAppWeb, :live_view
  import Ecto.Query, only: [from: 2]
  alias DaleApp.Repo
  alias DaleApp.Brands.Brand
  alias DaleApp.Products.Venta

  @meses ~w(enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre)

  def mount(_params, session, socket) do
    user_id = session["user_id"]
    brand = if user_id, do: Repo.get_by(Brand, user_id: user_id), else: nil
    sedes = if brand, do: Repo.all(from(l in DaleApp.Brands.BrandLocation, where: l.brand_id == ^brand.id, order_by: l.id)), else: []
    sede_actual = brand && Enum.find(sedes, &(&1.id == brand.sede_activa_id))
    hoy = Date.utc_today()

    socket =
      assign(socket,
        brand: brand,
        sedes: sedes,
        sede_actual: sede_actual,
        mostrar_selector_sede: false,
        anio_seleccionado: hoy.year,
        mes_seleccionado: hoy.month,
        mostrar_selector_mes: false,
        meses_lista: @meses
      )

    socket = cargar_ventas_del_mes(socket)

    {:ok, socket}
  end

  def handle_event("toggle_selector_mes", _params, socket) do
    {:noreply, assign(socket, mostrar_selector_mes: !socket.assigns.mostrar_selector_mes)}
  end

  def handle_event("seleccionar_mes", %{"mes" => mes}, socket) do
    mes_int = String.to_integer(mes)
    socket =
      socket
      |> assign(mes_seleccionado: mes_int, mostrar_selector_mes: false)
      |> cargar_ventas_del_mes()

    {:noreply, socket}
  end

  def handle_event("mes_anterior", _params, socket) do
    {anio, mes} = restar_mes(socket.assigns.anio_seleccionado, socket.assigns.mes_seleccionado)
    socket = socket |> assign(anio_seleccionado: anio, mes_seleccionado: mes) |> cargar_ventas_del_mes()
    {:noreply, socket}
  end

  def handle_event("mes_siguiente", _params, socket) do
    {anio, mes} = sumar_mes(socket.assigns.anio_seleccionado, socket.assigns.mes_seleccionado)
    socket = socket |> assign(anio_seleccionado: anio, mes_seleccionado: mes) |> cargar_ventas_del_mes()
    {:noreply, socket}
  end

  def handle_event("toggle_selector_sede", _params, socket) do
    {:noreply, assign(socket, mostrar_selector_sede: !socket.assigns.mostrar_selector_sede)}
  end

  def handle_event("elegir_sede", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    sede = Enum.find(socket.assigns.sedes, fn s -> s.id == id end)
    {:noreply, cambiar_sede(socket, sede)}
  end

  def handle_event("elegir_todas_sedes", _params, socket) do
    {:noreply, cambiar_sede(socket, nil)}
  end

  defp cambiar_sede(socket, sede) do
    brand = socket.assigns.brand
    sede_id = sede && sede.id
    {:ok, brand} = brand |> Brand.changeset(%{sede_activa_id: sede_id}) |> Repo.update()

    socket
    |> assign(brand: brand, sede_actual: sede, mostrar_selector_sede: false)
    |> cargar_ventas_del_mes()
  end

  defp restar_mes(anio, 1), do: {anio - 1, 12}
  defp restar_mes(anio, mes), do: {anio, mes - 1}
  defp sumar_mes(anio, 12), do: {anio + 1, 1}
  defp sumar_mes(anio, mes), do: {anio, mes + 1}

  defp cargar_ventas_del_mes(socket) do
    brand = socket.assigns.brand
    anio = socket.assigns.anio_seleccionado
    mes = socket.assigns.mes_seleccionado
    sede_id = socket.assigns.sede_actual && socket.assigns.sede_actual.id

    if is_nil(brand) do
      assign(socket, ventas_agrupadas: [])
    else
      inicio = NaiveDateTime.new!(anio, mes, 1, 0, 0, 0)
      fin = NaiveDateTime.new!(anio, mes, Date.days_in_month(Date.new!(anio, mes, 1)), 23, 59, 59)

      query =
        from(v in Venta,
          where: v.brand_id == ^brand.id and v.inserted_at >= ^inicio and v.inserted_at <= ^fin,
          order_by: [desc: v.inserted_at]
        )

      query = if sede_id, do: from(v in query, where: v.brand_location_id == ^sede_id), else: query

      ventas = Repo.all(query)

      agrupadas =
        ventas
        |> Enum.group_by(fn v -> fecha_argentina(v.inserted_at) end)
        |> Enum.sort_by(fn {fecha, _} -> fecha end, {:desc, Date})

      assign(socket, ventas_agrupadas: agrupadas)
    end
  end

  defp fecha_argentina(naive_utc) do
    naive_utc
    |> NaiveDateTime.add(-3 * 3600, :second)
    |> NaiveDateTime.to_date()
  end

  defp hora_argentina(naive_utc) do
    fecha_ar = NaiveDateTime.add(naive_utc, -3 * 3600, :second)
    hora_12 = case rem(fecha_ar.hour, 12) do
      0 -> 12
      h -> h
    end
    ampm = if fecha_ar.hour >= 12, do: "pm", else: "am"
    minuto = String.pad_leading(Integer.to_string(fecha_ar.minute), 2, "0")
    "#{hora_12}:#{minuto}#{ampm}"
  end

  defp etiqueta_dia(fecha) do
    hoy = Date.utc_today()
    ayer = Date.add(hoy, -1)
    dias_semana = ~w(Lunes Martes Miércoles Jueves Viernes Sábado Domingo)

    cond do
      fecha == hoy -> "Hoy"
      fecha == ayer -> "Ayer"
      true ->
        dia_semana = Enum.at(dias_semana, Date.day_of_week(fecha) - 1)
        "#{dia_semana} #{fecha.day}/#{String.pad_leading(Integer.to_string(fecha.month), 2, "0")}"
    end
  end

  defp formatear_precio_venta(precio) when is_integer(precio) do
    precio
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
    |> String.replace(",", ".")
  end
  defp formatear_precio_venta(_), do: "0"

  defp total_del_dia(ventas_del_dia) do
    ventas_del_dia
    |> Enum.map(fn v -> v.precio_unitario || 0 end)
    |> Enum.sum()
  end

  defp url_producto(venta) do
    params =
      [{"categoria", venta.codigo_tipo}, {"form", "editar"}, {"articulo", venta.producto_nombre}]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    case params do
      [] -> "/mi-tienda/stock"
      _ -> "/mi-tienda/stock?" <> URI.encode_query(params)
    end
  end

  defp texto_sede_actual(sedes, sede_actual) do
    cond do
      Enum.empty?(sedes) -> "Elegir sede"
      sede_actual -> truncar_nombre_sede(sede_actual.nombre)
      true -> "Todas"
    end
  end
  defp truncar_nombre_sede(nil), do: "Sede"
  defp truncar_nombre_sede(nombre) when byte_size(nombre) > 12, do: String.slice(nombre, 0, 12) <> "..."
  defp truncar_nombre_sede(nombre), do: nombre

  def render(assigns) do
    ~H"""
    <style>
      html, body {
        scrollbar-width: none;
        -ms-overflow-style: none;
      }
      html::-webkit-scrollbar, body::-webkit-scrollbar {
        display: none;
        width: 0;
        height: 0;
      }
      #lista-ventas-scroll {
        scrollbar-width: none;
        -ms-overflow-style: none;
      }
      #lista-ventas-scroll::-webkit-scrollbar {
        display: none;
        width: 0;
        height: 0;
      }
    </style>
    <div style="padding: 24px 18px 40px; font-family: Poppins, sans-serif; max-width: 600px; margin: 0 auto; background-color: white; min-height: 100vh;">
      <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 16px;">
        <a href="/mi-tienda" style="display: inline-flex; background: none; border: none; color: #186904; font-size: 22px; font-weight: 700; cursor: pointer; line-height: 1; text-decoration: none;">&#x2715;</a>
      </div>
      <p style="font-size: 26px; font-weight: 800; color: #186904; margin: 0 0 20px;">Libro de Ventas</p>

      <%= if length(@sedes) > 1 do %>
        <div style="position: relative; display: flex; align-items: center; justify-content: space-between; gap: 10px; background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 14px; padding: 10px 14px; margin-bottom: 16px; box-shadow: 0 3px 10px rgba(24,105,4,0.08);">
          <p style="font-size: 12.5px; font-weight: 700; color: #186904; margin: 0; font-family: Poppins, sans-serif;">
            Sede visualizando: <span style="font-weight: 800;"><%= texto_sede_actual(@sedes, @sede_actual) %></span>
          </p>
          <button type="button" phx-click="toggle_selector_sede" style="display: flex; align-items: center; gap: 6px; background: white; border: 1.5px solid #186904; border-radius: 20px; padding: 6px 12px; cursor: pointer; font-family: Poppins, sans-serif; font-size: 12px; font-weight: 700; color: #186904;">
            <%= texto_sede_actual(@sedes, @sede_actual) %>
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style={"transition: transform 0.15s; transform: rotate(#{if @mostrar_selector_sede, do: "180deg", else: "0deg"});"}>
              <polyline points="6 9 12 15 18 9"/>
            </svg>
          </button>
          <%= if @mostrar_selector_sede do %>
            <div style="position: absolute; top: calc(100% + 6px); right: 0; z-index: 20; background: white; border: 1.5px solid #eee; border-radius: 14px; box-shadow: 0 8px 24px rgba(0,0,0,0.12); min-width: 180px; overflow: hidden;">
              <button type="button" phx-click="elegir_todas_sedes" style={"display: block; width: 100%; text-align: left; padding: 12px 16px; border: none; border-bottom: 1px solid #f2f2f2; cursor: pointer; font-family: Poppins, sans-serif; font-size: 13px; font-weight: 700; background: #{if is_nil(@sede_actual), do: "#eef4ec", else: "white"}; color: #{if is_nil(@sede_actual), do: "#186904", else: "#333"};"}>
                Todas las sedes
              </button>
              <%= for sede <- @sedes do %>
                <button type="button" phx-click="elegir_sede" phx-value-id={sede.id} style={"display: block; width: 100%; text-align: left; padding: 12px 16px; border: none; cursor: pointer; font-family: Poppins, sans-serif; font-size: 13px; font-weight: 600; background: #{if @sede_actual && @sede_actual.id == sede.id, do: "#eef4ec", else: "white"}; color: #{if @sede_actual && @sede_actual.id == sede.id, do: "#186904", else: "#333"};"}>
                  <%= sede.nombre %>
                </button>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>

      <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 22px; padding: 16px; box-shadow: 0 4px 14px rgba(24,105,4,0.10);">
        <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 12px; background: #eef4ec; border-radius: 16px; padding: 10px 8px;">
          <button type="button" phx-click="mes_anterior" style="background: none; border: none; cursor: pointer; padding: 6px; display: flex;">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 18 9 12 15 6"/></svg>
          </button>
          <button type="button" phx-click="toggle_selector_mes" style="display: flex; align-items: center; gap: 6px; background: none; border: none; cursor: pointer; padding: 0;">
            <span style="font-size: 14px; font-weight: 700; color: #186904; text-transform: capitalize; font-family: Poppins, sans-serif;"><%= Enum.at(@meses_lista, @mes_seleccionado - 1) %> <%= @anio_seleccionado %></span>
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style={"transition: transform 0.15s; transform: rotate(#{if @mostrar_selector_mes, do: "180deg", else: "0deg"});"}><polyline points="6 9 12 15 18 9"/></svg>
          </button>
          <button type="button" phx-click="mes_siguiente" style="background: none; border: none; cursor: pointer; padding: 6px; display: flex;">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"/></svg>
          </button>
        </div>

        <%= if @mostrar_selector_mes do %>
          <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; margin-bottom: 12px; background: #eef4ec; border-radius: 14px; padding: 12px;">
            <%= for {nombre, i} <- Enum.with_index(@meses_lista, 1) do %>
              <button
                type="button"
                phx-click="seleccionar_mes"
                phx-value-mes={i}
                style={"padding: 9px 4px; border-radius: 10px; border: none; cursor: pointer; font-family: Poppins, sans-serif; font-size: 12px; font-weight: #{if @mes_seleccionado == i, do: "700", else: "500"}; background: #{if @mes_seleccionado == i, do: "#186904", else: "white"}; color: #{if @mes_seleccionado == i, do: "white", else: "#555"}; text-transform: capitalize;"}
              >
                <%= nombre %>
              </button>
            <% end %>
          </div>
        <% end %>

        <div id="lista-ventas-scroll" style="background: white; border-radius: 14px; padding: 8px; height: 420px; overflow-y: auto; -webkit-overflow-scrolling: touch;">
        <%= if @ventas_agrupadas == [] do %>
          <div style="display: flex; align-items: center; justify-content: center; min-height: 200px; text-align: center;">
            <p style="font-size: 14px; color: #999; margin: 0; font-family: Poppins, sans-serif;">No hay ventas registradas este mes.</p>
          </div>
        <% else %>
          <%= for {fecha, ventas_del_dia} <- @ventas_agrupadas do %>
            <div style="display: flex; align-items: baseline; justify-content: space-between; margin: 4px 0 8px;">
              <p style="font-size: 12px; font-weight: 700; color: #186904; margin: 0; text-transform: uppercase; letter-spacing: 1px; font-family: Poppins, sans-serif;"><%= etiqueta_dia(fecha) %></p>
              <p style="font-size: 12px; font-weight: 700; color: #186904; margin: 0; font-family: Poppins, sans-serif;">$<%= formatear_precio_venta(total_del_dia(ventas_del_dia)) %></p>
            </div>
            <%= for venta <- ventas_del_dia do %>
              <.link navigate={url_producto(venta)} style="display: flex; align-items: center; justify-content: space-between; gap: 10px; padding: 12px 4px; border-bottom: 1px solid #f2f2f2; text-decoration: none;">
                <div style="min-width: 0;">
                  <p style="font-size: 14px; font-weight: 600; color: #111; margin: 0; font-family: Poppins, sans-serif; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;"><%= venta.producto_nombre %></p>
                  <div style="display: flex; align-items: center; gap: 6px; margin: 2px 0 0;">
                    <p style="font-size: 11px; color: #aaa; margin: 0; font-family: Poppins, sans-serif;"><%= hora_argentina(venta.inserted_at) %></p>
                    <span style={"font-size: 9.5px; font-weight: 700; color: #{if venta.canal == "online", do: "#0066cc", else: "#186904"}; background: #{if venta.canal == "online", do: "#eaf2fb", else: "#eef4ec"}; padding: 2px 6px; border-radius: 6px; text-transform: uppercase; letter-spacing: 0.4px;"}><%= if venta.canal == "online", do: "Online", else: "Local" %></span>
                  </div>
                </div>
                <p style="font-size: 14px; font-weight: 700; color: #186904; margin: 0; font-family: Poppins, sans-serif; flex-shrink: 0;">$<%= formatear_precio_venta(venta.precio_unitario || 0) %></p>
              </.link>
            <% end %>
          <% end %>
        <% end %>
        </div>
      </div>
    </div>
    """
  end
end
