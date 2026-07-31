defmodule DaleAppWeb.StockLive do
  use DaleAppWeb, :live_view
  import Ecto.Query, only: [from: 2]
  alias DaleApp.Repo
  alias DaleApp.Products.{Product, StockItem, Dale9}

  def mount(%{"id" => producto_id}, session, socket) do
    user_id = session["user_id"]
    producto = Repo.get(Product, producto_id)
    brand = if producto, do: DaleApp.Repo.get(DaleApp.Brands.Brand, producto.brand_id), else: nil
    autorizado = brand && brand.user_id == user_id

    socket =
      if autorizado do
        socket
        |> assign(producto: producto, brand: brand, tipos: StockItem.tipos(), colores: StockItem.colores(), talles: StockItem.talles())
        |> assign(color_nuevo: nil, talle_nuevo: nil, cantidad_nueva: 0)
        |> cargar_stock()
      else
        assign(socket, producto: nil, brand: nil)
      end

    {:ok, socket}
  end

  def handle_event("elegir_tipo", %{"tipo" => codigo_tipo}, socket) do
    producto = socket.assigns.producto
    numero = Dale9.proximo_numero(producto.brand_id, codigo_tipo)

    {:ok, producto_actualizado} =
      producto
      |> Ecto.Changeset.change(%{codigo_tipo: codigo_tipo, codigo_numero: numero})
      |> Repo.update()

    {:noreply, assign(socket, producto: producto_actualizado)}
  end

  def handle_event("seleccionar_color", %{"color" => color}, socket) do
    {:noreply, assign(socket, color_nuevo: color)}
  end

  def handle_event("seleccionar_talle", %{"talle" => talle}, socket) do
    {:noreply, assign(socket, talle_nuevo: talle)}
  end

  def handle_event("agregar_variante", %{"cantidad" => cantidad_str}, socket) do
    %{producto: producto, color_nuevo: color, talle_nuevo: talle} = socket.assigns
    cantidad = (Integer.parse(cantidad_str) |> elem(0)) || 0

    if producto.codigo_tipo && color && talle do
      codigo = StockItem.armar_codigo(producto.codigo_tipo, color, producto.codigo_numero, talle)

      %StockItem{}
      |> StockItem.changeset(%{
        codigo: codigo,
        cantidad: cantidad,
        codigo_color: color,
        codigo_talle: talle,
        product_id: producto.id
      })
      |> Repo.insert()

      {:noreply, socket |> assign(color_nuevo: nil, talle_nuevo: nil) |> cargar_stock()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cambiar_cantidad", %{"id" => id, "cantidad" => cantidad_str}, socket) do
    cantidad = (Integer.parse(cantidad_str) |> elem(0)) || 0
    item = Repo.get(StockItem, id)

    if item && item.product_id == socket.assigns.producto.id do
      item |> StockItem.changeset(%{cantidad: max(cantidad, 0)}) |> Repo.update()
    end

    {:noreply, cargar_stock(socket)}
  end

  def handle_event("borrar_variante", %{"id" => id}, socket) do
    item = Repo.get(StockItem, id)

    if item && item.product_id == socket.assigns.producto.id do
      Repo.delete(item)
    end

    {:noreply, cargar_stock(socket)}
  end

  defp cargar_stock(socket) do
    items =
      from(s in StockItem, where: s.product_id == ^socket.assigns.producto.id, order_by: [asc: s.codigo])
      |> Repo.all()

    total = Enum.reduce(items, 0, fn i, acc -> acc + i.cantidad end)

    assign(socket, stock_items: items, total_stock: total)
  end

  def render(assigns) do
    ~H"""
    <div style="padding: 24px 18px 40px; font-family: Poppins, sans-serif; max-width: 600px; margin: 0 auto; background-color: white; min-height: 100vh;">
      <a href="/mi-tienda/productos" style="display: inline-flex; background: none; border: none; color: #186904; font-size: 22px; font-weight: 700; cursor: pointer; line-height: 1; text-decoration: none; margin-bottom: 16px;">&#x2715;</a>

      <%= if is_nil(@producto) do %>
        <p style="color: #999; font-family: Poppins, sans-serif; font-size: 14px; text-align: center; padding: 40px 0;">No encontrado.</p>
      <% else %>
        <p style="font-size: 22px; font-weight: 800; color: #186904; margin: 0 0 4px;">Stock</p>
        <p style="font-size: 13px; color: #999; margin: 0 0 20px;"><%= @producto.name %></p>

        <%= if is_nil(@producto.codigo_tipo) do %>
          <div style="background: #f7f5ef; border-radius: 18px; padding: 18px; margin-bottom: 20px;">
            <p style="font-size: 13px; font-weight: 700; color: #186904; margin: 0 0 12px;">¿Qué tipo de prenda es?</p>
            <div style="display: flex; flex-wrap: wrap; gap: 8px;">
              <%= for {codigo, nombre} <- Enum.sort_by(@tipos, fn {c, _} -> c end) do %>
                <button type="button" phx-click="elegir_tipo" phx-value-tipo={codigo} style="padding: 9px 14px; border-radius: 20px; border: 1.5px solid #e0e0e0; background: white; color: #333; cursor: pointer; font-size: 13px; font-weight: 600; font-family: Poppins, sans-serif;">
                  <%= nombre %>
                </button>
              <% end %>
            </div>
          </div>
        <% else %>
          <div style="background: white; border: 1.5px solid #f0f0f0; border-radius: 18px; padding: 16px; margin-bottom: 16px; box-shadow: 0 3px 12px rgba(0,0,0,0.06);">
            <p style="font-size: 11px; color: #999; margin: 0 0 4px; text-transform: uppercase; letter-spacing: 1px; font-weight: 700;">Código base (DALE9)</p>
            <p style="font-size: 18px; font-weight: 800; color: #186904; margin: 0; letter-spacing: 2px;"><%= @producto.codigo_tipo %><%= @producto.codigo_numero %> <span style="color:#ccc; font-weight:400;">+ color + talle</span></p>
            <p style="font-size: 12px; color: #666; margin: 6px 0 0;">Tipo: <%= StockItem.nombre_tipo(@producto.codigo_tipo) %></p>
          </div>

          <div style="background: white; border: 1.5px solid #f0f0f0; border-radius: 18px; padding: 16px; margin-bottom: 20px; box-shadow: 0 3px 12px rgba(0,0,0,0.06);">
            <p style="font-size: 13px; font-weight: 700; color: #186904; margin: 0 0 12px;">Agregar variante</p>

            <p style="font-size: 11px; color: #888; margin: 0 0 6px; font-weight: 600;">Color</p>
            <div style="display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 12px;">
              <%= for {codigo, nombre} <- Enum.sort_by(@colores, fn {c, _} -> c end) do %>
                <button type="button" phx-click="seleccionar_color" phx-value-color={codigo} style={"padding: 6px 12px; border-radius: 16px; border: 1.5px solid #{if @color_nuevo == codigo, do: "#186904", else: "#e0e0e0"}; background: #{if @color_nuevo == codigo, do: "#186904", else: "white"}; color: #{if @color_nuevo == codigo, do: "white", else: "#555"}; cursor: pointer; font-size: 12px; font-weight: 600; font-family: Poppins, sans-serif;"}>
                  <%= nombre %>
                </button>
              <% end %>
            </div>

            <p style="font-size: 11px; color: #888; margin: 0 0 6px; font-weight: 600;">Talle</p>
            <div style="display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 14px;">
              <%= for {codigo, nombre} <- Enum.sort_by(@talles, fn {c, _} -> c end) do %>
                <button type="button" phx-click="seleccionar_talle" phx-value-talle={codigo} style={"padding: 6px 12px; border-radius: 16px; border: 1.5px solid #{if @talle_nuevo == codigo, do: "#186904", else: "#e0e0e0"}; background: #{if @talle_nuevo == codigo, do: "#186904", else: "white"}; color: #{if @talle_nuevo == codigo, do: "white", else: "#555"}; cursor: pointer; font-size: 12px; font-weight: 600; font-family: Poppins, sans-serif;"}>
                  <%= nombre %>
                </button>
              <% end %>
            </div>

            <%= if @color_nuevo && @talle_nuevo do %>
              <form phx-submit="agregar_variante" style="display: flex; gap: 8px;">
                <input type="number" name="cantidad" min="0" placeholder="Cantidad" style="flex: 1; padding: 10px 12px; border: 1.5px solid #e0e0e0; border-radius: 12px; font-family: Poppins, sans-serif; font-size: 13px; outline: none;" />
                <button type="submit" style="background: #186904; color: white; border: none; border-radius: 12px; padding: 10px 18px; font-size: 13px; font-weight: 700; font-family: Poppins, sans-serif; cursor: pointer;">Agregar</button>
              </form>
            <% end %>
          </div>

          <p style="font-size: 13px; font-weight: 700; color: #333; margin: 0 0 12px;">Variantes cargadas (<%= @total_stock %> unidades en total)</p>

          <%= if Enum.empty?(@stock_items) do %>
            <p style="font-size: 12.5px; color: #bbb; text-align: center; padding: 20px 0;">Todavía no cargaste ninguna variante.</p>
          <% else %>
            <div style="display: flex; flex-direction: column; gap: 8px;">
              <%= for item <- @stock_items do %>
                <div style="display: flex; align-items: center; gap: 10px; padding: 10px 12px; background: #f9f9f9; border-radius: 12px;">
                  <div style="flex: 1;">
                    <p style="font-size: 12.5px; font-weight: 700; color: #333; margin: 0;"><%= StockItem.nombre_color(item.codigo_color) %> · <%= StockItem.nombre_talle(item.codigo_talle) %></p>
                    <p style="font-size: 10px; color: #aaa; margin: 2px 0 0; letter-spacing: 1px;"><%= item.codigo %></p>
                  </div>
                  <form phx-change="cambiar_cantidad">
                    <input type="hidden" name="id" value={item.id} />
                    <input type="number" name="cantidad" value={item.cantidad} min="0" style="width: 56px; padding: 6px; border: 1.5px solid #e0e0e0; border-radius: 8px; text-align: center; font-family: Poppins, sans-serif; font-size: 13px; outline: none;" />
                  </form>
                  <button type="button" phx-click="borrar_variante" phx-value-id={item.id} style="background: none; border: none; color: #c0392b; font-size: 16px; cursor: pointer;">✕</button>
                </div>
              <% end %>
            </div>
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end
end
