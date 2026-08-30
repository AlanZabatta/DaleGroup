defmodule DaleAppWeb.CajerosLive do
  use DaleAppWeb, :live_view
  import Ecto.Query, only: [from: 2]
  alias DaleApp.Repo
  alias DaleApp.Brands.Brand
  alias DaleApp.Accounts
  alias DaleApp.Accounts.EmpleadoSede
  alias DaleApp.Brands.BrandLocation

  def mount(_params, session, socket) do
    user_id = session["user_id"]
    brand = if user_id, do: Repo.get_by(Brand, user_id: user_id), else: nil
    cajeros = if brand, do: Accounts.list_cajeros(brand.id), else: []
    sedes = if brand, do: listar_sedes(brand.id), else: []
    sede_actual = brand && brand.sede_activa_id
    ranking_puntualidad = calcular_ranking(brand, sede_actual)
    ranking_ventas = calcular_ranking_ventas(brand, sede_actual)
    ranking_gestores = calcular_ranking_gestores(brand, sede_actual)
    sedes_por_empleado = if brand, do: calcular_sedes_por_empleado(brand.id), else: %{}

    {:ok,
     assign(socket,
       brand: brand,
       cajeros: cajeros,
       sedes: sedes,
       sede_actual: sede_actual,
       selector_sede_abierto: false,
       ranking_puntualidad: ranking_puntualidad,
       ranking_ventas: ranking_ventas,
       ranking_gestores: ranking_gestores,
       sedes_por_empleado: sedes_por_empleado
     )}
  end

  defp listar_sedes(brand_id) do
    from(l in BrandLocation, where: l.brand_id == ^brand_id, order_by: [asc: l.id])
    |> Repo.all()
  end

  defp usuarios_en_sede(sede_id), do: DaleApp.Accounts.usuarios_en_sede(sede_id)

  defp nombre_sede_actual(nil, _sedes), do: "Todas"

  defp nombre_sede_actual(sede_id, sedes) do
    case Enum.find(sedes, &(&1.id == sede_id)) do
      nil -> "Todas"
      sede -> truncar_nombre_sede(if sede.nombre && sede.nombre != "", do: sede.nombre, else: "Sede ##{sede.id}")
    end
  end

  defp truncar_nombre_sede(nombre) when byte_size(nombre) > 12, do: String.slice(nombre, 0, 12) <> "..."
  defp truncar_nombre_sede(nombre), do: nombre

  defp calcular_sedes_por_empleado(brand_id) do
    from(es in EmpleadoSede,
      join: l in BrandLocation, on: l.id == es.brand_location_id,
      where: l.brand_id == ^brand_id,
      select: {es.user_id, l.id, l.nombre}
    )
    |> Repo.all()
    |> Enum.group_by(fn {user_id, _lid, _nombre} -> user_id end, fn {_uid, lid, nombre} ->
      if nombre && nombre != "", do: nombre, else: "Sede ##{lid}"
    end)
  end

  def handle_event("toggle_selector_sede", _params, socket) do
    {:noreply, assign(socket, selector_sede_abierto: !socket.assigns.selector_sede_abierto)}
  end

  def handle_event("elegir_sede", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    {:noreply, guardar_sede_activa(socket, id)}
  end

  def handle_event("elegir_todas_sedes", _params, socket) do
    {:noreply, guardar_sede_activa(socket, nil)}
  end

  # Persiste la sede elegida en brand.sede_activa_id, compartida con Mi
  # Tienda y Stock.
  defp guardar_sede_activa(socket, sede_id) do
    {:ok, brand_actualizada} =
      socket.assigns.brand
      |> DaleApp.Brands.Brand.changeset(%{sede_activa_id: sede_id})
      |> Repo.update()

    assign(socket,
      brand: brand_actualizada,
      sede_actual: sede_id,
      selector_sede_abierto: false,
      ranking_puntualidad: calcular_ranking(brand_actualizada, sede_id),
      ranking_ventas: calcular_ranking_ventas(brand_actualizada, sede_id),
      ranking_gestores: calcular_ranking_gestores(brand_actualizada, sede_id)
    )
  end

  def handle_event("toggle_asistencia", _params, socket) do
    brand = socket.assigns.brand
    nuevo_estado = !brand.asistencia_activa

    atributos =
      if nuevo_estado && is_nil(brand.asistencia_activada_en) do
        %{asistencia_activa: true, asistencia_activada_en: DateTime.utc_now() |> DateTime.truncate(:second)}
      else
        %{asistencia_activa: nuevo_estado}
      end

    {:ok, brand_actualizada} =
      brand
      |> Brand.changeset(atributos)
      |> Repo.update()

    ranking_puntualidad = calcular_ranking(brand_actualizada, socket.assigns.sede_actual)
    {:noreply, assign(socket, brand: brand_actualizada, ranking_puntualidad: ranking_puntualidad)}
  end

  def handle_event("toggle_ventas", _params, socket) do
    brand = socket.assigns.brand
    nuevo_estado = !brand.ventas_activa

    atributos =
      if nuevo_estado && is_nil(brand.ventas_activada_en) do
        %{ventas_activa: true, ventas_activada_en: DateTime.utc_now() |> DateTime.truncate(:second)}
      else
        %{ventas_activa: nuevo_estado}
      end

    {:ok, brand_actualizada} =
      brand
      |> Brand.changeset(atributos)
      |> Repo.update()

    ranking_ventas = calcular_ranking_ventas(brand_actualizada, socket.assigns.sede_actual)
    {:noreply, assign(socket, brand: brand_actualizada, ranking_ventas: ranking_ventas)}
  end

  def handle_event("toggle_gestiones", _params, socket) do
    brand = socket.assigns.brand
    nuevo_estado = !brand.gestiones_activa

    atributos =
      if nuevo_estado && is_nil(brand.gestiones_activada_en) do
        %{gestiones_activa: true, gestiones_activada_en: DateTime.utc_now() |> DateTime.truncate(:second)}
      else
        %{gestiones_activa: nuevo_estado}
      end

    {:ok, brand_actualizada} =
      brand
      |> Brand.changeset(atributos)
      |> Repo.update()

    ranking_gestores = calcular_ranking_gestores(brand_actualizada, socket.assigns.sede_actual)
    {:noreply, assign(socket, brand: brand_actualizada, ranking_gestores: ranking_gestores)}
  end

  def handle_event("toggle_estadisticas", _params, socket) do
    brand = socket.assigns.brand
    nuevo_estado = !brand.asistencia_activa
    ahora = DateTime.utc_now() |> DateTime.truncate(:second)

    atributos = %{
      asistencia_activa: nuevo_estado,
      asistencia_activada_en: brand.asistencia_activada_en || (if nuevo_estado, do: ahora, else: nil),
      ventas_activa: nuevo_estado,
      ventas_activada_en: brand.ventas_activada_en || (if nuevo_estado, do: ahora, else: nil),
      gestiones_activa: nuevo_estado,
      gestiones_activada_en: brand.gestiones_activada_en || (if nuevo_estado, do: ahora, else: nil)
    }

    {:ok, brand_actualizada} =
      brand
      |> Brand.changeset(atributos)
      |> Repo.update()

    sede_actual = socket.assigns.sede_actual
    ranking_puntualidad = calcular_ranking(brand_actualizada, sede_actual)
    ranking_ventas = calcular_ranking_ventas(brand_actualizada, sede_actual)
    ranking_gestores = calcular_ranking_gestores(brand_actualizada, sede_actual)

    {:noreply,
     assign(socket,
       brand: brand_actualizada,
       ranking_puntualidad: ranking_puntualidad,
       ranking_ventas: ranking_ventas,
       ranking_gestores: ranking_gestores
     )}
  end

  def handle_event("toggle_empleado_puntos", _params, socket) do
    brand = socket.assigns.brand
    nuevo_estado = !brand.empleado_puntos_activa

    atributos =
      if nuevo_estado && is_nil(brand.empleado_puntos_activada_en) do
        %{empleado_puntos_activa: true, empleado_puntos_activada_en: DateTime.utc_now() |> DateTime.truncate(:second)}
      else
        %{empleado_puntos_activa: nuevo_estado}
      end

    {:ok, brand_actualizada} =
      brand
      |> Brand.changeset(atributos)
      |> Repo.update()

    {:noreply, assign(socket, brand: brand_actualizada)}
  end

  defp calcular_ranking(nil, _sede_id), do: []
  defp calcular_ranking(%{asistencia_activada_en: nil}, _sede_id), do: []

  defp calcular_ranking(brand, sede_id),
    do: ranking_desde_movimientos(brand, brand.asistencia_activada_en, "asistencia", sede_id)

  defp calcular_ranking_ventas(nil, _sede_id), do: []
  defp calcular_ranking_ventas(%{ventas_activada_en: nil}, _sede_id), do: []

  defp calcular_ranking_ventas(brand, sede_id),
    do: ranking_desde_movimientos(brand, brand.ventas_activada_en, "venta", sede_id)

  defp calcular_ranking_gestores(nil, _sede_id), do: []
  defp calcular_ranking_gestores(%{gestiones_activada_en: nil}, _sede_id), do: []

  defp calcular_ranking_gestores(brand, sede_id),
    do: ranking_desde_movimientos(brand, brand.gestiones_activada_en, "gestores", sede_id)

  # Ranking generico desde movimientos_puntos: agrupa por usuario, suma
  # puntos_finales del ciclo EN VIVO (no el ultimo cerrado, ese es el de
  # EmpleadoDelMes), respeta el filtro por sede si se pide, top 4.
  #
  # "criterio" es un motivo puntual ("venta", "asistencia") o una
  # categoria entera ("gestores", que junta creacion_stock + incidencia).
  defp ranking_desde_movimientos(brand, activada_en, criterio, sede_id) do
    dias_desde_activacion = DateTime.diff(DateTime.utc_now(), activada_en, :day)
    ciclo_actual = div(dias_desde_activacion, 30)

    inicio_ciclo =
      activada_en
      |> DateTime.add(ciclo_actual * 30 * 86400, :second)
      |> DateTime.to_date()

    fin_ciclo = Date.add(inicio_ciclo, 30)

    base =
      if criterio == "gestores" do
        from(m in DaleApp.Products.MovimientoPuntos,
          where:
            m.brand_id == ^brand.id and m.categoria == ^criterio and m.fecha >= ^inicio_ciclo and
              m.fecha < ^fin_ciclo
        )
      else
        from(m in DaleApp.Products.MovimientoPuntos,
          where:
            m.brand_id == ^brand.id and m.motivo == ^criterio and m.fecha >= ^inicio_ciclo and
              m.fecha < ^fin_ciclo
        )
      end

    query =
      if sede_id do
        ids_empleados = usuarios_en_sede(sede_id)

        from(m in base,
          where:
            m.user_id in ^ids_empleados and
              (is_nil(m.brand_location_id) or m.brand_location_id == ^sede_id)
        )
      else
        base
      end

    from(m in query,
      group_by: m.user_id,
      select: {m.user_id, sum(m.puntos_finales)},
      order_by: [desc: sum(m.puntos_finales)],
      limit: 4
    )
    |> Repo.all()
    |> Enum.map(fn {user_id, puntos} -> {Accounts.get_user(user_id), puntos} end)
    |> Enum.reject(fn {cajero, _puntos} -> is_nil(cajero) end)
  end

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
      <.link navigate="/mi-tienda" style="display: inline-flex; background: none; border: none; color: #186904; font-size: 22px; font-weight: 700; cursor: pointer; line-height: 1; text-decoration: none; margin-bottom: 16px;">&#x2715;</.link>
      <p style="font-size: 26px; font-weight: 800; color: #186904; margin: 0 0 20px;">Mis Empleados</p>
      <button type="button" onclick="document.getElementById('modal-qr-empleado').style.display='flex'" style="width: 100%; text-align: center; background-color: #f0f0f0; color: #186904; padding: 12px; border-radius: 16px; margin-bottom: 12px; font-family: Poppins, sans-serif; font-weight: 700; font-size: 13px; border: none; cursor: pointer;">
        + Agregar nuevo empleado
      </button>

      <a href="/mi-tienda/horarios" style="display: block; text-align: center; background-color: white; color: #186904; padding: 12px; border-radius: 16px; margin-bottom: 20px; font-family: Poppins, sans-serif; font-weight: 700; font-size: 13px; border: 1.5px solid #186904; text-decoration: none;">
        Ver Horarios
      </a>

      <div id="modal-qr-empleado" style="display:none; position:fixed; top:0; left:0; right:0; bottom:0; background:rgba(0,0,0,0.45); z-index:9999; align-items:center; justify-content:center;">
        <div style="background:#fff; border-radius:28px; width:300px; max-width:85%; padding:28px 24px; box-shadow:0 12px 40px rgba(0,0,0,0.25); text-align:center;">
          <p style="font-size:18px; font-weight:700; color:#186904; margin:0 0 6px; font-family:Poppins,sans-serif;">Sumá un empleado</p>
          <p style="font-size:13px; color:#666; margin:0 0 18px; font-family:Poppins,sans-serif;">Que escanee este código con su celular</p>
          <div style="background:white; border-radius:16px; padding:16px; display:inline-block; border:1.5px solid #e0e0e0;">
            {raw(EQRCode.encode("https://shawl-stipend-composed.ngrok-free.dev/unirse/#{@brand.id}") |> EQRCode.svg(width: 180))}
          </div>
          <button onclick="document.getElementById('modal-qr-empleado').style.display='none'" style="width:100%; margin-top:18px; background:#186904; color:#fff; border:none; border-radius:14px; padding:12px 0; font-size:14px; font-weight:600; font-family:Poppins,sans-serif; cursor:pointer;">Cerrar</button>
        </div>
      </div>

      <%= if Enum.empty?(@cajeros) do %>
        <p style="color: #999; font-family: Poppins, sans-serif; font-size: 14px; text-align: center; padding: 40px 0;">Todavía no tenés empleados asignados.</p>
      <% else %>
        <%
          colores = ["#E91E8C", "#186904", "#2b2b2b", "#0066cc", "#e67e22", "#8e44ad", "#c0392b", "#16a085"]
          cajeros_con_color = @cajeros |> Enum.map(fn cajero -> {cajero, Enum.at(colores, rem(cajero.id, length(colores)))} end)
        %>
        <div style="display: flex; flex-wrap: wrap; gap: 12px; justify-content: space-between;">
          <%= for {{cajero, color}, i} <- Enum.with_index(cajeros_con_color) do %>
            <a href={"/mi-tienda/cajeros/#{cajero.id}"} class={if i < 4, do: "cajero-tarjeta-visible", else: "cajero-tarjeta-oculta"} style={"display: #{if i < 4, do: "flex", else: "none"}; width: 47%; flex-direction: column; align-items: center; text-align: center; background: white; border: 1.5px solid #f0f0f0; border-radius: 20px; padding: 18px 10px; box-shadow: 0 3px 12px rgba(0,0,0,0.06); text-decoration: none; box-sizing: border-box;"}>
              <div style={"width: 64px; height: 64px; border-radius: 50%; background: #{color}; display: flex; align-items: flex-end; justify-content: center; margin-bottom: 10px; overflow: hidden; flex-shrink: 0;"}>
                <svg width="52" height="52" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/>
                  <path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>
                </svg>
              </div>
              <%
                apellido_mostrar = if cajero.apellido_visible && cajero.apellido_visible != "" do
                  cajero.apellido_visible
                else
                  (cajero.name || "") |> String.split(" ", parts: 2) |> Enum.at(1, "")
                end
                nombre_mostrar = if cajero.nombre_visible && cajero.nombre_visible != "" do
                  cajero.nombre_visible
                else
                  (cajero.name || "") |> String.split(" ", parts: 2) |> List.first() || ""
                end
              %>
              <p style="font-size: 16px; font-weight: 700; color: #111; margin: 0; font-family: Poppins, sans-serif;"><%= if apellido_mostrar != "", do: apellido_mostrar, else: nombre_mostrar %></p>
              <%= if apellido_mostrar != "" do %>
                <p style="font-size: 13px; color: #999; margin: 2px 0 0; font-family: Poppins, sans-serif;"><%= nombre_mostrar %></p>
              <% end %>
              <%
                sedes_nombres = Map.get(@sedes_por_empleado, cajero.id, [])
              %>
              <%= if sedes_nombres != [] do %>
                <p style="font-size: 11px; color: #888; margin: 4px 0 0; font-family: Poppins, sans-serif;"><%= Enum.join(sedes_nombres, ", ") %></p>
              <% end %>
              <%= if cajero.zona && cajero.zona != "" do %>
                <p style="font-size: 11px; color: #888; margin: 2px 0 0; font-family: Poppins, sans-serif;">Zona: <%= cajero.zona %></p>
              <% end %>
            </a>
          <% end %>
        </div>

        <%= if length(@cajeros) > 4 do %>
          <button type="button" onclick="document.querySelectorAll('.cajero-tarjeta-oculta').forEach(el => el.style.display = 'flex'); this.style.display = 'none';" style="display: block; width: 100%; margin-top: 16px; background: none; border: 1.5px dashed #e0e0e0; border-radius: 16px; padding: 12px; cursor: pointer; color: #186904; font-family: Poppins, sans-serif; font-weight: 700; font-size: 13px;">
            Ver todos ({length(@cajeros)})
          </button>
        <% end %>
      <% end %>

      <div style="height: 1px; background: #eee; margin: 24px 0 20px;"></div>

      <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 18px;">
        <p style="font-size: 13px; font-weight: 700; margin: 0; text-transform: uppercase; letter-spacing: 1px; color: #186904;">Estadísticas</p>
        <button type="button" phx-click="toggle_estadisticas" style={"width: 50px; height: 28px; border-radius: 20px; border: none; cursor: pointer; padding: 3px; display: flex; align-items: center; background: #{if @brand.asistencia_activa, do: "#186904", else: "#ccc"}; justify-content: #{if @brand.asistencia_activa, do: "flex-end", else: "flex-start"}; transition: background 0.2s;"}>
          <div style="width: 22px; height: 22px; border-radius: 50%; background: white; box-shadow: 0 1px 3px rgba(0,0,0,0.3); transition: transform 0.2s;"></div>
        </button>
      </div>

      <%= if @brand.asistencia_activa and length(@sedes) > 1 do %>
        <div style="position: relative; display: flex; align-items: center; justify-content: space-between; gap: 10px; background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 14px; padding: 10px 14px; margin-bottom: 16px; box-shadow: 0 3px 10px rgba(24,105,4,0.08);">
          <p style="font-size: 12.5px; font-weight: 700; color: #186904; margin: 0; font-family: Poppins, sans-serif;">
            Sede visualizando: <span style="font-weight: 800;"><%= nombre_sede_actual(@sede_actual, @sedes) %></span>
          </p>
          <button type="button" phx-click="toggle_selector_sede" style="display: flex; align-items: center; gap: 6px; background: white; border: 1.5px solid #186904; border-radius: 20px; padding: 6px 12px; cursor: pointer; font-family: Poppins, sans-serif; font-size: 12px; font-weight: 700; color: #186904;">
            <%= nombre_sede_actual(@sede_actual, @sedes) %>
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style={"transition: transform 0.15s; transform: rotate(#{if @selector_sede_abierto, do: "180deg", else: "0deg"});"}>
              <polyline points="6 9 12 15 18 9"/>
            </svg>
          </button>
          <%= if @selector_sede_abierto do %>
            <div style="position: absolute; top: calc(100% + 6px); right: 0; z-index: 20; background: white; border: 1.5px solid #eee; border-radius: 14px; box-shadow: 0 8px 24px rgba(0,0,0,0.12); min-width: 180px; overflow: hidden;">
              <%= if Enum.empty?(@sedes) do %>
                <p style="font-size: 12.5px; color: #999; margin: 0; padding: 14px; font-family: Poppins, sans-serif; text-align: center;">Todavía no cargaste sedes.</p>
              <% else %>
                <%= if length(@sedes) > 1 do %>
                  <button type="button" phx-click="elegir_todas_sedes" style={"display: block; width: 100%; text-align: left; padding: 12px 16px; border: none; border-bottom: 1px solid #f2f2f2; cursor: pointer; font-family: Poppins, sans-serif; font-size: 13px; font-weight: 700; background: #{if is_nil(@sede_actual), do: "#eef4ec", else: "white"}; color: #{if is_nil(@sede_actual), do: "#186904", else: "#333"};"}>
                    Todas las sedes
                  </button>
                <% end %>
                <%= for sede <- @sedes do %>
                  <button type="button" phx-click="elegir_sede" phx-value-id={sede.id} style={"display: block; width: 100%; text-align: left; padding: 12px 16px; border: none; cursor: pointer; font-family: Poppins, sans-serif; font-size: 13px; font-weight: 600; background: #{if @sede_actual == sede.id, do: "#eef4ec", else: "white"}; color: #{if @sede_actual == sede.id, do: "#186904", else: "#333"};"}>
                    <%= if sede.nombre && sede.nombre != "", do: sede.nombre, else: "Sede ##{sede.id}" %>
                  </button>
                <% end %>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>

      <div style="background: #fafaf7; border: 1.5px solid #e6e0d2; border-radius: 22px; padding: 18px 14px;">

      <p style="font-size: 12px; font-weight: 700; margin: 0 0 4px; text-transform: uppercase; letter-spacing: 1px; color: #999;">Asistencia</p>
      <p style="font-size: 11.5px; color: #999; margin: 0 0 10px; font-family: Poppins, sans-serif; line-height: 1.4;">Mide puntualidad de fichaje. Aplica a todos los roles.</p>

      <%= if @brand.asistencia_activa do %>
        <div style="background: white; border: 1.5px solid #186904; border-radius: 18px; padding: 18px 16px; box-shadow: 0 3px 12px rgba(24,105,4,0.08);">
          <%= if Enum.empty?(@ranking_puntualidad) do %>
            <div style="display: flex; align-items: center; gap: 10px;">
              <div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 8px; flex-shrink: 0;">
                <%= for i <- 1..4 do %>
                  <div style="position: relative; display: flex; flex-direction: column; align-items: center; background: white; border: 1.5px solid #f0f0f0; border-radius: 14px; padding: 8px 6px 6px; width: 74px; box-sizing: border-box; box-shadow: 0 2px 6px rgba(0,0,0,0.05); opacity: 0.55;">
                    <div style="width: 44px; height: 44px; border-radius: 50%; background: #ccc; display: flex; align-items: flex-end; justify-content: center; overflow: hidden; margin-bottom: 6px; flex-shrink: 0;">
                      <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                        <path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/>
                        <path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>
                      </svg>
                    </div>
                    <p style="font-size: 11px; font-weight: 700; color: #999; margin: 0; text-align: center; font-family: Poppins, sans-serif;">Empleado <%= i %></p>
                  </div>
                <% end %>
              </div>
              <div style="flex: 1; min-width: 0; position: relative; display: flex; align-items: flex-end; justify-content: flex-start; gap: 10px; height: 180px; padding: 0 8px; border-radius: 12px; background-color: #f7f5ef; background-image: repeating-linear-gradient(to bottom, transparent 0, transparent 29px, #e6e0d2 29px, #e6e0d2 30px); background-position: bottom; overflow-x: auto; overflow-y: hidden;">
                <%= for _i <- 1..4 do %>
                  <div style="display: flex; flex-direction: column; align-items: center; gap: 8px; width: 34px;">
                    <div style="width: 20px; background: #186904; opacity: 0.15; height: 6px; border-radius: 5px 5px 0 0;"></div>
                  </div>
                <% end %>
              </div>
            </div>
            <p style="font-size: 11px; color: #999; margin: 0; text-align: center; font-family: Poppins, sans-serif;">Todavía no hay registros de asistencia</p>
          <% else %>
            <%
              max_puntos = @ranking_puntualidad |> Enum.map(fn {_cajero, puntos} -> puntos end) |> Enum.max()
              colores_mini = ["#E91E8C", "#186904", "#2b2b2b", "#0066cc", "#e67e22", "#8e44ad", "#c0392b", "#16a085"]
            %>
            <div style="display: flex; align-items: center; gap: 10px;">
              <div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 8px; flex-shrink: 0;">
                <%= for {{cajero, _puntos}, i} <- Enum.with_index(@ranking_puntualidad) do %>
                  <%
                    apellido_mini = nombre_corto(cajero)
                  %>
                  <div style="position: relative; display: flex; flex-direction: column; align-items: center; background: white; border: 1.5px solid #f0f0f0; border-radius: 14px; padding: 8px 6px 6px; width: 74px; box-sizing: border-box; box-shadow: 0 2px 6px rgba(0,0,0,0.05);">
                    <%= if i == 0 do %>
                      <svg width="20" height="20" viewBox="0 0 24 24" fill="#f5b301" stroke="#f5b301" style="position: absolute; top: -10px; left: 50%; transform: translateX(-50%); z-index: 2;">
                        <path d="M2 18h20l-2-9-5 4-3-7-3 7-5-4-2 9z"/>
                      </svg>
                    <% end %>
                    <div style={"width: 44px; height: 44px; border-radius: 50%; background: #{Enum.at(colores_mini, rem(cajero.id, length(colores_mini)))}; display: flex; align-items: flex-end; justify-content: center; overflow: hidden; margin-bottom: 6px; flex-shrink: 0;"}>
                      <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                        <path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/>
                        <path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>
                      </svg>
                    </div>
                    <p style="font-size: 11px; font-weight: 700; color: #111; margin: 0; text-align: center; font-family: Poppins, sans-serif; max-width: 68px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                      <%= apellido_mini %>
                    </p>
                  </div>
                <% end %>
              </div>
              <div style="flex: 1; min-width: 0; position: relative; display: flex; align-items: flex-end; justify-content: flex-start; gap: 10px; height: 180px; padding: 0 8px; border-radius: 12px; background-color: #f7f5ef; background-image: repeating-linear-gradient(to bottom, transparent 0, transparent 29px, #e6e0d2 29px, #e6e0d2 30px); background-position: bottom; overflow-x: hidden; overflow-y: hidden;">
                <%= for {cajero, puntos} <- @ranking_puntualidad do %>
                  <%
                    altura = max(10, round(puntos / max_puntos * 148))
                  %>
                  <div style="display: flex; flex-direction: column; align-items: center; gap: 8px; width: 34px;">
                    <div title={"#{puntos} pts"} style={"width: 20px; background: #186904; height: #{altura}px; border-radius: 5px 5px 0 0;"}></div>
                    <p style="font-size: 9.5px; font-weight: 600; color: #555; margin: 0; text-align: center; font-family: Poppins, sans-serif; line-height: 1.15; max-width: 34px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                      <%= nombre_corto(cajero) %>
                    </p>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
          <a href={"/mi-tienda/cajeros/asistencia?sede=#{@sede_actual}"} style="display: block; text-align: center; background-color: white; color: #186904; padding: 11px; border-radius: 14px; margin-top: 16px; font-family: Poppins, sans-serif; font-weight: 700; font-size: 13px; border: 1.5px solid #186904; text-decoration: none;">
            Ver detalle
          </a>
        </div>
      <% else %>
        <div style="background: #f5f5f5; border: 1.5px solid #e5e5e5; border-radius: 18px; padding: 22px 16px; text-align: center;">
          <p style="font-size: 12px; color: #aaa; margin: 0; font-family: Poppins, sans-serif;">Activá Estadísticas para ver este panel</p>
        </div>
      <% end %>

      <div style="height: 1px; background: #eee; margin: 24px 0 20px;"></div>

      <p style="font-size: 12px; font-weight: 700; margin: 0 0 4px; text-transform: uppercase; letter-spacing: 1px; color: #999;">Ventas</p>
      <p style="font-size: 11.5px; color: #999; margin: 0 0 10px; font-family: Poppins, sans-serif; line-height: 1.4;">Mide productos vendidos, con bonus por venta múltiple. Aplica a los roles de Cajero y MultiTask.</p>

      <%= if @brand.ventas_activa do %>
        <div style="background: white; border: 1.5px solid #186904; border-radius: 18px; padding: 18px 16px; box-shadow: 0 3px 12px rgba(24,105,4,0.08);">
          <%= if Enum.empty?(@ranking_ventas) do %>
            <div style="display: flex; align-items: center; gap: 10px;">
              <div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 8px; flex-shrink: 0;">
                <%= for i <- 1..4 do %>
                  <div style="position: relative; display: flex; flex-direction: column; align-items: center; background: white; border: 1.5px solid #f0f0f0; border-radius: 14px; padding: 8px 6px 6px; width: 74px; box-sizing: border-box; box-shadow: 0 2px 6px rgba(0,0,0,0.05); opacity: 0.55;">
                    <div style="width: 44px; height: 44px; border-radius: 50%; background: #ccc; display: flex; align-items: flex-end; justify-content: center; overflow: hidden; margin-bottom: 6px; flex-shrink: 0;">
                      <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                        <path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/>
                        <path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>
                      </svg>
                    </div>
                    <p style="font-size: 11px; font-weight: 700; color: #999; margin: 0; text-align: center; font-family: Poppins, sans-serif;">Empleado <%= i %></p>
                  </div>
                <% end %>
              </div>
              <div style="flex: 1; min-width: 0; position: relative; display: flex; align-items: flex-end; justify-content: flex-start; gap: 10px; height: 180px; padding: 0 8px; border-radius: 12px; background-color: #f7f5ef; background-image: repeating-linear-gradient(to bottom, transparent 0, transparent 29px, #e6e0d2 29px, #e6e0d2 30px); background-position: bottom; overflow-x: auto; overflow-y: hidden;">
                <%= for _i <- 1..4 do %>
                  <div style="display: flex; flex-direction: column; align-items: center; gap: 8px; width: 34px;">
                    <div style="width: 20px; background: #186904; opacity: 0.15; height: 6px; border-radius: 5px 5px 0 0;"></div>
                  </div>
                <% end %>
              </div>
            </div>
            <p style="font-size: 11px; color: #999; margin: 10px 0 0; text-align: center; font-family: Poppins, sans-serif;">Todavía no hay ventas registradas</p>
          <% else %>
            <%
              max_puntos_ventas = @ranking_ventas |> Enum.map(fn {_cajero, puntos} -> puntos end) |> Enum.max()
              colores_mini_ventas = ["#E91E8C", "#186904", "#2b2b2b", "#0066cc", "#e67e22", "#8e44ad", "#c0392b", "#16a085"]
            %>
            <div style="display: flex; align-items: center; gap: 10px;">
              <div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 8px; flex-shrink: 0;">
                <%= for {{cajero, _puntos}, i} <- Enum.with_index(@ranking_ventas) do %>
                  <%
                    apellido_mini_venta = nombre_corto(cajero)
                  %>
                  <div style="position: relative; display: flex; flex-direction: column; align-items: center; background: white; border: 1.5px solid #f0f0f0; border-radius: 14px; padding: 8px 6px 6px; width: 74px; box-sizing: border-box; box-shadow: 0 2px 6px rgba(0,0,0,0.05);">
                    <%= if i == 0 do %>
                      <svg width="20" height="20" viewBox="0 0 24 24" fill="#f5b301" stroke="#f5b301" style="position: absolute; top: -10px; left: 50%; transform: translateX(-50%); z-index: 2;">
                        <path d="M2 18h20l-2-9-5 4-3-7-3 7-5-4-2 9z"/>
                      </svg>
                    <% end %>
                    <div style={"width: 44px; height: 44px; border-radius: 50%; background: #{Enum.at(colores_mini_ventas, rem(cajero.id, length(colores_mini_ventas)))}; display: flex; align-items: flex-end; justify-content: center; overflow: hidden; margin-bottom: 6px; flex-shrink: 0;"}>
                      <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                        <path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/>
                        <path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>
                      </svg>
                    </div>
                    <p style="font-size: 11px; font-weight: 700; color: #111; margin: 0; text-align: center; font-family: Poppins, sans-serif; max-width: 68px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                      <%= apellido_mini_venta %>
                    </p>
                  </div>
                <% end %>
              </div>
              <div style="flex: 1; min-width: 0; position: relative; display: flex; align-items: flex-end; justify-content: flex-start; gap: 10px; height: 180px; padding: 0 8px; border-radius: 12px; background-color: #f7f5ef; background-image: repeating-linear-gradient(to bottom, transparent 0, transparent 29px, #e6e0d2 29px, #e6e0d2 30px); background-position: bottom; overflow-x: auto; overflow-y: hidden;">
                <%= for {cajero, puntos} <- @ranking_ventas do %>
                  <%
                    altura_venta = max(10, round(puntos / max_puntos_ventas * 148))
                  %>
                  <div style="display: flex; flex-direction: column; align-items: center; gap: 8px; width: 34px;">
                    <div title={"#{puntos} pts"} style={"width: 20px; background: #186904; height: #{altura_venta}px; border-radius: 5px 5px 0 0;"}></div>
                    <p style="font-size: 9.5px; font-weight: 600; color: #555; margin: 0; text-align: center; font-family: Poppins, sans-serif; line-height: 1.15; max-width: 34px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                      <%= nombre_corto(cajero) %>
                    </p>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
          <.link navigate={"/mi-tienda/cajeros/ventas?sede=#{@sede_actual}"} style="display: block; text-align: center; background-color: white; color: #186904; padding: 11px; border-radius: 14px; margin-top: 16px; font-family: Poppins, sans-serif; font-weight: 700; font-size: 13px; border: 1.5px solid #186904; text-decoration: none;">
            Ver detalle
          </.link>
        </div>
      <% else %>
        <div style="background: #f5f5f5; border: 1.5px solid #e5e5e5; border-radius: 18px; padding: 22px 16px; text-align: center;">
          <p style="font-size: 12px; color: #aaa; margin: 0; font-family: Poppins, sans-serif;">Activá Estadísticas para ver este panel</p>
        </div>
      <% end %>

      <div style="height: 1px; background: #eee; margin: 24px 0 20px;"></div>

      <p style="font-size: 12px; font-weight: 700; margin: 0 0 4px; text-transform: uppercase; letter-spacing: 1px; color: #999;">Gestores</p>
      <p style="font-size: 11.5px; color: #999; margin: 0 0 10px; font-family: Poppins, sans-serif; line-height: 1.4;">Mide productos creados y problemas de stock resueltos. Aplica a los roles de Gestiones y MultiTask.</p>

      <%= if @brand.gestiones_activa do %>
        <div style="background: white; border: 1.5px solid #186904; border-radius: 18px; padding: 18px 16px; box-shadow: 0 3px 12px rgba(24,105,4,0.08);">
          <%= if Enum.empty?(@ranking_gestores) do %>
            <div style="display: flex; align-items: center; gap: 10px;">
              <div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 8px; flex-shrink: 0;">
                <%= for i <- 1..4 do %>
                  <div style="position: relative; display: flex; flex-direction: column; align-items: center; background: white; border: 1.5px solid #f0f0f0; border-radius: 14px; padding: 8px 6px 6px; width: 74px; box-sizing: border-box; box-shadow: 0 2px 6px rgba(0,0,0,0.05); opacity: 0.55;">
                    <div style="width: 44px; height: 44px; border-radius: 50%; background: #ccc; display: flex; align-items: flex-end; justify-content: center; overflow: hidden; margin-bottom: 6px; flex-shrink: 0;">
                      <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                        <path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/>
                        <path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>
                      </svg>
                    </div>
                    <p style="font-size: 11px; font-weight: 700; color: #999; margin: 0; text-align: center; font-family: Poppins, sans-serif;">Empleado <%= i %></p>
                  </div>
                <% end %>
              </div>
              <div style="flex: 1; min-width: 0; position: relative; display: flex; align-items: flex-end; justify-content: flex-start; gap: 10px; height: 180px; padding: 0 8px; border-radius: 12px; background-color: #f7f5ef; background-image: repeating-linear-gradient(to bottom, transparent 0, transparent 29px, #e6e0d2 29px, #e6e0d2 30px); background-position: bottom; overflow-x: auto; overflow-y: hidden;">
                <%= for _i <- 1..4 do %>
                  <div style="display: flex; flex-direction: column; align-items: center; gap: 8px; width: 34px;">
                    <div style="width: 20px; background: #186904; opacity: 0.15; height: 6px; border-radius: 5px 5px 0 0;"></div>
                  </div>
                <% end %>
              </div>
            </div>
            <p style="font-size: 11px; color: #999; margin: 10px 0 0; text-align: center; font-family: Poppins, sans-serif;">Todavía no hay creaciones de stock registradas</p>
          <% else %>
            <%
              max_puntos_gestores = @ranking_gestores |> Enum.map(fn {_cajero, puntos} -> puntos end) |> Enum.max()
              colores_mini_gestores = ["#E91E8C", "#186904", "#2b2b2b", "#0066cc", "#e67e22", "#8e44ad", "#c0392b", "#16a085"]
            %>
            <div style="display: flex; align-items: center; gap: 10px;">
              <div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 8px; flex-shrink: 0;">
                <%= for {{cajero, _puntos}, i} <- Enum.with_index(@ranking_gestores) do %>
                  <%
                    apellido_mini_gestor = nombre_corto(cajero)
                  %>
                  <div style="position: relative; display: flex; flex-direction: column; align-items: center; background: white; border: 1.5px solid #f0f0f0; border-radius: 14px; padding: 8px 6px 6px; width: 74px; box-sizing: border-box; box-shadow: 0 2px 6px rgba(0,0,0,0.05);">
                    <%= if i == 0 do %>
                      <svg width="20" height="20" viewBox="0 0 24 24" fill="#f5b301" stroke="#f5b301" style="position: absolute; top: -10px; left: 50%; transform: translateX(-50%); z-index: 2;">
                        <path d="M2 18h20l-2-9-5 4-3-7-3 7-5-4-2 9z"/>
                      </svg>
                    <% end %>
                    <div style={"width: 44px; height: 44px; border-radius: 50%; background: #{Enum.at(colores_mini_gestores, rem(cajero.id, length(colores_mini_gestores)))}; display: flex; align-items: flex-end; justify-content: center; overflow: hidden; margin-bottom: 6px; flex-shrink: 0;"}>
                      <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                        <path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/>
                        <path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>
                      </svg>
                    </div>
                    <p style="font-size: 11px; font-weight: 700; color: #111; margin: 0; text-align: center; font-family: Poppins, sans-serif; max-width: 68px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                      <%= apellido_mini_gestor %>
                    </p>
                  </div>
                <% end %>
              </div>
              <div style="flex: 1; min-width: 0; position: relative; display: flex; align-items: flex-end; justify-content: flex-start; gap: 10px; height: 180px; padding: 0 8px; border-radius: 12px; background-color: #f7f5ef; background-image: repeating-linear-gradient(to bottom, transparent 0, transparent 29px, #e6e0d2 29px, #e6e0d2 30px); background-position: bottom; overflow-x: auto; overflow-y: hidden;">
                <%= for {cajero, puntos} <- @ranking_gestores do %>
                  <%
                    altura_gestor = max(10, round(puntos / max_puntos_gestores * 148))
                  %>
                  <div style="display: flex; flex-direction: column; align-items: center; gap: 8px; width: 34px;">
                    <div title={"#{puntos} pts"} style={"width: 20px; background: #186904; height: #{altura_gestor}px; border-radius: 5px 5px 0 0;"}></div>
                    <p style="font-size: 9.5px; font-weight: 600; color: #555; margin: 0; text-align: center; font-family: Poppins, sans-serif; line-height: 1.15; max-width: 34px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                      <%= nombre_corto(cajero) %>
                    </p>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
          <.link navigate={"/mi-tienda/cajeros/gestores?sede=#{@sede_actual}"} style="display: block; text-align: center; background-color: white; color: #186904; padding: 11px; border-radius: 14px; margin-top: 16px; font-family: Poppins, sans-serif; font-weight: 700; font-size: 13px; border: 1.5px solid #186904; text-decoration: none;">
            Ver detalle
          </.link>
        </div>
      <% else %>
        <div style="background: #f5f5f5; border: 1.5px solid #e5e5e5; border-radius: 18px; padding: 22px 16px; text-align: center;">
          <p style="font-size: 12px; color: #aaa; margin: 0; font-family: Poppins, sans-serif;">Activá Estadísticas para ver este panel</p>
        </div>
      <% end %>

      <%= if @brand.asistencia_activa do %>
        <div style="height: 1px; background: #eee; margin: 24px 0 20px;"></div>
        <p style="font-size: 12px; font-weight: 700; margin: 0 0 10px; text-transform: uppercase; letter-spacing: 1px; color: #999;">Empleado del mes</p>
        <div style="background: white; border: 1.5px solid #186904; border-radius: 18px; padding: 24px 16px; box-shadow: 0 3px 12px rgba(24,105,4,0.08); display: flex; flex-direction: column; align-items: center;">
          <div style="position: relative; margin-bottom: 4px;">
            <svg width="30" height="30" viewBox="0 0 24 24" fill="#f5b301" stroke="#f5b301" style="position: absolute; top: -20px; left: 50%; transform: translateX(-50%); filter: drop-shadow(0 2px 3px rgba(0,0,0,0.2));"><path d="M2 18h20l-2-9-5 4-3-7-3 7-5-4-2 9z"/></svg>
            <div style="width: 72px; height: 72px; border-radius: 50%; background: white; border: 2px solid #f0f0f0; display: flex; align-items: center; justify-content: center; box-shadow: 0 3px 10px rgba(0,0,0,0.08);">
              <span style="font-size: 32px; color: #111; font-weight: 800;">?</span>
            </div>
          </div>
          <p style="font-size: 12.5px; color: #999; margin: 8px 0 0; font-family: Poppins, sans-serif; text-align: center;">Todavía no hay empleado del mes</p>
        </div>
      <% end %>
      </div>

      <div style="height: 1px; background: #eee; margin: 24px 0 20px;"></div>

      <div style="background: white; border: 1.5px solid #186904; border-radius: 18px; padding: 18px 16px; box-shadow: 0 3px 12px rgba(24,105,4,0.08);">
        <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 14px;">
          <p style="font-size: 13px; font-weight: 700; margin: 0; text-transform: uppercase; letter-spacing: 1px; color: #186904;">Recompensas</p>
          <button type="button" phx-click="toggle_empleado_puntos" style={"width: 50px; height: 28px; border-radius: 20px; border: none; cursor: pointer; padding: 3px; display: flex; align-items: center; background: #{if @brand.empleado_puntos_activa, do: "#186904", else: "#ccc"}; justify-content: #{if @brand.empleado_puntos_activa, do: "flex-end", else: "flex-start"}; transition: background 0.2s;"}>
            <div style="width: 22px; height: 22px; border-radius: 50%; background: white; box-shadow: 0 1px 3px rgba(0,0,0,0.3); transition: transform 0.2s;"></div>
          </button>
        </div>

        <div style="height: 1px; background: #eee; margin: 0 0 14px;"></div>

        <p style="font-size: 12px; font-weight: 700; margin: 0 0 6px; text-transform: uppercase; letter-spacing: 1px; color: #999;">¿Qué es esto?</p>
        <p style="font-size: 11.5px; color: #999; margin: 0; font-family: Poppins, sans-serif; line-height: 1.4;">Si activás esto, tus empleados van a ganar puntos en las tablas de Asistencia, Ventas y Gestores según la cantidad de gente que compita en cada categoría. Con esos puntos, después vas a poder crear premios acá abajo (por ejemplo: "500 puntos = una tarde libre"). Distintos estudios muestran que los sistemas de recompensa bien diseñados mejoran el desempeño y la retención de los empleados.</p>
      </div>

      <%= if @brand.empleado_puntos_activa do %>
        <div style="background: #fafaf7; border: 1.5px solid #e6e0d2; border-radius: 22px; padding: 18px 14px; margin-top: 16px;">
          <p style="font-size: 12px; font-weight: 700; margin: 0 0 8px; text-transform: uppercase; letter-spacing: 1px; color: #999;">Mercado</p>
          <div style="background: linear-gradient(180deg, #eaf3ff 0%, #ffffff 55%); border: 1.5px solid #186904; border-radius: 18px; padding: 14px; box-shadow: 0 3px 12px rgba(24,105,4,0.08); margin-bottom: 14px; overflow: hidden;">
            <style>
              @keyframes caerFicha {
                0%   { transform: translateY(-6px) rotate(calc(var(--rot) - 3deg)); }
                50%  { transform: translateY(6px) rotate(calc(var(--rot) + 3deg)); }
                100% { transform: translateY(-6px) rotate(calc(var(--rot) - 3deg)); }
              }
              @keyframes monedaCae {
                0%   { transform: translateY(-260px) rotate(var(--rot)); opacity: 0; }
                8%   { opacity: 1; }
                92%  { opacity: 1; }
                100% { transform: translateY(260px) rotate(var(--rot)); opacity: 0; }
              }
            </style>
            <div style="position: relative; height: 230px;">
            <div style="position: absolute; top: 5px; left: 10px; --rot: -16deg; animation: caerFicha 2.8s ease-in-out infinite; animation-delay: -0.01s; display: flex; flex-direction: column; align-items: center; background: white; border: 1.5px solid #f0f0f0; border-radius: 14px; padding: 8px 6px 6px; width: 74px; box-sizing: border-box; box-shadow: 0 2px 6px rgba(0,0,0,0.05);">
              <div style="width: 44px; height: 44px; border-radius: 50%; background: #E91E8C; display: flex; align-items: flex-end; justify-content: center; overflow: hidden; margin-bottom: 6px; flex-shrink: 0;">
                <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/>
                  <path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>
                </svg>
              </div>
              <p style="font-size: 11px; font-weight: 700; color: #111; margin: 0; text-align: center; font-family: Poppins, sans-serif;">Vera</p>
            </div>
            <div style="position: absolute; top: 0px; left: 95px; --rot: 10deg; animation: caerFicha 2.8s ease-in-out infinite; animation-delay: -0.35s; display: flex; flex-direction: column; align-items: center; background: white; border: 1.5px solid #f0f0f0; border-radius: 14px; padding: 8px 6px 6px; width: 74px; box-sizing: border-box; box-shadow: 0 2px 6px rgba(0,0,0,0.05);">
              <div style="width: 44px; height: 44px; border-radius: 50%; background: #186904; display: flex; align-items: flex-end; justify-content: center; overflow: hidden; margin-bottom: 6px; flex-shrink: 0;">
                <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/>
                  <path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>
                </svg>
              </div>
              <p style="font-size: 11px; font-weight: 700; color: #111; margin: 0; text-align: center; font-family: Poppins, sans-serif;">Paz</p>
            </div>
            <div style="position: absolute; top: 55px; left: 125px; --rot: -20deg; animation: caerFicha 2.8s ease-in-out infinite; animation-delay: -0.7s; display: flex; flex-direction: column; align-items: center; background: white; border: 1.5px solid #f0f0f0; border-radius: 14px; padding: 8px 6px 6px; width: 74px; box-sizing: border-box; box-shadow: 0 2px 6px rgba(0,0,0,0.05);">
              <div style="width: 44px; height: 44px; border-radius: 50%; background: #0066cc; display: flex; align-items: flex-end; justify-content: center; overflow: hidden; margin-bottom: 6px; flex-shrink: 0;">
                <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/>
                  <path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>
                </svg>
              </div>
              <p style="font-size: 11px; font-weight: 700; color: #111; margin: 0; text-align: center; font-family: Poppins, sans-serif;">Luna</p>
            </div>
            <div style="position: absolute; top: 10px; left: 205px; --rot: 14deg; animation: caerFicha 2.8s ease-in-out infinite; animation-delay: -1.05s; display: flex; flex-direction: column; align-items: center; background: white; border: 1.5px solid #f0f0f0; border-radius: 14px; padding: 8px 6px 6px; width: 74px; box-sizing: border-box; box-shadow: 0 2px 6px rgba(0,0,0,0.05);">
              <div style="width: 44px; height: 44px; border-radius: 50%; background: #e67e22; display: flex; align-items: flex-end; justify-content: center; overflow: hidden; margin-bottom: 6px; flex-shrink: 0;">
                <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/>
                  <path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>
                </svg>
              </div>
              <p style="font-size: 11px; font-weight: 700; color: #111; margin: 0; text-align: center; font-family: Poppins, sans-serif;">Ríos</p>
            </div>
            <div style="position: absolute; top: 70px; left: 15px; --rot: 18deg; animation: caerFicha 2.8s ease-in-out infinite; animation-delay: -1.4s; display: flex; flex-direction: column; align-items: center; background: white; border: 1.5px solid #f0f0f0; border-radius: 14px; padding: 8px 6px 6px; width: 74px; box-sizing: border-box; box-shadow: 0 2px 6px rgba(0,0,0,0.05);">
              <div style="width: 44px; height: 44px; border-radius: 50%; background: #c0392b; display: flex; align-items: flex-end; justify-content: center; overflow: hidden; margin-bottom: 6px; flex-shrink: 0;">
                <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/>
                  <path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>
                </svg>
              </div>
              <p style="font-size: 11px; font-weight: 700; color: #111; margin: 0; text-align: center; font-family: Poppins, sans-serif;">Cruz</p>
            </div>
            <div style="position: absolute; top: 95px; left: 190px; --rot: -12deg; animation: caerFicha 2.8s ease-in-out infinite; animation-delay: -1.75s; display: flex; flex-direction: column; align-items: center; background: white; border: 1.5px solid #f0f0f0; border-radius: 14px; padding: 8px 6px 6px; width: 74px; box-sizing: border-box; box-shadow: 0 2px 6px rgba(0,0,0,0.05);">
              <div style="width: 44px; height: 44px; border-radius: 50%; background: #8e44ad; display: flex; align-items: flex-end; justify-content: center; overflow: hidden; margin-bottom: 6px; flex-shrink: 0;">
                <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/>
                  <path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>
                </svg>
              </div>
              <p style="font-size: 11px; font-weight: 700; color: #111; margin: 0; text-align: center; font-family: Poppins, sans-serif;">Ibáñez</p>
            </div>
            <div style="position: absolute; top: 130px; left: 80px; --rot: -8deg; animation: caerFicha 2.8s ease-in-out infinite; animation-delay: -2.1s; display: flex; flex-direction: column; align-items: center; background: white; border: 1.5px solid #f0f0f0; border-radius: 14px; padding: 8px 6px 6px; width: 74px; box-sizing: border-box; box-shadow: 0 2px 6px rgba(0,0,0,0.05);">
              <div style="width: 44px; height: 44px; border-radius: 50%; background: #16a085; display: flex; align-items: flex-end; justify-content: center; overflow: hidden; margin-bottom: 6px; flex-shrink: 0;">
                <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/>
                  <path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>
                </svg>
              </div>
              <p style="font-size: 11px; font-weight: 700; color: #111; margin: 0; text-align: center; font-family: Poppins, sans-serif;">Ortega</p>
            </div>
            <div style="position: absolute; top: 135px; left: 245px; --rot: 16deg; animation: caerFicha 2.8s ease-in-out infinite; animation-delay: -2.45s; display: flex; flex-direction: column; align-items: center; background: white; border: 1.5px solid #f0f0f0; border-radius: 14px; padding: 8px 6px 6px; width: 74px; box-sizing: border-box; box-shadow: 0 2px 6px rgba(0,0,0,0.05);">
              <div style="width: 44px; height: 44px; border-radius: 50%; background: #2b2b2b; display: flex; align-items: flex-end; justify-content: center; overflow: hidden; margin-bottom: 6px; flex-shrink: 0;">
                <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/>
                  <path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>
                </svg>
              </div>
              <p style="font-size: 11px; font-weight: 700; color: #111; margin: 0; text-align: center; font-family: Poppins, sans-serif;">Vidal</p>
            </div>
            <svg width="26" height="26" viewBox="-13 -13 26 26" style="position: absolute; top: 15px; left: 175px; --rot: 20deg; animation: monedaCae 2.2s ease-in infinite; animation-delay: -0.0s; pointer-events: none;">
              <defs>
                <linearGradient id="coinFace1" x1="0" y1="0" x2="1" y2="1">
                  <stop offset="0%" stop-color="#ffe27a"/>
                  <stop offset="60%" stop-color="#f0c040"/>
                  <stop offset="100%" stop-color="#c9971b"/>
                </linearGradient>
              </defs>
              <ellipse cx="1.5" cy="0" rx="9" ry="9" fill="#a8790a"/>
              <circle cx="0" cy="0" r="9" fill="url(#coinFace1)" stroke="#a8790a" stroke-width="1"/>
              <path d="M6 -6 L7 -6 M6.8 -3 L7.8 -3 M7.2 0 L8.2 0 M6.8 3 L7.8 3 M6 6 L7 6" stroke="#8a6208" stroke-width="0.8" stroke-linecap="round"/>
              <ellipse cx="-3" cy="-3" rx="3" ry="2" fill="white" opacity="0.5"/>
            </svg>
            <svg width="26" height="26" viewBox="-13 -13 26 26" style="position: absolute; top: 0px; left: 265px; --rot: -15deg; animation: monedaCae 2.2s ease-in infinite; animation-delay: -0.37s; pointer-events: none;">
              <defs>
                <linearGradient id="coinFace2" x1="0" y1="0" x2="1" y2="1">
                  <stop offset="0%" stop-color="#ffe27a"/>
                  <stop offset="60%" stop-color="#f0c040"/>
                  <stop offset="100%" stop-color="#c9971b"/>
                </linearGradient>
              </defs>
              <ellipse cx="1.5" cy="0" rx="9" ry="9" fill="#a8790a"/>
              <circle cx="0" cy="0" r="9" fill="url(#coinFace2)" stroke="#a8790a" stroke-width="1"/>
              <path d="M6 -6 L7 -6 M6.8 -3 L7.8 -3 M7.2 0 L8.2 0 M6.8 3 L7.8 3 M6 6 L7 6" stroke="#8a6208" stroke-width="0.8" stroke-linecap="round"/>
              <ellipse cx="-3" cy="-3" rx="3" ry="2" fill="white" opacity="0.5"/>
            </svg>
            <svg width="26" height="26" viewBox="-13 -13 26 26" style="position: absolute; top: 95px; left: 0px; --rot: 25deg; animation: monedaCae 2.2s ease-in infinite; animation-delay: -0.74s; pointer-events: none;">
              <defs>
                <linearGradient id="coinFace3" x1="0" y1="0" x2="1" y2="1">
                  <stop offset="0%" stop-color="#ffe27a"/>
                  <stop offset="60%" stop-color="#f0c040"/>
                  <stop offset="100%" stop-color="#c9971b"/>
                </linearGradient>
              </defs>
              <ellipse cx="1.5" cy="0" rx="9" ry="9" fill="#a8790a"/>
              <circle cx="0" cy="0" r="9" fill="url(#coinFace3)" stroke="#a8790a" stroke-width="1"/>
              <path d="M6 -6 L7 -6 M6.8 -3 L7.8 -3 M7.2 0 L8.2 0 M6.8 3 L7.8 3 M6 6 L7 6" stroke="#8a6208" stroke-width="0.8" stroke-linecap="round"/>
              <ellipse cx="-3" cy="-3" rx="3" ry="2" fill="white" opacity="0.5"/>
            </svg>
            <svg width="26" height="26" viewBox="-13 -13 26 26" style="position: absolute; top: 55px; left: 265px; --rot: -10deg; animation: monedaCae 2.2s ease-in infinite; animation-delay: -1.11s; pointer-events: none;">
              <defs>
                <linearGradient id="coinFace4" x1="0" y1="0" x2="1" y2="1">
                  <stop offset="0%" stop-color="#ffe27a"/>
                  <stop offset="60%" stop-color="#f0c040"/>
                  <stop offset="100%" stop-color="#c9971b"/>
                </linearGradient>
              </defs>
              <ellipse cx="1.5" cy="0" rx="9" ry="9" fill="#a8790a"/>
              <circle cx="0" cy="0" r="9" fill="url(#coinFace4)" stroke="#a8790a" stroke-width="1"/>
              <path d="M6 -6 L7 -6 M6.8 -3 L7.8 -3 M7.2 0 L8.2 0 M6.8 3 L7.8 3 M6 6 L7 6" stroke="#8a6208" stroke-width="0.8" stroke-linecap="round"/>
              <ellipse cx="-3" cy="-3" rx="3" ry="2" fill="white" opacity="0.5"/>
            </svg>
            <svg width="26" height="26" viewBox="-13 -13 26 26" style="position: absolute; top: 165px; left: 10px; --rot: 15deg; animation: monedaCae 2.2s ease-in infinite; animation-delay: -1.48s; pointer-events: none;">
              <defs>
                <linearGradient id="coinFace5" x1="0" y1="0" x2="1" y2="1">
                  <stop offset="0%" stop-color="#ffe27a"/>
                  <stop offset="60%" stop-color="#f0c040"/>
                  <stop offset="100%" stop-color="#c9971b"/>
                </linearGradient>
              </defs>
              <ellipse cx="1.5" cy="0" rx="9" ry="9" fill="#a8790a"/>
              <circle cx="0" cy="0" r="9" fill="url(#coinFace5)" stroke="#a8790a" stroke-width="1"/>
              <path d="M6 -6 L7 -6 M6.8 -3 L7.8 -3 M7.2 0 L8.2 0 M6.8 3 L7.8 3 M6 6 L7 6" stroke="#8a6208" stroke-width="0.8" stroke-linecap="round"/>
              <ellipse cx="-3" cy="-3" rx="3" ry="2" fill="white" opacity="0.5"/>
            </svg>
            <svg width="26" height="26" viewBox="-13 -13 26 26" style="position: absolute; top: 185px; left: 165px; --rot: -20deg; animation: monedaCae 2.2s ease-in infinite; animation-delay: -1.85s; pointer-events: none;">
              <defs>
                <linearGradient id="coinFace6" x1="0" y1="0" x2="1" y2="1">
                  <stop offset="0%" stop-color="#ffe27a"/>
                  <stop offset="60%" stop-color="#f0c040"/>
                  <stop offset="100%" stop-color="#c9971b"/>
                </linearGradient>
              </defs>
              <ellipse cx="1.5" cy="0" rx="9" ry="9" fill="#a8790a"/>
              <circle cx="0" cy="0" r="9" fill="url(#coinFace6)" stroke="#a8790a" stroke-width="1"/>
              <path d="M6 -6 L7 -6 M6.8 -3 L7.8 -3 M7.2 0 L8.2 0 M6.8 3 L7.8 3 M6 6 L7 6" stroke="#8a6208" stroke-width="0.8" stroke-linecap="round"/>
              <ellipse cx="-3" cy="-3" rx="3" ry="2" fill="white" opacity="0.5"/>
            </svg>
            </div>
            <.link navigate="/mi-tienda/cajeros/mercado" style="position: relative; z-index: 5; display: block; text-align: center; background-color: white; color: #186904; padding: 11px; margin-top: 14px; border-radius: 14px; font-family: Poppins, sans-serif; font-weight: 700; font-size: 13px; border: 1.5px solid #186904; text-decoration: none;">
              Mercado de puntos
            </.link>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
