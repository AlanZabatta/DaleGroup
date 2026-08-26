defmodule DaleAppWeb.GestoresLive do
  use DaleAppWeb, :live_view
  import Ecto.Query, only: [from: 2]
  alias DaleApp.Repo
  alias DaleApp.Brands.Brand
  alias DaleApp.Brands.BrandLocation
  alias DaleApp.Accounts
  alias DaleApp.Accounts.EmpleadoSede
  alias DaleApp.Products.{MovimientoStock, IncidenciaStock}

  @colores_avatar ["#E91E8C", "#186904", "#2b2b2b", "#0066cc", "#e67e22", "#8e44ad", "#c0392b", "#16a085"]

  def mount(params, session, socket) do
    user_id = session["user_id"]
    brand = if user_id, do: Repo.get_by(Brand, user_id: user_id), else: nil
    sede_actual = parse_sede_param(params["sede"])
    nombre_sede_badge = nombre_badge_sede(sede_actual)

    socket =
      socket
      |> assign(
        brand: brand,
        sede_actual: sede_actual,
        nombre_sede_badge: nombre_sede_badge,
        expandido_gestor_id: nil,
        filtro_fecha_gestores: nil,
        filtro_empleado_id_gestores: nil,
        filtro_fecha_por_gestor: %{},
        colores_avatar: @colores_avatar
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
    case Repo.get(BrandLocation, sede_id) do
      nil -> "Todas"
      sede -> truncar_nombre_sede(if sede.nombre && sede.nombre != "", do: sede.nombre, else: "Sede ##{sede.id}")
    end
  end

  def handle_event("toggle_gestor", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    nuevo = if socket.assigns.expandido_gestor_id == id, do: nil, else: id
    {:noreply, assign(socket, expandido_gestor_id: nuevo)}
  end

  def handle_event("filtrar_gestores_fecha", %{"fecha" => fecha}, socket) do
    filtro = if fecha == "", do: nil, else: fecha
    {:noreply, socket |> assign(filtro_fecha_gestores: filtro) |> recomputar_filtro()}
  end

  def handle_event("filtrar_gestores_empleado", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    nuevo = if socket.assigns.filtro_empleado_id_gestores == id, do: nil, else: id
    {:noreply, socket |> assign(filtro_empleado_id_gestores: nuevo) |> recomputar_filtro()}
  end

  def handle_event("filtrar_gestores_empleado_todos", _params, socket) do
    {:noreply, socket |> assign(filtro_empleado_id_gestores: nil) |> recomputar_filtro()}
  end

  def handle_event("filtrar_gestor_fecha_individual", %{"gestor_id" => id_str, "fecha" => fecha}, socket) do
    id = String.to_integer(id_str)
    mapa = socket.assigns.filtro_fecha_por_gestor

    nuevo_mapa =
      if fecha == "" do
        Map.delete(mapa, id)
      else
        Map.put(mapa, id, fecha)
      end

    {:noreply, assign(socket, filtro_fecha_por_gestor: nuevo_mapa)}
  end

  defp usuarios_en_sede(sede_id) do
    from(es in EmpleadoSede, where: es.brand_location_id == ^sede_id, select: es.user_id)
    |> Repo.all()
  end

  defp truncar_nombre_sede(nombre) when byte_size(nombre) > 12, do: String.slice(nombre, 0, 12) <> "..."
  defp truncar_nombre_sede(nombre), do: nombre

  defp cargar_datos(socket) do
    brand = socket.assigns.brand
    sede_id = socket.assigns[:sede_actual]

    if is_nil(brand) do
      assign(socket,
        feed_eventos: [],
        todos_eventos: [],
        eventos_filtrados: [],
        ranking_completo: [],
        lista_cajeros: []
      )
    else
      cajeros = Accounts.list_cajeros(brand.id) |> Map.new(fn c -> {c.id, c} end)
      eventos_creaciones = eventos_creaciones(brand.id, cajeros, sede_id)
      eventos_incidencias = eventos_incidencias(brand.id, cajeros, sede_id)

      todos_eventos =
        (eventos_creaciones ++ eventos_incidencias)
        |> Enum.filter(& &1.cajero)
        |> Enum.sort_by(& &1.fecha, {:desc, NaiveDateTime})

      feed_eventos = Enum.take(todos_eventos, 20)
      ranking_completo = armar_ranking_completo(todos_eventos)

      socket
      |> assign(
        feed_eventos: feed_eventos,
        todos_eventos: todos_eventos,
        ranking_completo: ranking_completo,
        lista_cajeros: Map.values(cajeros)
      )
      |> recomputar_filtro()
    end
  end

  defp recomputar_filtro(socket) do
    eventos_filtrados =
      filtrar_eventos(
        socket.assigns.todos_eventos,
        socket.assigns.filtro_fecha_gestores,
        socket.assigns.filtro_empleado_id_gestores
      )

    assign(socket, eventos_filtrados: eventos_filtrados)
  end

  defp filtrar_eventos(todos_eventos, fecha_filtro, empleado_filtro) do
    todos_eventos
    |> Enum.filter(fn ev ->
      pasa_fecha =
        case fecha_filtro do
          nil ->
            true

          fecha_str ->
            case Date.from_iso8601(fecha_str) do
              {:ok, dia} -> NaiveDateTime.to_date(fecha_ar(ev.fecha)) == dia
              :error -> true
            end
        end

      pasa_empleado = is_nil(empleado_filtro) or ev.user_id == empleado_filtro
      pasa_fecha and pasa_empleado
    end)
    |> Enum.take(80)
  end

  defp filtrar_por_fecha_individual(eventos, nil), do: eventos
  defp filtrar_por_fecha_individual(eventos, ""), do: eventos

  defp filtrar_por_fecha_individual(eventos, fecha_str) do
    case Date.from_iso8601(fecha_str) do
      {:ok, dia} -> Enum.filter(eventos, fn ev -> NaiveDateTime.to_date(fecha_ar(ev.fecha)) == dia end)
      :error -> eventos
    end
  end

  defp eventos_creaciones(brand_id, cajeros, sede_id) do
    base =
      from(m in MovimientoStock,
        where: m.brand_id == ^brand_id and m.tipo_accion == "creado" and not is_nil(m.user_id),
        order_by: [desc: m.inserted_at],
        limit: 60
      )

    query =
      if sede_id do
        ids_empleados = usuarios_en_sede(sede_id)

        from(m in base,
          where: m.user_id in ^ids_empleados and (is_nil(m.brand_location_id) or m.brand_location_id == ^sede_id)
        )
      else
        base
      end

    query
    |> Repo.all()
    |> Enum.map(fn mov ->
      %{
        tipo: :creacion,
        user_id: mov.user_id,
        cajero: Map.get(cajeros, mov.user_id),
        fecha: mov.inserted_at,
        puntos: 10,
        titulo: "Creó #{mov.producto_nombre || "un producto"}",
        explicacion: "Fijo de 10 puntos por cada producto nuevo creado."
      }
    end)
  end

  defp eventos_incidencias(brand_id, cajeros, sede_id) do
    base =
      from(i in IncidenciaStock,
        where: i.brand_id == ^brand_id and i.resuelta == true and not is_nil(i.resuelto_por_user_id),
        order_by: [desc: i.fecha_resolucion],
        limit: 60
      )

    query =
      if sede_id do
        ids_empleados = usuarios_en_sede(sede_id)

        from(i in base,
          where:
            i.resuelto_por_user_id in ^ids_empleados and
              (is_nil(i.brand_location_id) or i.brand_location_id == ^sede_id)
        )
      else
        base
      end

    query
    |> Repo.all()
    |> Enum.map(fn inc ->
      %{
        tipo: :incidencia,
        user_id: inc.resuelto_por_user_id,
        cajero: Map.get(cajeros, inc.resuelto_por_user_id),
        fecha: inc.fecha_resolucion,
        puntos: inc.puntos_otorgados || 0,
        titulo: "Resolvió una incidencia de #{inc.tipo || "stock"}",
        explicacion: explicacion_incidencia(inc)
      }
    end)
  end

  defp explicacion_incidencia(inc) do
    dias_desde_creacion =
      if inc.producto_creado_en && inc.fecha_resolucion do
        div(NaiveDateTime.diff(inc.fecha_resolucion, inc.producto_creado_en, :second), 86400)
      else
        999
      end

    propio_reciente =
      inc.creado_por_user_id == inc.resuelto_por_user_id and dias_desde_creacion <= 14

    cond do
      propio_reciente ->
        "No sumó puntos: resolviste una incidencia de un producto que vos mismo creaste hace #{dias_desde_creacion} día(s) — el sistema no premia corregir tus propios errores recientes (≤14 días)."

      inc.fecha_apertura && inc.fecha_resolucion ->
        horas = NaiveDateTime.diff(inc.fecha_resolucion, inc.fecha_apertura, :second) / 3600
        cond do
          horas <= 24 -> "Resuelta dentro de las primeras 24hs (#{Float.round(horas, 1)}hs) — nivel más alto, 30 puntos."
          horas <= 48 -> "Resuelta entre 24 y 48hs (#{Float.round(horas, 1)}hs) — nivel medio, 20 puntos."
          true -> "Resuelta después de 48hs (#{Float.round(horas, 1)}hs) — nivel más bajo, 10 puntos."
        end

      true ->
        "Puntos otorgados por resolver la incidencia."
    end
  end

  defp armar_ranking_completo(todos_eventos) do
    todos_eventos
    |> Enum.group_by(& &1.user_id)
    |> Enum.map(fn {user_id, eventos} ->
      cajero = eventos |> List.first() |> Map.get(:cajero)
      puntos_creaciones = eventos |> Enum.filter(&(&1.tipo == :creacion)) |> Enum.map(& &1.puntos) |> Enum.sum()
      puntos_incidencias = eventos |> Enum.filter(&(&1.tipo == :incidencia)) |> Enum.map(& &1.puntos) |> Enum.sum()
      total = puntos_creaciones + puntos_incidencias

      %{
        id: user_id,
        cajero: cajero,
        total: total,
        puntos_creaciones: puntos_creaciones,
        puntos_incidencias: puntos_incidencias,
        eventos: eventos |> Enum.sort_by(& &1.fecha, {:desc, NaiveDateTime}) |> Enum.take(30)
      }
    end)
    |> Enum.sort_by(& &1.total, :desc)
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

  defp fecha_ar(naive_utc), do: NaiveDateTime.add(naive_utc, -3 * 3600, :second)

  defp tiempo_relativo(fecha) do
    ahora = NaiveDateTime.utc_now()
    diff_min = NaiveDateTime.diff(ahora, fecha, :second) |> div(60)

    cond do
      diff_min < 1 -> "Recién"
      diff_min < 60 -> "Hace #{diff_min}m"
      diff_min < 1440 -> "Hace #{div(diff_min, 60)}h"
      true -> "Hace #{div(diff_min, 1440)}d"
    end
  end

  defp filtro_fecha_texto(nil), do: "Todos los días"
  defp filtro_fecha_texto(""), do: "Todos los días"

  defp filtro_fecha_texto(fecha_str) do
    case Date.from_iso8601(fecha_str) do
      {:ok, dia} -> Calendar.strftime(dia, "%d/%m/%Y")
      :error -> "Todos los días"
    end
  end

  defp icono_evento(:creacion), do: {"#186904", "#eef9f0"}
  defp icono_evento(:incidencia), do: {"#c0392b", "#fdecea"}

  defp svg_evento(assigns) do
    ~H"""
    <%= case @tipo do %>
      <% :creacion -> %>
        <path d="M12 5v14M5 12h14"/>
      <% :incidencia -> %>
        <path d="M12 9v4M12 17h.01"/>
        <path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/>
    <% end %>
    """
  end

  defp fila_evento(assigns) do
    ~H"""
    <%
      {color, fondo} = icono_evento(@evento.tipo)
    %>
    <div style="display: flex; align-items: flex-start; gap: 10px; padding: 9px 4px; border-bottom: 1px solid #f2f2f2;">
      <div style={"width: 30px; height: 30px; border-radius: 50%; background: #{fondo}; display: flex; align-items: center; justify-content: center; flex-shrink: 0; margin-top: 1px;"}>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={color} stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <.svg_evento tipo={@evento.tipo} />
        </svg>
      </div>
      <div style="flex: 1; min-width: 0;">
        <div style="display: flex; align-items: baseline; justify-content: space-between; gap: 8px;">
          <p style="font-size: 12.5px; font-weight: 700; color: #111; margin: 0; font-family: Poppins, sans-serif;">
            <%= if @mostrar_nombre, do: "#{nombre_corto(@evento.cajero)} · " %><%= @evento.titulo %>
          </p>
          <span style={"font-size: 11px; font-weight: 800; color: #{color}; flex-shrink: 0; font-family: Poppins, sans-serif;"}>+<%= @evento.puntos %></span>
        </div>
        <%= if @mostrar_explicacion do %>
          <p style="font-size: 10.5px; color: #999; margin: 2px 0 0; font-family: Poppins, sans-serif; line-height: 1.35;"><%= @evento.explicacion %></p>
        <% end %>
        <p style="font-size: 9.5px; color: #ccc; margin: 2px 0 0; font-family: Poppins, sans-serif;"><%= tiempo_relativo(@evento.fecha) %></p>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div style="padding: 24px 18px 40px; font-family: Poppins, sans-serif; max-width: 600px; margin: 0 auto; background-color: white; min-height: 100vh;">
      <style>
        #feed-gestores-scroll::-webkit-scrollbar { display: none; }
        #fila-empleados-gestores::-webkit-scrollbar { display: none; }
        .scroll-verde, .scroll-verde-fino { scrollbar-width: none; }
        .scroll-verde::-webkit-scrollbar, .scroll-verde-fino::-webkit-scrollbar { display: none; }
      </style>
      <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 16px;">
        <.link navigate="/mi-tienda/cajeros" style="display: inline-flex; background: none; border: none; color: #186904; font-size: 22px; font-weight: 700; cursor: pointer; line-height: 1; text-decoration: none;">&#x2715;</.link>
        <div style="display: inline-flex; align-items: center; gap: 6px; background: #eef4ec; border: 1.5px solid #186904; border-radius: 20px; padding: 6px 12px;">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="#186904" xmlns="http://www.w3.org/2000/svg"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/></svg>
          <span style="font-size: 12px; font-weight: 700; color: #186904; font-family: Poppins, sans-serif;">Visualizando: <%= @nombre_sede_badge %></span>
        </div>
      </div>
      <p style="font-size: 26px; font-weight: 800; color: #186904; margin: 0 0 6px;">Gestores</p>
      <p style="font-size: 12.5px; color: #999; margin: 0 0 18px; font-family: Poppins, sans-serif; line-height: 1.4;">Quién creó productos o resolvió incidencias de stock, y cuántos puntos ganó por cada acción.</p>

      <p style="font-size: 13px; font-weight: 700; color: #186904; margin: 0 0 10px; text-transform: uppercase; letter-spacing: 1px;">Actividad reciente</p>
      <%= if Enum.empty?(@feed_eventos) do %>
        <p style="font-size: 13px; color: #999; text-align: center; padding: 20px 0; font-family: Poppins, sans-serif;">Todavía no hay actividad registrada.</p>
      <% else %>
        <div id="feed-gestores-scroll" style="display: flex; gap: 10px; overflow-x: auto; padding-bottom: 6px; scrollbar-width: none; margin: 0 -18px 20px; padding-left: 18px; padding-right: 18px;">
          <%= for evento <- @feed_eventos do %>
            <%
              {color, fondo} = icono_evento(evento.tipo)
            %>
            <div style="flex-shrink: 0; width: 148px; background: white; border: 1.5px solid #f0f0f0; border-radius: 14px; padding: 12px; box-shadow: 0 2px 8px rgba(0,0,0,0.05);">
              <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px;">
                <div style={"width: 30px; height: 30px; border-radius: 50%; background: #{fondo}; display: flex; align-items: center; justify-content: center;"}>
                  <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke={color} stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <.svg_evento tipo={evento.tipo} />
                  </svg>
                </div>
                <span style={"font-size: 11px; font-weight: 800; color: #{color}; background: #{fondo}; padding: 2px 7px; border-radius: 8px; font-family: Poppins, sans-serif;"}>+<%= evento.puntos %></span>
              </div>
              <p style="font-size: 11.5px; font-weight: 700; color: #111; margin: 0 0 2px; font-family: Poppins, sans-serif;"><%= nombre_corto(evento.cajero) %></p>
              <p style="font-size: 10.5px; color: #999; margin: 0 0 4px; font-family: Poppins, sans-serif; line-height: 1.3;"><%= evento.titulo %></p>
              <p style="font-size: 9.5px; color: #bbb; margin: 0; font-family: Poppins, sans-serif;"><%= tiempo_relativo(evento.fecha) %></p>
            </div>
          <% end %>
        </div>
      <% end %>

      <div style="background: white; border: 1.5px solid #f0f0f0; border-radius: 18px; padding: 14px; margin-bottom: 20px; box-shadow: 0 2px 10px rgba(0,0,0,0.04);">
        <div style="display: flex; align-items: center; justify-content: space-between; gap: 8px; margin-bottom: 12px;">
          <p style="font-size: 13px; font-weight: 700; color: #186904; margin: 0; text-transform: uppercase; letter-spacing: 1px;">Historial Básico</p>
          <div style={"display: flex; align-items: center; gap: 6px; padding: 5px 10px; border-radius: 20px; border: 1.5px solid #{if @filtro_fecha_gestores, do: "#186904", else: "#e0e0e0"}; background: #{if @filtro_fecha_gestores, do: "#eef4ec", else: "white"};"}>
            <button type="button" onclick="document.getElementById('input-fecha-gestores').showPicker()" style="display: flex; align-items: center; gap: 5px; cursor: pointer; margin: 0; background: none; border: none; padding: 0;">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="flex-shrink: 0;">
                <rect x="3" y="4" width="18" height="18" rx="3"/>
                <line x1="16" y1="2" x2="16" y2="6"/>
                <line x1="8" y1="2" x2="8" y2="6"/>
                <line x1="3" y1="10" x2="21" y2="10"/>
              </svg>
              <p style="font-size: 10.5px; font-weight: 700; color: #186904; margin: 0; font-family: Poppins, sans-serif; white-space: nowrap;"><%= filtro_fecha_texto(@filtro_fecha_gestores) %></p>
            </button>
            <form phx-change="filtrar_gestores_fecha" style="position: absolute; width: 1px; height: 1px; overflow: hidden; margin: 0;">
              <input type="date" id="input-fecha-gestores" name="fecha" value={@filtro_fecha_gestores} style="width: 1px; height: 1px; opacity: 0; border: none; padding: 0;" />
            </form>
            <%= if @filtro_fecha_gestores do %>
              <button type="button" phx-click="filtrar_gestores_fecha" phx-value-fecha="" style="border: none; background: none; padding: 0; cursor: pointer; display: flex; align-items: center;">
                <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
              </button>
            <% end %>
          </div>
        </div>

        <div id="fila-empleados-gestores" style="display: flex; gap: 14px; overflow-x: auto; padding-bottom: 8px; margin-bottom: 12px; scrollbar-width: none;">
          <button type="button" phx-click="filtrar_gestores_empleado_todos" style={"display: flex; flex-direction: column; align-items: center; gap: 4px; background: none; border: none; cursor: pointer; padding: 0; flex-shrink: 0; opacity: #{if @filtro_empleado_id_gestores != nil, do: "0.4", else: "1"};"}>
            <div style={"width: 46px; height: 46px; border-radius: 50%; background: #f2f2f2; display: flex; align-items: center; justify-content: center; border: #{if @filtro_empleado_id_gestores == nil, do: "3px solid #186904", else: "3px solid transparent"};"}>
              <p style="font-size: 10px; font-weight: 800; color: #666; margin: 0; font-family: Poppins, sans-serif;">Todos</p>
            </div>
            <p style="font-size: 9.5px; font-weight: 700; color: #666; margin: 0; font-family: Poppins, sans-serif; white-space: nowrap;">Todos</p>
          </button>
          <%= for cajero <- @lista_cajeros do %>
            <%
              color_c = Enum.at(@colores_avatar, rem(cajero.id, length(@colores_avatar)))
            %>
            <button type="button" phx-click="filtrar_gestores_empleado" phx-value-id={cajero.id} style={"display: flex; flex-direction: column; align-items: center; gap: 4px; background: none; border: none; cursor: pointer; padding: 0; flex-shrink: 0; opacity: #{if @filtro_empleado_id_gestores != nil && @filtro_empleado_id_gestores != cajero.id, do: "0.4", else: "1"};"}>
              <div style={"width: 46px; height: 46px; border-radius: 50%; background: #{color_c}; display: flex; align-items: flex-end; justify-content: center; overflow: hidden; border: #{if @filtro_empleado_id_gestores == cajero.id, do: "3px solid " <> color_c, else: "3px solid transparent"};"}>
                <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/>
                  <path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>
                </svg>
              </div>
              <p style="font-size: 9.5px; font-weight: 700; color: #666; margin: 0; font-family: Poppins, sans-serif; white-space: nowrap;"><%= nombre_corto(cajero) %></p>
            </button>
          <% end %>
        </div>

        <div style="position: relative;">
          <div id="scroll-historial-basico" class="scroll-verde" phx-hook=".BarritaScrollGestores" style="background: #fafafa; border-radius: 12px; padding: 4px 10px; height: 160px; overflow-y: auto; -webkit-overflow-scrolling: touch;">
            <%= if Enum.empty?(@eventos_filtrados) do %>
              <div style="display: flex; align-items: center; justify-content: center; height: 100%; text-align: center;">
                <p style="font-size: 13px; color: #999; margin: 0; font-family: Poppins, sans-serif; max-width: 220px;">No hay actividad que coincida con este filtro.</p>
              </div>
          <% else %>
            <%= for evento <- @eventos_filtrados do %>
              <.fila_evento evento={evento} mostrar_nombre={true} mostrar_explicacion={false} />
            <% end %>
          <% end %>
          </div>
          <div style="position: absolute; top: 4px; right: 2px; bottom: 4px; width: 3px; background: #e8e8e8; border-radius: 10px;">
            <div id="pulgar-historial-basico" style="position: absolute; top: 0; left: 0; width: 100%; background: #186904; border-radius: 10px; transition: top 0.05s linear;"></div>
          </div>
        </div>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".BarritaScrollGestores">
        export default {
          mounted() {
            var el = this.el;
            var pulgar = document.getElementById('pulgar-historial-basico');
            function actualizar() {
              if (!pulgar) return;
              var scrollH = el.scrollHeight;
              var clientH = el.clientHeight;
              if (scrollH <= clientH) { pulgar.style.height = '100%'; pulgar.style.top = '0'; return; }
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

      <div style="height: 1px; background: #eee; margin: 8px 0 20px;"></div>

      <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 2px solid #186904; border-radius: 24px; padding: 20px; margin-bottom: 16px; box-shadow: 0 8px 24px rgba(24,105,4,0.18);">
        <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 10px; padding: 0 8px;">
          <p style="font-size: 16px; font-weight: 800; color: #186904; margin: 0; text-transform: uppercase; letter-spacing: 1.2px;">Historial completo</p>
          <span style="font-size: 9.5px; font-weight: 800; color: #186904; background: #eef4ec; padding: 3px 8px; border-radius: 8px; text-transform: uppercase; letter-spacing: 0.6px;">Premium</span>
        </div>
        <p style="font-size: 11px; color: #999; margin: 0 0 12px; padding: 0 8px; font-family: Poppins, sans-serif; line-height: 1.4;">Tocá a un empleado para ver cómo se calculó cada punto que ganó.</p>

        <%= if Enum.empty?(@ranking_completo) do %>
          <p style="font-size: 13px; color: #999; text-align: center; padding: 20px 0; font-family: Poppins, sans-serif;">Todavía no hay puntos acumulados.</p>
        <% else %>
          <%= for {fila, i} <- Enum.with_index(@ranking_completo) do %>
            <%
              fecha_ind = Map.get(@filtro_fecha_por_gestor, fila.id)
              eventos_mostrar = filtrar_por_fecha_individual(fila.eventos, fecha_ind)
            %>
            <div style="background: white; border-radius: 14px; margin-bottom: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.05); overflow: hidden;">
              <div phx-click="toggle_gestor" phx-value-id={fila.id} style="padding: 12px; cursor: pointer;">
                <div style="display: flex; align-items: center; gap: 10px; margin-bottom: 8px;">
                  <div style="width: 20px; height: 20px; border-radius: 50%; background: #f2f2f2; display: flex; align-items: center; justify-content: center; flex-shrink: 0;">
                    <p style="font-size: 10px; font-weight: 800; color: #999; margin: 0; font-family: Poppins, sans-serif;"><%= i + 1 %></p>
                  </div>
                  <p style="font-size: 13.5px; font-weight: 700; color: #111; margin: 0; font-family: Poppins, sans-serif; flex: 1;"><%= nombre_corto(fila.cajero) %></p>
                  <p style="font-size: 15px; font-weight: 800; color: #186904; margin: 0; font-family: Poppins, sans-serif;"><%= fila.total %> pts</p>
                  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#bbb" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style={"flex-shrink: 0; transition: transform 0.15s; transform: rotate(#{if @expandido_gestor_id == fila.id, do: "180deg", else: "0deg"});"}>
                    <polyline points="6 9 12 15 18 9"/>
                  </svg>
                </div>
                <div style="display: flex; gap: 6px;">
                  <div style="flex: 1; background: #eef9f0; border-radius: 8px; padding: 6px 8px; text-align: center;">
                    <p style="font-size: 11px; font-weight: 800; color: #186904; margin: 0; font-family: Poppins, sans-serif;"><%= fila.puntos_creaciones %></p>
                    <p style="font-size: 9px; color: #7a9e70; margin: 0; font-family: Poppins, sans-serif;">creaciones</p>
                  </div>
                  <div style="flex: 1; background: #fdecea; border-radius: 8px; padding: 6px 8px; text-align: center;">
                    <p style="font-size: 11px; font-weight: 800; color: #c0392b; margin: 0; font-family: Poppins, sans-serif;"><%= fila.puntos_incidencias %></p>
                    <p style="font-size: 9px; color: #c0392b; margin: 0; font-family: Poppins, sans-serif; opacity: 0.75;">incidencias</p>
                  </div>
                </div>
              </div>
              <%= if @expandido_gestor_id == fila.id do %>
                <div style="border-top: 1px solid #f2f2f2; padding: 4px 12px; background: #fafafa;">
                  <div style="display: flex; align-items: center; justify-content: flex-end; gap: 4px; padding-top: 8px;">
                    <button type="button" onclick={"document.getElementById('input-fecha-gestor-#{fila.id}').showPicker()"} style={"display: flex; align-items: center; gap: 5px; padding: 5px 10px; border-radius: 20px; cursor: pointer; margin: 0; background: #{if fecha_ind, do: "#eef4ec", else: "#f5f5f5"}; border: none;"}>
                      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="flex-shrink: 0;">
                        <rect x="3" y="4" width="18" height="18" rx="3"/>
                        <line x1="16" y1="2" x2="16" y2="6"/>
                        <line x1="8" y1="2" x2="8" y2="6"/>
                        <line x1="3" y1="10" x2="21" y2="10"/>
                      </svg>
                      <p style="font-size: 10px; font-weight: 700; color: #186904; margin: 0; font-family: Poppins, sans-serif; white-space: nowrap;"><%= filtro_fecha_texto(fecha_ind) %></p>
                    </button>
                    <form phx-change="filtrar_gestor_fecha_individual" style="position: absolute; width: 1px; height: 1px; overflow: hidden; margin: 0;">
                      <input type="hidden" name="gestor_id" value={fila.id} />
                      <input type="date" id={"input-fecha-gestor-#{fila.id}"} name="fecha" value={fecha_ind} style="width: 1px; height: 1px; opacity: 0; border: none; padding: 0;" />
                    </form>
                    <%= if fecha_ind do %>
                      <button type="button" phx-click="filtrar_gestor_fecha_individual" phx-value-gestor_id={fila.id} phx-value-fecha="" style="border: none; background: none; padding: 0; cursor: pointer; display: flex; align-items: center;">
                        <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
                      </button>
                    <% end %>
                  </div>
                  <div style="position: relative;">
                    <div id={"scroll-historial-gestor-#{fila.id}"} class="scroll-verde-fino" phx-hook=".BarritaScrollGestorInd" style="background: white; border-radius: 10px; padding: 4px 8px; height: 220px; overflow-y: auto; -webkit-overflow-scrolling: touch; margin: 6px 0 8px;">
                      <%= if Enum.empty?(eventos_mostrar) do %>
                        <div style="display: flex; align-items: center; justify-content: center; height: 100%;">
                          <p style="font-size: 12px; color: #999; margin: 0; font-family: Poppins, sans-serif;">Sin actividad para este filtro.</p>
                        </div>
                      <% else %>
                        <%= for evento <- eventos_mostrar do %>
                          <.fila_evento evento={evento} mostrar_nombre={false} mostrar_explicacion={true} />
                        <% end %>
                      <% end %>
                    </div>
                    <div style={"position: absolute; top: 10px; right: 2px; bottom: 12px; width: 2px; background: #e8e8e8; border-radius: 10px;"}>
                      <div id={"pulgar-historial-gestor-#{fila.id}"} style="position: absolute; top: 0; left: 0; width: 100%; background: #186904; border-radius: 10px; opacity: 0.5; transition: top 0.05s linear;"></div>
                    </div>
                  </div>
                </div>
                <script :type={Phoenix.LiveView.ColocatedHook} name=".BarritaScrollGestorInd">
                  export default {
                    mounted() {
                      var el = this.el;
                      var pulgar = document.getElementById('pulgar-historial-gestor-' + el.id.replace('scroll-historial-gestor-', ''));
                      function actualizar() {
                        if (!pulgar) return;
                        var scrollH = el.scrollHeight;
                        var clientH = el.clientHeight;
                        if (scrollH <= clientH) { pulgar.style.height = '100%'; pulgar.style.top = '0'; return; }
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
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end
end
