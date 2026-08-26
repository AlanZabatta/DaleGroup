defmodule DaleAppWeb.GestionarProductosLive do
  use DaleAppWeb, :live_view
  import Ecto.Query
  alias DaleApp.Repo
  alias DaleApp.Products
  alias DaleApp.Brands.Brand

  def mount(_params, session, socket) do
    user_id = session["user_id"]
    brand = if user_id, do: Repo.get_by(Brand, user_id: user_id), else: nil
    productos = if brand, do: cargar_productos(brand.id), else: []

    {:ok,
     assign(socket,
       brand: brand,
       productos: productos,
       user_id: user_id,
       mostrar_confirmar_borrar: false,
       producto_a_borrar: nil
     )}
  end

  defp cargar_productos(brand_id) do
    Products.list_brand_products(brand_id)
    |> Enum.filter(&(&1.active and &1.image))
  end

  def handle_event("pedir_borrar", %{"id" => id}, socket) do
    {:noreply, assign(socket, mostrar_confirmar_borrar: true, producto_a_borrar: String.to_integer(id))}
  end

  def handle_event("cancelar_borrar", _params, socket) do
    {:noreply, assign(socket, mostrar_confirmar_borrar: false, producto_a_borrar: nil)}
  end

  def handle_event("confirmar_borrar", _params, socket) do
    id = socket.assigns.producto_a_borrar
    user_id = socket.assigns.user_id
    product = Products.get_product(id)
    brand = socket.assigns.brand

    if product && brand && product.brand_id == brand.id do
      borrar_producto(product, user_id)
      productos = cargar_productos(brand.id)

      {:noreply,
       assign(socket,
         productos: productos,
         mostrar_confirmar_borrar: false,
         producto_a_borrar: nil
       )}
    else
      {:noreply, assign(socket, mostrar_confirmar_borrar: false, producto_a_borrar: nil)}
    end
  end

  defp borrar_producto(product, user_id) do
    imagenes_a_borrar = (product.images || []) ++ (if product.image, do: [product.image], else: [])

    imagenes_a_borrar
    |> Enum.uniq()
    |> Enum.each(fn url ->
      case extraer_public_id(url) do
        nil -> :ok
        public_id -> DaleApp.Storage.delete_image(public_id)
      end
    end)

    DaleApp.Products.IncidenciasStock.resolver_todas_de_producto(product.id, user_id)

    if creado_hoy?(product.inserted_at) do
      Repo.delete_all(
        from(m in DaleApp.Products.MovimientoStock,
          where: m.producto_id == ^product.id and m.tipo_accion == "creado"
        )
      )
    end

    if product.codigo_tipo && product.codigo_numero do
      DaleApp.Products.Dale9.liberar_numero(product.brand_id, product.codigo_tipo, product.codigo_numero)
    end

    Products.delete_product(product)
  end

  defp creado_hoy?(inserted_at) do
    ahora_ar = NaiveDateTime.add(NaiveDateTime.utc_now(), -3 * 3600, :second)
    creado_ar = NaiveDateTime.add(inserted_at, -3 * 3600, :second)
    NaiveDateTime.to_date(ahora_ar) == NaiveDateTime.to_date(creado_ar)
  end

  defp extraer_public_id(url) when is_binary(url) do
    case Regex.run(~r{/upload/(?:v\d+/)?(.+)\.[a-zA-Z0-9]+(?:\?.*)?$}, url) do
      [_, public_id] -> public_id
      _ -> nil
    end
  end

  defp extraer_public_id(_), do: nil

  defp url_editar_producto(producto) do
    if producto.codigo_tipo do
      "/mi-tienda/stock?categoria=#{producto.codigo_tipo}&form=editar&articulo=#{URI.encode(producto.name)}&origen=productos_dale"
    else
      nil
    end
  end

  def render(assigns) do
    ~H"""
    <div style="max-width: 480px; margin: 0 auto; padding: 24px 16px; font-family: 'Noto Sans', sans-serif; background: white; min-height: 100vh;">
      <.link navigate="/mi-tienda" style="display: inline-flex; background: none; border: none; color: #186904; font-size: 22px; font-weight: 700; cursor: pointer; line-height: 1; text-decoration: none; margin-bottom: 16px;">&#x2715;</.link>
      <h1 style="font-size: 22px; font-weight: bold; color: #186904; margin: 16px 0 24px;">Mis Productos</h1>

      <a href="/mi-tienda/stock?categoria=99&form=crear" style="width: 100%; display: flex; align-items: center; gap: 12px; padding: 16px; border: 1.5px solid #186904; border-radius: 16px; background: white; cursor: pointer; font-size: 15px; font-weight: 600; color: #186904; margin-bottom: 24px; text-decoration: none; box-sizing: border-box;">
        <span style="font-size: 28px; line-height: 1; font-weight: 300;">+</span>
        Agregar nuevo producto
      </a>

      <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 12px;">
        <%= for producto <- @productos do %>
          <% url_editar = url_editar_producto(producto) %>
          <div style="border-radius: 16px; overflow: hidden; border: 1px solid #f2f2f2; position: relative; box-shadow: 0 3px 10px rgba(0,0,0,0.06);">
            <button type="button" phx-click="pedir_borrar" phx-value-id={producto.id} style="position: absolute; top: 6px; right: 6px; z-index: 10; background: rgba(255,255,255,0.95); border: none; border-radius: 50%; width: 34px; height: 34px; cursor: pointer; display: flex; align-items: center; justify-content: center; box-shadow: 0 2px 6px rgba(0,0,0,0.12);">
              <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <polyline points="3 6 5 6 21 6"/>
                <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>
                <line x1="10" y1="11" x2="10" y2="17"/>
                <line x1="14" y1="11" x2="14" y2="17"/>
              </svg>
            </button>
            <%= if url_editar do %>
              <.link navigate={url_editar} style="display: block; text-decoration: none; color: inherit;">
                <div style="aspect-ratio: 3/4; background: #f0f0f0; overflow: hidden;">
                  <img src={producto.image} style="width: 100%; height: 100%; object-fit: cover;"/>
                </div>
                <div style="background: white; padding: 8px 10px;">
                  <p style="font-size: 12px; font-weight: 500; margin: 0; color: #111;"><%= producto.name %></p>
                  <p style="font-size: 11px; color: #999; margin: 2px 0 0; text-decoration: line-through;">$<%= producto.original_price %></p>
                  <p style="font-size: 13px; font-weight: 600; color: #186904; margin: 0;">$<%= producto.price %></p>
                  <p style="font-size: 11px; color: #888; margin: 2px 0 0;"><%= @brand.name %></p>
                </div>
              </.link>
            <% else %>
              <div style="aspect-ratio: 3/4; background: #f0f0f0; overflow: hidden;">
                <img src={producto.image} style="width: 100%; height: 100%; object-fit: cover;"/>
              </div>
              <div style="background: white; padding: 8px 10px;">
                <p style="font-size: 12px; font-weight: 500; margin: 0; color: #111;"><%= producto.name %></p>
                <p style="font-size: 11px; color: #999; margin: 2px 0 0; text-decoration: line-through;">$<%= producto.original_price %></p>
                <p style="font-size: 13px; font-weight: 600; color: #186904; margin: 0;">$<%= producto.price %></p>
                <p style="font-size: 11px; color: #888; margin: 2px 0 0;"><%= @brand.name %></p>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <%= if @mostrar_confirmar_borrar do %>
        <div style="display:flex; position:fixed; inset:0; z-index:9998; background:rgba(0,0,0,0.4); align-items:center; justify-content:center;">
          <div style="background:white; border-radius:12px; padding:24px; max-width:300px; width:90%; text-align:center;">
            <p style="font-family:'Noto Sans',sans-serif; font-size:13px; font-weight:700; color:#186904; margin:0 0 8px; text-transform:uppercase; letter-spacing:1px;">Aviso</p>
            <p style="font-family:'Noto Sans',sans-serif; font-size:14px; color:#111; margin:0 0 20px;">¿Borrar este producto?</p>
            <div style="display:flex; gap:10px;">
              <button type="button" phx-click="cancelar_borrar" style="flex:1; padding:10px; border:1.5px solid #ddd; border-radius:8px; background:white; cursor:pointer; font-size:14px;">Cancelar</button>
              <button type="button" phx-click="confirmar_borrar" style="flex:1; padding:10px; border:none; border-radius:8px; background:#c0392b; color:white; cursor:pointer; font-size:14px; font-weight:600;">Borrar</button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
