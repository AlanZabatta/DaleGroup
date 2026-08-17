defmodule DaleAppWeb.BitacoraLive do
  use DaleAppWeb, :live_view
  import Ecto.Query, only: [from: 2]
  alias DaleApp.Repo
  alias DaleApp.Brands.Brand

  def mount(_params, session, socket) do
    user_id = session["user_id"]
    brand = if user_id, do: Repo.get_by(Brand, user_id: user_id), else: nil
    cajeros = if brand, do: DaleApp.Accounts.list_cajeros(brand.id), else: []
    movimientos = if brand, do: DaleApp.Products.listar_movimientos_stock(brand.id, 200), else: []

    ids_usuarios = movimientos |> Enum.map(& &1.user_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    usuarios =
      if ids_usuarios == [] do
        %{}
      else
        from(u in DaleApp.Accounts.User, where: u.id in ^ids_usuarios)
        |> Repo.all()
        |> Map.new(fn u -> {u.id, u} end)
      end

    {:ok,
     assign(socket,
       brand: brand,
       user_id: user_id,
       cajeros: cajeros,
       movimientos_stock: movimientos,
       usuarios_bitacora: usuarios,
       filtro_empleado_id: nil,
       filtro_tipo: nil,
       busqueda_producto: ""
     )}
  end

  def handle_event("filtrar_por_empleado", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    nuevo_filtro = if socket.assigns.filtro_empleado_id == id, do: nil, else: id
    {:noreply, assign(socket, filtro_empleado_id: nuevo_filtro)}
  end

  def handle_event("filtrar_por_empleado_vos", _params, socket) do
    nuevo_filtro = if socket.assigns.filtro_empleado_id == :vos, do: nil, else: :vos
    {:noreply, assign(socket, filtro_empleado_id: nuevo_filtro)}
  end

  def handle_event("buscar_bitacora", %{"busqueda" => texto}, socket) do
    {:noreply, assign(socket, busqueda_producto: texto)}
  end

  def handle_event("filtrar_por_tipo", %{"tipo" => tipo}, socket) do
    nuevo_filtro = if socket.assigns.filtro_tipo == tipo, do: nil, else: tipo
    {:noreply, assign(socket, filtro_tipo: nuevo_filtro)}
  end

  defp movimientos_filtrados(movimientos, filtro_empleado_id, filtro_tipo, user_id, busqueda) do
    movimientos
    |> Enum.filter(fn mov ->
      case filtro_empleado_id do
        nil -> true
        :vos -> mov.user_id == user_id
        id -> mov.user_id == id
      end
    end)
    |> Enum.filter(fn mov ->
      is_nil(filtro_tipo) or mov.tipo_accion == filtro_tipo
    end)
    |> Enum.filter(fn mov ->
      texto_busqueda = String.trim(busqueda || "")
      if texto_busqueda == "" do
        true
      else
        nombre_prod = mov.producto_nombre || ""
        String.contains?(String.downcase(nombre_prod), String.downcase(texto_busqueda))
      end
    end)
  end

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

  defp nombre_de(usuario_mov, es_vos) do
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
  end

  def render(assigns) do
    ~H"""
    <div style="padding: 24px 18px 40px; font-family: Poppins, sans-serif; max-width: 600px; margin: 0 auto; background-color: white; min-height: 100vh;">
      <style>
        #fila-empleados-bitacora::-webkit-scrollbar { display: none; }
      </style>
      <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 16px;">
        <.link navigate="/mi-tienda/stock" style="display: inline-flex; background: none; border: none; color: #186904; font-size: 22px; font-weight: 700; cursor: pointer; line-height: 1; text-decoration: none;">&#x2715;</.link>
        <.link navigate="/mi-tienda/stock/configuracion" style="background: none; border: none; padding: 0; cursor: pointer; display: flex; align-items: center; text-decoration: none;">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
            <circle cx="12" cy="12" r="3"/>
            <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>
          </svg>
        </.link>
      </div>
      <p style="font-size: 26px; font-weight: 800; color: #186904; margin: 0 0 20px;">Bitácora detallada</p>

      <%
        colores_bitacora = ["#E91E8C", "#186904", "#2b2b2b", "#0066cc", "#e67e22", "#8e44ad", "#c0392b", "#16a085"]
        tipos_disponibles = [{"creado", "Creaciones"}, {"editado", "Ediciones"}, {"aumentado", "Aumentos"}, {"disminuido", "Disminuciones"}, {"eliminado", "Eliminaciones"}]
      %>

      <p style="font-size: 11px; font-weight: 700; color: #999; margin: 0 0 8px; text-transform: uppercase; letter-spacing: 1px;">Filtrar por empleado</p>
      <div id="fila-empleados-bitacora" style="display: flex; gap: 16px; overflow-x: auto; padding-bottom: 6px; margin-bottom: 18px; scrollbar-width: none;">
        <button type="button" phx-click="filtrar_por_empleado_vos" style={"display: flex; flex-direction: column; align-items: center; gap: 4px; background: none; border: none; cursor: pointer; padding: 0; flex-shrink: 0; opacity: #{if @filtro_empleado_id != nil && @filtro_empleado_id != :vos, do: "0.35", else: "1"};"}>
          <div style={"width: 62px; height: 62px; border-radius: 50%; background: #186904; display: flex; align-items: flex-end; justify-content: center; overflow: hidden; border: #{if @filtro_empleado_id == :vos, do: "3px solid #186904", else: "3px solid transparent"};"}>
            <svg width="52" height="52" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">
              <path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/>
              <path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>
            </svg>
          </div>
          <span style="font-size: 12px; font-weight: 700; color: #333;">Vos</span>
        </button>
        <%= for {cajero, i} <- Enum.with_index(@cajeros) do %>
          <% color_c = Enum.at(colores_bitacora, rem(cajero.id, length(colores_bitacora))) %>
          <button type="button" phx-click="filtrar_por_empleado" phx-value-id={cajero.id} style={"display: flex; flex-direction: column; align-items: center; gap: 4px; background: none; border: none; cursor: pointer; padding: 0; flex-shrink: 0; opacity: #{if @filtro_empleado_id != nil && @filtro_empleado_id != cajero.id, do: "0.35", else: "1"};"}>
            <div style={"width: 62px; height: 62px; border-radius: 50%; background: #{color_c}; display: flex; align-items: flex-end; justify-content: center; overflow: hidden; border: #{if @filtro_empleado_id == cajero.id, do: "3px solid " <> color_c, else: "3px solid transparent"};"}>
              <svg width="52" height="52" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">
                <path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/>
                <path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>
              </svg>
            </div>
            <span style="font-size: 12px; font-weight: 700; color: #333; max-width: 68px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;"><%= cajero.nombre_visible || cajero.name %></span>
          </button>
        <% end %>
      </div>

      <p style="font-size: 11px; font-weight: 700; color: #999; margin: 0 0 8px; text-transform: uppercase; letter-spacing: 1px;">Filtrar por tipo</p>
      <div style="display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 22px;">
        <%= for {valor, etiqueta} <- tipos_disponibles do %>
          <button type="button" phx-click="filtrar_por_tipo" phx-value-tipo={valor} style={"padding: 7px 14px; border-radius: 10px; border: 1.5px solid #{if @filtro_tipo == valor, do: "#186904", else: "#e0e0e0"}; background: #{if @filtro_tipo == valor, do: "#186904", else: "white"}; color: #{if @filtro_tipo == valor, do: "white", else: "#555"}; font-family: Poppins, sans-serif; font-size: 12.5px; font-weight: 700; cursor: pointer;"}>
            <%= etiqueta %>
          </button>
        <% end %>
      </div>

      <p style="font-size: 11px; font-weight: 700; color: #999; margin: 0 0 8px; text-transform: uppercase; letter-spacing: 1px;">Bitácora</p>
      <form phx-change="buscar_bitacora" style="margin: 0 0 18px;">
        <input
          type="text"
          name="busqueda"
          value={@busqueda_producto}
          placeholder="Buscar por nombre de producto"
          autocomplete="off"
          style="width: 100%; box-sizing: border-box; padding: 12px 14px; border: 1.5px solid #e0e0e0; border-radius: 14px; font-family: Poppins, sans-serif; font-size: 14px; color: #333; outline: none; background: white;"
        />
      </form>

      <%
        movimientos_mostrados = movimientos_filtrados(@movimientos_stock, @filtro_empleado_id, @filtro_tipo, @user_id, @busqueda_producto)
      %>

      <%= if movimientos_mostrados == [] do %>
        <div style="display: flex; align-items: center; justify-content: center; min-height: 200px; text-align: center;">
          <p style="font-size: 14px; color: #999; margin: 0; font-family: Poppins, sans-serif;">No hay movimientos que coincidan con este filtro.</p>
        </div>
      <% else %>
        <%= for mov <- movimientos_mostrados do %>
          <%
            usuario_mov = mov.user_id && Map.get(@usuarios_bitacora, mov.user_id)
            es_vos = mov.user_id && mov.user_id == @user_id
            color_avatar = if usuario_mov, do: Enum.at(colores_bitacora, rem(usuario_mov.id, length(colores_bitacora))), else: "#bbb"
            nombre_mov = nombre_de(usuario_mov, es_vos)
          %>
          <div style="display: flex; align-items: flex-start; gap: 12px; padding: 14px 4px; border-bottom: 1px solid #f2f2f2;">
            <div style={"width: 42px; height: 42px; border-radius: 50%; background: #{color_avatar}; display: flex; align-items: flex-end; justify-content: center; overflow: hidden; flex-shrink: 0;"}>
              <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">
                <path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/>
                <path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>
              </svg>
            </div>
            <div style="flex: 1; min-width: 0;">
              <div style="display: flex; align-items: baseline; justify-content: space-between; gap: 8px; margin: 0 0 3px;">
                <p style="font-size: 14px; font-weight: 700; color: #111; margin: 0; font-family: Poppins, sans-serif;"><%= nombre_mov %></p>
                <p style="font-size: 11px; color: #aaa; margin: 0; font-family: Poppins, sans-serif; white-space: nowrap; flex-shrink: 0;"><%= formato_fecha_movimiento(mov.inserted_at) %></p>
              </div>
              <p style="font-size: 14px; color: #555; margin: 0; font-family: Poppins, sans-serif;"><%= mov.descripcion %></p>
            </div>
          </div>
        <% end %>
      <% end %>

    </div>
    """
  end
end
