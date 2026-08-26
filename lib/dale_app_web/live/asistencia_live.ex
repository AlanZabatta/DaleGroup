defmodule DaleAppWeb.AsistenciaLive do
  use DaleAppWeb, :live_view
  import Ecto.Query, only: [from: 2]
  alias DaleApp.Repo
  alias DaleApp.Accounts
  alias DaleApp.Accounts.Asistencia
  alias DaleApp.Brands.{Brand, HorarioTrabajo}

  @meses ~w(enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre)

  def mount(params, session, socket) do
    user_id = session["user_id"]
    brand = if user_id, do: Repo.get_by(Brand, user_id: user_id), else: nil
    todos_cajeros = if brand, do: Accounts.list_cajeros(brand.id), else: []
    sede_actual = parse_sede_param(params["sede"])
    cajeros = cajeros_de_sede(todos_cajeros, sede_actual)
    nombre_sede_badge = nombre_badge_sede(sede_actual)
    primer_empleado = List.first(cajeros)

    hoy = Date.utc_today()

    socket =
      assign(socket,
        brand: brand,
        mostrar_info: false,
        todos_cajeros: todos_cajeros,
        cajeros: cajeros,
        sede_actual: sede_actual,
        nombre_sede_badge: nombre_sede_badge,
        empleado_seleccionado_id: primer_empleado && primer_empleado.id,
        anio_seleccionado: hoy.year,
        mes_seleccionado: hoy.month,
        mostrar_selector_mes: false,
        meses_lista: @meses,
        editando_fecha: nil,
        pin_paso: nil,
        pin_input_error: nil,
        sin_pin_error: false
      )

    socket = if primer_empleado, do: cargar_calendario(socket, primer_empleado.id), else: assign(socket, dias_mes: [], nombre_mes: "")
    socket = assign(socket, fecha_detalle: hoy) |> cargar_registro_del_dia()

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

  defp cajeros_de_sede(cajeros, nil), do: cajeros

  defp cajeros_de_sede(cajeros, sede_id) do
    ids =
      from(es in DaleApp.Accounts.EmpleadoSede, where: es.brand_location_id == ^sede_id, select: es.user_id)
      |> Repo.all()
      |> MapSet.new()

    Enum.filter(cajeros, fn c -> MapSet.member?(ids, c.id) end)
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

  def handle_event("cambiar_fecha_detalle", %{"fecha" => fecha_str}, socket) do
    case Date.from_iso8601(fecha_str) do
      {:ok, fecha} -> {:noreply, socket |> assign(fecha_detalle: fecha) |> cargar_registro_del_dia()}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("seleccionar_empleado", %{"id" => id}, socket) do
    id_int = String.to_integer(id)
    {:noreply, socket |> assign(empleado_seleccionado_id: id_int) |> cargar_calendario(id_int)}
  end

  def handle_event("toggle_selector_mes", _params, socket) do
    {:noreply, assign(socket, mostrar_selector_mes: !socket.assigns.mostrar_selector_mes)}
  end

  def handle_event("seleccionar_mes", %{"mes" => mes}, socket) do
    mes_int = String.to_integer(mes)
    socket = assign(socket, mes_seleccionado: mes_int, mostrar_selector_mes: false)
    socket = if socket.assigns.empleado_seleccionado_id, do: cargar_calendario(socket, socket.assigns.empleado_seleccionado_id), else: socket
    {:noreply, socket}
  end

  def handle_event("toggle_info", _params, socket) do
    {:noreply, assign(socket, mostrar_info: !socket.assigns.mostrar_info)}
  end

  def handle_event("abrir_dia", %{"fecha" => fecha_str}, socket) do
    fecha = Date.from_iso8601!(fecha_str)
    hoy = Date.utc_today()

    cond do
      Date.compare(fecha, hoy) == :gt ->
        {:noreply, socket}

      is_nil(socket.assigns.brand.pin_hash) ->
        {:noreply, assign(socket, sin_pin_error: true)}

      true ->
        {:noreply, assign(socket, editando_fecha: fecha_str, pin_paso: :pedir_pin, pin_input_error: nil, sin_pin_error: false)}
    end
  end

  def handle_event("cerrar_banner_sin_pin", _params, socket) do
    {:noreply, assign(socket, sin_pin_error: false)}
  end

  def handle_event("cerrar_modal_dia", _params, socket) do
    {:noreply, assign(socket, editando_fecha: nil, pin_paso: nil, pin_input_error: nil)}
  end

  def handle_event("verificar_pin", %{"pin" => pin}, socket) do
    if Brand.pin_valido?(socket.assigns.brand, pin) do
      {:noreply, assign(socket, pin_paso: :elegir_color, pin_input_error: nil)}
    else
      {:noreply, assign(socket, pin_input_error: "PIN incorrecto.")}
    end
  end

  def handle_event("guardar_color", %{"color" => color}, socket) do
    fecha = Date.from_iso8601!(socket.assigns.editando_fecha)
    user_id = socket.assigns.empleado_seleccionado_id
    brand_id = socket.assigns.brand.id

    existente = Repo.get_by(Asistencia, user_id: user_id, brand_id: brand_id, fecha: fecha)

    case color do
      "ausente" ->
        if existente, do: Repo.delete(existente)

      _ ->
        puntos = puntos_para_color(color)
        attrs = %{user_id: user_id, brand_id: brand_id, fecha: fecha, hora_marcada: Time.new!(0, 0, 0), puntos: puntos}
        changeset = (existente || %Asistencia{}) |> Asistencia.changeset(attrs)
        Repo.insert_or_update(changeset)
    end

    socket =
      socket
      |> assign(editando_fecha: nil, pin_paso: nil, pin_input_error: nil)
      |> cargar_calendario(user_id)
      |> cargar_registro_del_dia()

    {:noreply, socket}
  end

  defp cargar_registro_del_dia(socket) do
    brand = socket.assigns.brand
    fecha = socket.assigns.fecha_detalle

    registros =
      from(a in Asistencia,
        join: u in DaleApp.Accounts.User, on: u.id == a.user_id,
        where: a.brand_id == ^brand.id and a.fecha == ^fecha,
        order_by: [asc: a.hora_marcada],
        select: %{hora: a.hora_marcada, puntos: a.puntos, nombre: u.name, apellido_visible: u.apellido_visible, nombre_visible: u.nombre_visible}
      )
      |> Repo.all()
      |> Enum.map(fn r ->
        nombre_mostrar =
          cond do
            r.apellido_visible && r.apellido_visible != "" -> r.apellido_visible
            r.nombre_visible && r.nombre_visible != "" -> r.nombre_visible
            true -> (r.nombre || "") |> String.split(" ", parts: 2) |> List.first() || "Empleado"
          end

        %{hora: r.hora, puntos: r.puntos, nombre: nombre_mostrar}
      end)

    assign(socket, registros_del_dia: registros)
  end

  defp puntos_para_color("verde"), do: 10
  defp puntos_para_color("amarillo"), do: 5
  defp puntos_para_color("muy_tarde"), do: 2
  defp puntos_para_color(_), do: 0

  defp cargar_calendario(socket, user_id) do
    brand = socket.assigns.brand
    empleado = Accounts.get_user(user_id)
    hoy = Date.utc_today()
    anio = socket.assigns.anio_seleccionado
    mes = socket.assigns.mes_seleccionado
    primer_dia = Date.new!(anio, mes, 1)
    ultimo_dia = Date.new!(anio, mes, Date.days_in_month(primer_dia))

    horario = if empleado.horario_id, do: Repo.get(HorarioTrabajo, empleado.horario_id), else: nil

    asistencias_del_mes =
      from(a in Asistencia,
        where: a.user_id == ^user_id and a.brand_id == ^brand.id and a.fecha >= ^primer_dia and a.fecha <= ^ultimo_dia
      )
      |> Repo.all()
      |> Map.new(fn a -> {a.fecha, a} end)

    dias_mes =
      for dia_num <- 1..ultimo_dia.day do
        fecha = Date.new!(anio, mes, dia_num)
        estado = estado_del_dia(fecha, hoy, horario, asistencias_del_mes)
        %{numero: dia_num, fecha: fecha, estado: estado, offset_semana: if(dia_num == 1, do: offset_semana(fecha), else: nil)}
      end

    nombre_mes = "#{Enum.at(@meses, mes - 1)} #{anio}"

    assign(socket, dias_mes: dias_mes, nombre_mes: nombre_mes)
  end

  defp estado_del_dia(fecha, hoy, horario, asistencias_del_mes) do
    cond do
      Date.compare(fecha, hoy) == :gt ->
        :futuro

      true ->
        dia_semana = dia_en_espanol(fecha)
        entrada_esperada_str = horario_para_dia(horario, dia_semana)

        cond do
          is_nil(entrada_esperada_str) ->
            :no_correspondia

          !Map.has_key?(asistencias_del_mes, fecha) ->
            :ausente

          true ->
            asistencia = Map.get(asistencias_del_mes, fecha)
            estado_por_puntos(asistencia.puntos)
        end
    end
  end

  defp estado_por_puntos(puntos) when puntos >= 8, do: :verde
  defp estado_por_puntos(puntos) when puntos >= 3, do: :amarillo
  defp estado_por_puntos(puntos) when puntos >= 1, do: :muy_tarde
  defp estado_por_puntos(_), do: :ausente

  defp horario_para_dia(horario, dia_semana) do
    cond do
      is_nil(horario) -> nil
      horario.tipo == "especifico" && Map.has_key?(horario.horario_por_dia || %{}, dia_semana) ->
        Map.get(horario.horario_por_dia, dia_semana)["entrada"]
      horario.tipo == "general" && dia_semana in (horario.dias || []) ->
        horario.hora_entrada_general
      true -> nil
    end
  end

  defp dia_en_espanol(date) do
    case Date.day_of_week(date) do
      1 -> "lunes"
      2 -> "martes"
      3 -> "miercoles"
      4 -> "jueves"
      5 -> "viernes"
      6 -> "sabado"
      7 -> "domingo"
    end
  end

  defp offset_semana(fecha), do: Date.day_of_week(fecha) - 1

  defp color_estado(:verde), do: {"#186904", "#186904", "white"}
  defp color_estado(:amarillo), do: {"#f2b705", "#f2b705", "white"}
  defp color_estado(:ausente), do: {"#c0392b", "#c0392b", "white"}
  defp color_estado(:muy_tarde), do: {"white", "#c0392b", "#c0392b"}
  defp color_estado(:no_correspondia), do: {"#ececec", "#ececec", "#bbb"}
  defp color_estado(:futuro), do: {"#f7f7f7", "#f0f0f0", "#ccc"}

  defp escape_svg(texto) do
    (texto || "")
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp qr_para_imprimir(brand) do
    qr_interno =
      EQRCode.encode("https://shawl-stipend-composed.ngrok-free.dev/fichar/#{brand.id}")
      |> EQRCode.svg(width: 480)

    nombre = escape_svg(brand.name)

    """
    <svg width="700" height="920" viewBox="0 0 700 920" xmlns="http://www.w3.org/2000/svg">
      <rect width="700" height="920" fill="white"/>
      <rect x="24" y="24" width="652" height="872" rx="28" fill="none" stroke="#186904" stroke-width="2"/>
      <text x="350" y="110" text-anchor="middle" font-family="sans-serif" font-size="34" font-weight="700" fill="#186904">#{nombre}</text>
      <text x="350" y="150" text-anchor="middle" font-family="sans-serif" font-size="20" fill="#555">Escaneá para fichar tu llegada</text>
      <g transform="translate(110, 210)">
        <rect x="-20" y="-20" width="520" height="520" rx="24" fill="white" stroke="#f0f0f0" stroke-width="2"/>
        #{qr_interno}
      </g>
      <text x="350" y="800" text-anchor="middle" font-family="sans-serif" font-size="16" fill="#999">Abrí la cámara de tu celular y apuntá al código</text>
      <text x="350" y="870" text-anchor="middle" font-family="sans-serif" font-size="14" fill="#bbb">Dale</text>
    </svg>
    """
  end

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
    </style>
    <div style="padding: 24px 18px 40px; font-family: Poppins, sans-serif; max-width: 600px; margin: 0 auto; background-color: white; min-height: 100vh;">
      <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 16px;">
        <a href="/mi-tienda/cajeros" style="display: inline-flex; background: none; border: none; color: #186904; font-size: 22px; font-weight: 700; cursor: pointer; line-height: 1; text-decoration: none;">&#x2715;</a>
        <div style="display: inline-flex; align-items: center; gap: 6px; background: #eef4ec; border: 1.5px solid #186904; border-radius: 20px; padding: 6px 12px;">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="#186904" xmlns="http://www.w3.org/2000/svg"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/></svg>
          <span style="font-size: 12px; font-weight: 700; color: #186904; font-family: Poppins, sans-serif;">Visualizando: <%= @nombre_sede_badge %></span>
        </div>
      </div>
      <p style="font-size: 26px; font-weight: 800; color: #186904; margin: 0 0 20px;">Asistencia</p>

      <%= if @sin_pin_error do %>
        <div style="background: #fff3f2; border: 1.5px solid #c0392b; border-radius: 14px; padding: 12px 14px; margin-bottom: 16px; display: flex; align-items: center; justify-content: space-between; gap: 10px;">
          <p style="font-size: 12.5px; color: #c0392b; margin: 0; font-family: Poppins, sans-serif; line-height: 1.4;">Primero tenés que crear tu PIN en Seguridad, dentro del editor de tu tienda.</p>
          <button type="button" phx-click="cerrar_banner_sin_pin" style="background: none; border: none; color: #c0392b; font-size: 16px; font-weight: 700; cursor: pointer; flex-shrink: 0;">✕</button>
        </div>
      <% end %>

      <%= if @brand && @cajeros != [] do %>
        <div style="background: white; border: 1.5px solid #f0f0f0; border-radius: 22px; padding: 20px; box-shadow: 0 3px 14px rgba(0,0,0,0.06); margin-bottom: 20px;">
          <p style="font-size: 12px; font-weight: 700; color: #186904; margin: 0 0 12px; text-transform: uppercase; letter-spacing: 1px;">Calendario de puntualidad</p>

          <div style="display: flex; gap: 8px; overflow-x: auto; padding-bottom: 10px; margin-bottom: 14px;">
            <%
              colores_avatar = ["#E91E8C", "#186904", "#2b2b2b", "#0066cc", "#e67e22", "#8e44ad", "#c0392b", "#16a085"]
            %>
            <%= for cajero <- @cajeros do %>
              <%
                color = Enum.at(colores_avatar, rem(cajero.id, length(colores_avatar)))
                seleccionado = @empleado_seleccionado_id == cajero.id
                nombre_corto_cal = if cajero.apellido_visible && cajero.apellido_visible != "", do: cajero.apellido_visible, else: ((cajero.name || "") |> String.split(" ", parts: 2) |> List.first() || "")
              %>
              <button
                type="button"
                phx-click="seleccionar_empleado"
                phx-value-id={cajero.id}
                style={"display: flex; align-items: center; gap: 6px; padding: 6px 12px 6px 6px; border-radius: 30px; border: 1.5px solid #{if seleccionado, do: "#186904", else: "#e8e8e8"}; background: #{if seleccionado, do: "rgba(24,105,4,0.06)", else: "white"}; cursor: pointer; flex-shrink: 0; white-space: nowrap;"}
              >
                <span style={"width: 18px; height: 18px; border-radius: 50%; background: #{color}; display: inline-block; flex-shrink: 0;"}></span>
                <span style={"font-size: 12.5px; font-weight: 600; color: #{if seleccionado, do: "#186904", else: "#555"}; font-family: Poppins, sans-serif;"}><%= nombre_corto_cal %></span>
              </button>
            <% end %>
          </div>

          <button
            type="button"
            phx-click="toggle_selector_mes"
            style="display: flex; align-items: center; gap: 6px; background: none; border: none; cursor: pointer; padding: 0; margin: 0 0 10px;"
          >
            <span style="font-size: 13px; font-weight: 700; color: #333; text-transform: capitalize; font-family: Poppins, sans-serif;"><%= @nombre_mes %></span>
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style={"transition: transform 0.15s; transform: rotate(#{if @mostrar_selector_mes, do: "180deg", else: "0deg"});"}><polyline points="6 9 12 15 18 9"/></svg>
          </button>

          <%= if @mostrar_selector_mes do %>
            <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; margin-bottom: 16px; background: #f7f5ef; border-radius: 14px; padding: 12px;">
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

          <div style="display: grid; grid-template-columns: repeat(7, 1fr); gap: 6px; margin-bottom: 6px;">
            <%= for letra <- ~w(L M M J V S D) do %>
              <p style="font-size: 10px; color: #aaa; text-align: center; margin: 0; font-weight: 700;"><%= letra %></p>
            <% end %>
          </div>

          <div style="display: grid; grid-template-columns: repeat(7, 1fr); gap: 6px;">
            <%= for dia <- @dias_mes do %>
              <%
                {bg, borde, texto} = color_estado(dia.estado)
                col_start = if dia.offset_semana, do: dia.offset_semana + 1, else: nil
                es_futuro = dia.estado == :futuro
              %>
              <div
                phx-click="abrir_dia"
                phx-value-fecha={Date.to_iso8601(dia.fecha)}
                style={"#{if col_start, do: "grid-column-start: #{col_start};", else: ""} aspect-ratio: 1; border-radius: 7px; background: #{bg}; border: 1.5px solid #{borde}; display: flex; align-items: center; justify-content: center; cursor: #{if es_futuro, do: "default", else: "pointer"};"}
              >
                <span style={"font-size: 10.5px; font-weight: 700; color: #{texto};"}><%= dia.numero %></span>
              </div>
            <% end %>
          </div>

          <div style="display: flex; flex-wrap: wrap; gap: 10px; margin-top: 16px;">
            <div style="display: flex; align-items: center; gap: 5px;">
              <span style="width: 11px; height: 11px; border-radius: 3px; background: #186904;"></span>
              <span style="font-size: 10.5px; color: #777; font-family: Poppins, sans-serif;">A horario</span>
            </div>
            <div style="display: flex; align-items: center; gap: 5px;">
              <span style="width: 11px; height: 11px; border-radius: 3px; background: #f2b705;"></span>
              <span style="font-size: 10.5px; color: #777; font-family: Poppins, sans-serif;">Llegó tarde</span>
            </div>
            <div style="display: flex; align-items: center; gap: 5px;">
              <span style="width: 11px; height: 11px; border-radius: 3px; background: white; border: 1.5px solid #c0392b;"></span>
              <span style="font-size: 10.5px; color: #777; font-family: Poppins, sans-serif;">Muy tarde</span>
            </div>
            <div style="display: flex; align-items: center; gap: 5px;">
              <span style="width: 11px; height: 11px; border-radius: 3px; background: #c0392b;"></span>
              <span style="font-size: 10.5px; color: #777; font-family: Poppins, sans-serif;">Ausente</span>
            </div>
          </div>
          <p style="font-size: 10.5px; color: #bbb; margin: 12px 0 0; font-family: Poppins, sans-serif;">Tocá un día para corregirlo (te va a pedir tu PIN)</p>
        </div>
      <% end %>

      <%= if @brand && @cajeros != [] do %>
        <div style="background: white; border: 1.5px solid #f0f0f0; border-radius: 22px; padding: 20px; box-shadow: 0 3px 14px rgba(0,0,0,0.06); margin-bottom: 20px;">
          <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 14px; flex-wrap: wrap; gap: 8px;">
            <p style="font-size: 12px; font-weight: 700; color: #186904; margin: 0; text-transform: uppercase; letter-spacing: 1px;">
              <%= if @fecha_detalle == Date.utc_today(), do: "Hoy", else: "" %> Registro del día
            </p>
            <form phx-change="cambiar_fecha_detalle">
              <input type="date" name="fecha" value={Date.to_iso8601(@fecha_detalle)} style="border: 1.5px solid #e0e0e0; border-radius: 10px; padding: 6px 10px; font-family: Poppins, sans-serif; font-size: 12px; color: #333; outline: none;" />
            </form>
          </div>

          <%= if Enum.empty?(@registros_del_dia) do %>
            <p style="font-size: 12.5px; color: #bbb; text-align: center; padding: 20px 0; margin: 0; font-family: Poppins, sans-serif;">Nadie fichó este día.</p>
          <% else %>
            <div style="display: flex; flex-direction: column; gap: 8px;">
              <%= for r <- @registros_del_dia do %>
                <div style="display: flex; align-items: center; gap: 10px; padding: 8px 10px; background: #f9f9f9; border-radius: 12px;">
                  <span style="font-size: 12.5px; font-weight: 700; color: #186904; font-family: Poppins, sans-serif; min-width: 44px;"><%= Calendar.strftime(r.hora, "%H:%M") %></span>
                  <span style="font-size: 12.5px; color: #333; font-family: Poppins, sans-serif; flex: 1;">Llegó <%= r.nombre %></span>
                  <span style="font-size: 10.5px; color: #999; font-family: Poppins, sans-serif;"><%= r.puntos %> pts</span>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>

      <%= if @editando_fecha do %>
        <div style="position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.45); z-index: 9999; display: flex; align-items: center; justify-content: center;">
          <div style="background: #fff; border-radius: 28px; width: 300px; max-width: 85%; padding: 28px 24px; box-shadow: 0 12px 40px rgba(0,0,0,0.25); text-align: center;">
            <%= if @pin_paso == :pedir_pin do %>
              <p style="font-size: 18px; font-weight: 700; color: #186904; margin: 0 0 6px; font-family: Poppins, sans-serif;">Ingresá tu PIN</p>
              <p style="font-size: 13px; color: #666; margin: 0 0 18px; font-family: Poppins, sans-serif;">Para corregir el día</p>
              <form phx-submit="verificar_pin">
                <input type="password" name="pin" inputmode="numeric" maxlength="4" autofocus style="width: 100%; box-sizing: border-box; padding: 12px; border: 1.5px solid #e0e0e0; border-radius: 14px; font-size: 20px; text-align: center; letter-spacing: 8px; font-family: Poppins, sans-serif; outline: none; margin-bottom: 12px;" />
                <button type="submit" style="width: 100%; background: #186904; color: #fff; border: none; border-radius: 14px; padding: 12px 0; font-size: 14px; font-weight: 700; font-family: Poppins, sans-serif; cursor: pointer;">Confirmar</button>
              </form>
              <%= if @pin_input_error do %>
                <p style="color: #c0392b; font-size: 12px; margin-top: 10px; font-family: Poppins, sans-serif;"><%= @pin_input_error %></p>
              <% end %>
              <button type="button" phx-click="cerrar_modal_dia" style="width: 100%; margin-top: 10px; background: none; color: #999; border: none; padding: 8px 0; font-size: 13px; font-family: Poppins, sans-serif; cursor: pointer;">Cancelar</button>
            <% else %>
              <p style="font-size: 18px; font-weight: 700; color: #186904; margin: 0 0 18px; font-family: Poppins, sans-serif;">Corregir día</p>
              <div style="display: flex; flex-direction: column; gap: 10px;">
                <button type="button" phx-click="guardar_color" phx-value-color="verde" style="background: #186904; color: white; border: none; border-radius: 14px; padding: 12px; font-family: Poppins, sans-serif; font-weight: 700; font-size: 14px; cursor: pointer;">A horario</button>
                <button type="button" phx-click="guardar_color" phx-value-color="amarillo" style="background: #f2b705; color: white; border: none; border-radius: 14px; padding: 12px; font-family: Poppins, sans-serif; font-weight: 700; font-size: 14px; cursor: pointer;">Llegó tarde</button>
                <button type="button" phx-click="guardar_color" phx-value-color="muy_tarde" style="background: white; color: #c0392b; border: 1.5px solid #c0392b; border-radius: 14px; padding: 12px; font-family: Poppins, sans-serif; font-weight: 700; font-size: 14px; cursor: pointer;">Muy tarde</button>
                <button type="button" phx-click="guardar_color" phx-value-color="ausente" style="background: #c0392b; color: white; border: none; border-radius: 14px; padding: 12px; font-family: Poppins, sans-serif; font-weight: 700; font-size: 14px; cursor: pointer;">Ausente</button>
              </div>
              <button type="button" phx-click="cerrar_modal_dia" style="width: 100%; margin-top: 14px; background: none; color: #999; border: none; padding: 8px 0; font-size: 13px; font-family: Poppins, sans-serif; cursor: pointer;">Cancelar</button>
            <% end %>
          </div>
        </div>
      <% end %>

      <%= if @brand do %>
        <div style="position: relative; background: linear-gradient(160deg, #ffffff 0%, #f7fbf5 100%); border: 1.5px solid #186904; border-radius: 24px; padding: 28px 22px; box-shadow: 0 8px 24px rgba(24,105,4,0.10); min-height: 320px; display: flex; flex-direction: column; align-items: center;">

          <button type="button" phx-click="toggle_info" style="position: absolute; top: 18px; right: 18px; width: 28px; height: 28px; border-radius: 50%; background: white; border: 1.5px solid #e0e0e0; cursor: pointer; color: #186904; font-size: 14px; font-weight: 800; display: flex; align-items: center; justify-content: center; box-shadow: 0 2px 6px rgba(0,0,0,0.06);">
            <%= if @mostrar_info, do: "✕", else: "?" %>
          </button>

          <%= if @mostrar_info do %>
            <div style="display: flex; flex-direction: column; height: 100%; width: 100%; padding-top: 6px;">
              <p style="font-size: 13px; font-weight: 700; color: #186904; margin: 0 0 14px; text-transform: uppercase; letter-spacing: 1px;">¿Cómo funciona?</p>
              <p style="font-size: 13.5px; color: #444; line-height: 1.7; margin: 0;">
                Imprimí este código y pegalo en tu local, bien visible cerca de la entrada.
                <br/><br/>
                Cuando un empleado llega, lo escanea con su celular. El sistema le pide su ubicación en ese momento y verifica que esté cerca de una de tus sedes, dentro de un radio de 200 metros.
                <br/><br/>
                Si está lejos, el fichaje no se registra. No guardamos su recorrido ni la ubicación exacta — solo confirmamos que estaba cerca al momento de fichar.
              </p>
            </div>
          <% else %>
            <p style="font-size: 12px; font-weight: 700; color: #186904; margin: 0 0 18px; text-transform: uppercase; letter-spacing: 1.5px;">Código de fichaje</p>

            <div id="qr-fichaje-box" style="background: white; border-radius: 20px; padding: 20px; box-shadow: 0 6px 18px rgba(0,0,0,0.10); border: 1px solid #f0f0f0;">
              {raw(EQRCode.encode("https://shawl-stipend-composed.ngrok-free.dev/fichar/#{@brand.id}") |> EQRCode.svg(width: 180))}
            </div>

            <p style="font-size: 15px; font-weight: 700; color: #111; margin: 18px 0 2px;"><%= @brand.name %></p>
            <p style="font-size: 12px; color: #999; margin: 0 0 20px; text-align: center; line-height: 1.4;">Pegalo en tu local para que tus empleados fichen al llegar</p>

            <div id="qr-fichaje-imprimir" style="position: absolute; left: -9999px; top: -9999px;">
              {raw(qr_para_imprimir(@brand))}
            </div>

            <button
              type="button"
              onclick={"
                const svg = document.querySelector('#qr-fichaje-imprimir svg');
                const svgData = new XMLSerializer().serializeToString(svg);
                const svgB64 = btoa(unescape(encodeURIComponent(svgData)));
                const a = document.createElement('a');
                a.href = 'data:image/svg+xml;base64,' + svgB64;
                a.download = 'fichaje-#{String.replace(@brand.name, " ", "-")}.svg';
                document.body.appendChild(a);
                a.click();
                document.body.removeChild(a);
              "}
              style="display: flex; align-items: center; gap: 8px; background: #186904; color: white; border: none; border-radius: 14px; padding: 12px 22px; font-size: 13.5px; font-weight: 700; font-family: Poppins, sans-serif; cursor: pointer; box-shadow: 0 3px 10px rgba(24,105,4,0.25);"
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
              Descargar para imprimir
            </button>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
