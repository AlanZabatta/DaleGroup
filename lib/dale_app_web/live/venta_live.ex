defmodule DaleAppWeb.VentaLive do
  use DaleAppWeb, :live_view
  alias DaleApp.Repo
  alias DaleApp.Products.StockItem
  alias DaleApp.Products.CategoriaCustom
  alias DaleApp.Accounts.User
  alias DaleApp.Brands.Brand

  @segundos_deshacer 10
  @ventana_dedupe_segundos 5

  @mapa_colores_hex %{
    "Negro" => "#1a1a1a", "Blanco" => "#ffffff", "Gris" => "#9e9e9e", "Beige" => "#e8dcc8",
    "Rojo" => "#d32f2f", "Bordó" => "#6d1b1b", "Rosa" => "#e91e8c", "Naranja" => "#f57c00",
    "Amarillo" => "#fbc02d", "Verde" => "#43a047", "Verde oscuro" => "#1b5e20", "Celeste" => "#4fc3f7",
    "Azul" => "#1565c0", "Azul marino" => "#0d1b4c", "Violeta" => "#7b1fa2", "Marrón" => "#5d3a1a",
    "Dorado" => "#c9a227", "Plateado" => "#b0b0b0"
  }

  def mount(params, session, socket) do
    user_id = session["user_id"]
    codigo = params["c"]

    socket = assign(socket, user_id: user_id, segundos_restantes: 0, grupo_venta_actual: nil, grupo_venta_vence_en: nil)

    socket =
      cond do
        is_nil(user_id) ->
          assign(socket, estado: :sin_sesion)

        is_nil(codigo) ->
          assign(socket, estado: :esperando_escaneo)

        not connected?(socket) ->
          assign(socket, estado: :cargando)

        true ->
          procesar_codigo(socket, user_id, codigo)
      end

    {:ok, socket}
  end

  def handle_event("escanear_manual", %{"codigo" => codigo_ean}, socket) do
    codigo9 =
      case StockItem.desde_ean13(codigo_ean) do
        {:ok, dale9} -> dale9
        {:error, _} -> nil
      end

    if codigo9 do
      {:noreply, procesar_codigo(socket, socket.assigns.user_id, codigo9)}
    else
      {:noreply, assign(socket, estado: :no_encontrado)}
    end
  end

  def handle_event("escanear_otro", _params, socket) do
    {:noreply, assign(socket, estado: :esperando_escaneo, segundos_restantes: 0)}
  end

  def handle_event("deshacer", _params, socket) do
    if socket.assigns[:estado] == :ok && !socket.assigns[:deshecho] && !socket.assigns[:ya_estaba_en_cero] do
      stock_item = Repo.get(StockItem, socket.assigns.stock_item_id)

      {:ok, actualizado} =
        stock_item
        |> StockItem.changeset(%{cantidad: stock_item.cantidad + 1})
        |> Repo.update()

      if socket.assigns[:venta_id] do
        DaleApp.Products.deshacer_venta(socket.assigns.venta_id)
      end

      {:noreply, assign(socket, cantidad: actualizado.cantidad, deshecho: true, segundos_restantes: 0)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:tick_deshacer, socket) do
    puede_seguir = socket.assigns[:estado] == :ok and not socket.assigns[:deshecho]
    nuevos_segundos = socket.assigns[:segundos_restantes] - 1

    if puede_seguir and nuevos_segundos > 0 do
      Process.send_after(self(), :tick_deshacer, 1000)
      {:noreply, assign(socket, segundos_restantes: nuevos_segundos)}
    else
      {:noreply, assign(socket, segundos_restantes: 0)}
    end
  end

  defp tabla_dedupe_ventas do
    case :ets.whereis(:ventas_dedupe) do
      :undefined -> :ets.new(:ventas_dedupe, [:named_table, :public, :set])
      tid -> tid
    end
  end

  defp ya_procesado_hace_poco?(user_id, codigo9) do
    tabla_dedupe_ventas()
    clave = {user_id, codigo9}
    ahora = System.system_time(:second)

    case :ets.lookup(:ventas_dedupe, clave) do
      [{^clave, marca_tiempo}] when ahora - marca_tiempo < @ventana_dedupe_segundos ->
        true

      _ ->
        :ets.insert(:ventas_dedupe, {clave, ahora})
        false
    end
  end

  defp datos_visuales(stock_item, brand_id) do
    nombre_color = StockItem.nombre_color(stock_item.codigo_color)
    color_hex = Map.get(@mapa_colores_hex, nombre_color, "#cccccc")
    es_blanco = stock_item.codigo_color == "21"

    cond do
      stock_item.product.image ->
        %{tipo: :foto, valor: stock_item.product.image, color_hex: color_hex, es_blanco: es_blanco}

      true ->
        categoria =
          Repo.get_by(CategoriaCustom, codigo_tipo: stock_item.product.codigo_tipo, brand_id: brand_id)

        cond do
          categoria && categoria.imagen_url ->
            %{tipo: :foto, valor: categoria.imagen_url, color_hex: color_hex, es_blanco: es_blanco}

          true ->
            %{tipo: :icono, valor: icono_svg(categoria && categoria.icono), color_hex: color_hex, es_blanco: es_blanco}
        end
    end
  end

  defp icono_svg("remera"), do: ~s(<path d="M15 4l6 2v5h-3v8a1 1 0 0 1 -1 1h-10a1 1 0 0 1 -1 -1v-8h-3v-5l6 -2a3 3 0 0 0 6 0"/>)
  defp icono_svg("pantalon"), do: ~s(<path d="M6 3h12l1 6-2 12h-4l-1-9-1 9h-4l-2-12z"/>)
  defp icono_svg("buzo"), do: ~s(<path d="M15 4l6 3v5h-3v9a1 1 0 0 1 -1 1h-10a1 1 0 0 1 -1 -1v-9h-3v-5l6 -3a3 3 0 0 0 6 0"/>)
  defp icono_svg("campera"), do: ~s(<path d="M15 4l6 2v5h-3v8a1 1 0 0 1 -1 1h-10a1 1 0 0 1 -1 -1v-8h-3v-5l6 -2a3 3 0 0 0 6 0"/><path d="M9 7l3 3l3 -3"/><line x1="12" y1="10" x2="12" y2="20"/>)
  defp icono_svg("anteojos"), do: ~s(<circle cx="6.5" cy="12" r="3.5"/><circle cx="17.5" cy="12" r="3.5"/><line x1="10" y1="11" x2="14" y2="11"/><path d="M3 11l-1 1"/><path d="M21 11l1 1"/>)
  defp icono_svg("bolso"), do: ~s(<rect x="3" y="8" width="18" height="12" rx="2"/><path d="M8 8v-2a4 4 0 0 1 8 0v2"/>)
  defp icono_svg(_), do: ~s(<circle cx="12" cy="12" r="8"/>)

  defp procesar_codigo(socket, user_id, codigo9) do
    case Repo.get_by(StockItem, codigo: codigo9) do
      nil ->
        assign(socket, estado: :no_encontrado)

      stock_item ->
        stock_item = Repo.preload(stock_item, [:product])
        brand_id = stock_item.product && stock_item.product.brand_id

        cond do
          is_nil(brand_id) ->
            assign(socket, estado: :no_encontrado)

          not empleado_autorizado?(user_id, brand_id) ->
            assign(socket, estado: :no_autorizado)

          ya_procesado_hace_poco?(user_id, codigo9) ->
            aplicar_assigns_ok(socket, stock_item, brand_id, stock_item.cantidad, false, false)

          true ->
            cantidad_anterior = stock_item.cantidad
            ahora_venta = DateTime.utc_now()

            {grupo_venta_id, _reutiliza_grupo} =
              if socket.assigns[:grupo_venta_vence_en] &&
                   DateTime.compare(ahora_venta, socket.assigns.grupo_venta_vence_en) == :lt do
                {socket.assigns.grupo_venta_actual, true}
              else
                {Ecto.UUID.generate(), false}
              end

            {cantidad_final, ya_estaba_en_cero, venta_id} =
              if cantidad_anterior > 0 do
                {:ok, actualizado} =
                  stock_item
                  |> StockItem.changeset(%{cantidad: cantidad_anterior - 1})
                  |> Repo.update()

                DaleApp.Products.NotificacionesStock.revisar(%{
                  brand_id: brand_id,
                  user_id: user_id,
                  stock_item: stock_item,
                  cantidad_anterior: cantidad_anterior,
                  cantidad_nueva: actualizado.cantidad,
                  nombre_producto: stock_item.product.name,
                  product_id: stock_item.product.id
                })

                {:ok, venta} =
                  DaleApp.Products.registrar_venta(%{
                    brand_id: brand_id,
                    user_id: user_id,
                    product_id: stock_item.product.id,
                    stock_item_id: stock_item.id,
                    producto_nombre: stock_item.product.name,
                    codigo_tipo: stock_item.product.codigo_tipo,
                    codigo_color: stock_item.codigo_color,
                    codigo_talle: stock_item.codigo_talle,
                    precio_unitario: stock_item.product.price,
                    grupo_venta: grupo_venta_id
                  })

                {actualizado.cantidad, false, venta.id}
              else
                {cantidad_anterior, true, nil}
              end

            if not ya_estaba_en_cero do
              Process.send_after(self(), :tick_deshacer, 1000)
            end

            socket =
              if ya_estaba_en_cero do
                socket
              else
                assign(socket,
                  grupo_venta_actual: grupo_venta_id,
                  grupo_venta_vence_en: DateTime.add(ahora_venta, 10, :second)
                )
              end

            aplicar_assigns_ok(socket, stock_item, brand_id, cantidad_final, ya_estaba_en_cero, false)
            |> assign(venta_id: venta_id)
        end
    end
  end

  defp aplicar_assigns_ok(socket, stock_item, brand_id, cantidad, ya_estaba_en_cero, dedupe_sin_segundos) do
    visual = datos_visuales(stock_item, brand_id)

    assign(socket,
      estado: :ok,
      stock_item_id: stock_item.id,
      nombre_producto: stock_item.product.name,
      tipo_imagen: visual.tipo,
      imagen_valor: visual.valor,
      color_hex_producto: visual.color_hex,
      es_blanco_producto: visual.es_blanco,
      nombre_color: StockItem.nombre_color(stock_item.codigo_color),
      nombre_talle: StockItem.nombre_talle(stock_item.codigo_talle),
      cantidad: cantidad,
      ya_estaba_en_cero: ya_estaba_en_cero,
      deshecho: false,
      segundos_restantes: if(dedupe_sin_segundos or ya_estaba_en_cero, do: 0, else: @segundos_deshacer)
    )
  end

  defp empleado_autorizado?(user_id, brand_id) do
    case Repo.get(User, user_id) do
      nil ->
        false

      user ->
        es_cajero_de_esta_marca = user.role == "cajero" and user.cajero_brand_id == brand_id
        es_dueño_de_esta_marca = Repo.get_by(Brand, id: brand_id, user_id: user_id) != nil
        es_cajero_de_esta_marca or es_dueño_de_esta_marca
    end
  end

  def render(assigns) do
    ~H"""
    <div style="min-height: 100vh; background: #f6faf3; display: flex; align-items: center; justify-content: center; padding: 20px; font-family: 'Noto Sans', sans-serif;">
      <div style="background: white; border-radius: 24px; padding: 32px 24px; max-width: 340px; width: 100%; box-shadow: 0 8px 30px rgba(0,0,0,0.08); text-align: center;">

        <%= if @estado == :cargando do %>
          <p style="font-size: 13px; color: #999; margin: 0;">Cargando...</p>
        <% end %>

        <%= if @estado == :sin_sesion do %>
          <p style="font-size: 15px; color: #333; margin: 0 0 20px;">Necesitás iniciar sesión para usar el escáner de ventas.</p>
          <a href="/auth/google" style="display: inline-block; background: #186904; color: white; padding: 12px 24px; border-radius: 12px; text-decoration: none; font-weight: 700; font-size: 14px;">Iniciar sesión</a>
        <% end %>

        <%= if @estado == :esperando_escaneo do %>
          <p style="font-size: 13px; font-weight: 700; color: #186904; margin: 0 0 8px; text-transform: uppercase; letter-spacing: 1px;">Escáner de ventas</p>
          <p style="font-size: 13px; color: #999; margin: 0 0 20px;">Apuntá el lector de código de barras acá y escaneá</p>
          <form phx-submit="escanear_manual">
            <input type="text" name="codigo" autofocus autocomplete="off" placeholder="Esperando escaneo..." style="width: 100%; box-sizing: border-box; padding: 14px; border: 1.5px solid #cfe4cf; border-radius: 12px; font-size: 15px; text-align: center; outline: none;" />
          </form>
        <% end %>

        <%= if @estado == :no_encontrado do %>
          <p style="font-size: 15px; color: #c0392b; font-weight: 700; margin: 0 0 8px;">Código no encontrado</p>
          <p style="font-size: 13px; color: #999; margin: 0 0 20px;">No hay ningún producto con ese código.</p>
          <button phx-click="escanear_otro" style="background: #186904; color: white; border: none; padding: 12px 24px; border-radius: 12px; font-weight: 700; font-size: 14px; cursor: pointer;">Escanear otro</button>
        <% end %>

        <%= if @estado == :no_autorizado do %>
          <p style="font-size: 15px; color: #c0392b; font-weight: 700; margin: 0 0 8px;">No tenés acceso a esto</p>
          <p style="font-size: 13px; color: #999; margin: 0;">Tu usuario no está registrado como empleado de esta marca.</p>
        <% end %>

        <%= if @estado == :ok do %>
          <p style="font-size: 13px; font-weight: 700; color: #186904; margin: 0 0 8px; text-transform: uppercase; letter-spacing: 1px;">
            <%= if @ya_estaba_en_cero, do: "Aviso", else: "Venta registrada" %>
          </p>

          <%= if @tipo_imagen == :foto do %>
            <img src={@imagen_valor} style={"width: 100px; height: 100px; object-fit: cover; border-radius: 16px; margin: 0 auto 12px; display: block; border: 4px solid #{@color_hex_producto}; box-sizing: border-box;"} />
          <% else %>
            <div style={"width: 100px; height: 100px; border-radius: 16px; margin: 0 auto 12px; display: flex; align-items: center; justify-content: center; background: #{@color_hex_producto}; #{if @es_blanco_producto, do: "border: 1.5px solid #ddd;", else: ""}"}>
              <svg width="52" height="52" viewBox="0 0 24 24" fill="none" stroke={if @es_blanco_producto, do: "#333", else: "white"} stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
                {raw(@imagen_valor)}
              </svg>
            </div>
          <% end %>

          <p style="font-size: 17px; font-weight: 700; color: #111; margin: 0 0 4px;"><%= @nombre_producto %></p>
          <p style="font-size: 13px; color: #666; margin: 0 0 16px;"><%= @nombre_color %> · <%= @nombre_talle %></p>

          <%= if @ya_estaba_en_cero do %>
            <p style="font-size: 13px; color: #c0392b; margin: 0 0 20px;">Este producto ya estaba en 0 unidades. No se restó nada.</p>
          <% else %>
            <p style="font-size: 14px; color: #333; margin: 0 0 20px;">
              <%= if @deshecho do %>
                Deshecho. Quedan <strong><%= @cantidad %></strong> unidades.
              <% else %>
                -1 unidad. Quedan <strong><%= @cantidad %></strong> unidades.
              <% end %>
            </p>
          <% end %>

          <div style="display: flex; gap: 10px;">
            <%= if !@ya_estaba_en_cero && !@deshecho && @segundos_restantes > 0 do %>
              <button phx-click="deshacer" style="flex: 1; padding: 12px; border: 1.5px solid #c0392b; border-radius: 12px; background: white; color: #c0392b; cursor: pointer; font-size: 14px; font-weight: 700;">Deshacer (<%= @segundos_restantes %>s)</button>
            <% end %>
            <button phx-click="escanear_otro" style="flex: 1; padding: 12px; border: none; border-radius: 12px; background: #186904; color: white; cursor: pointer; font-size: 14px; font-weight: 700;">Escanear otro</button>
          </div>
        <% end %>

      </div>
    </div>
    """
  end
end
