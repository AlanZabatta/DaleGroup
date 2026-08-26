defmodule DaleApp.Products.NotificacionesStock do
  import Ecto.Query
  alias DaleApp.Repo
  alias DaleApp.Accounts
  alias DaleApp.Brands.Brand
  alias DaleApp.Products.StockItem
  alias DaleApp.Products.IncidenciasStock

  # attrs: %{brand_id: id, user_id: id, stock_item: %StockItem{}, cantidad_anterior: integer,
  #          cantidad_nueva: integer, nombre_producto: string, product_id: id}
  def revisar(attrs) do
    brand = Repo.get(Brand, attrs.brand_id)

    total_nuevo = total_stock_producto(attrs.product_id)
    total_anterior = total_nuevo - attrs.cantidad_nueva + attrs.cantidad_anterior

    revisar_incidencias(brand, attrs, total_anterior, total_nuevo)

    if brand && brand.notificaciones_stock_activas do
      mensajes =
        []
        |> concat_si(regla_talle_agotado(attrs))
        |> concat_si(regla_producto_agotado(attrs, total_anterior, total_nuevo))
        |> concat_si(regla_poco_stock(brand, attrs, total_anterior, total_nuevo))

      Enum.each(mensajes, fn mensaje -> enviar(brand, mensaje) end)
    end
  end

  defp revisar_incidencias(nil, _attrs, _total_anterior, _total_nuevo), do: :ok

  defp revisar_incidencias(brand, attrs, total_anterior, total_nuevo) do
    ca = attrs.cantidad_anterior
    cn = attrs.cantidad_nueva

    if cn == 0 and ca > 0 do
      IncidenciasStock.abrir(attrs.brand_id, attrs.product_id, "talle_agotado", attrs.stock_item.codigo_talle, attrs.stock_item.brand_location_id)
    end

    if total_nuevo == 0 and total_anterior > 0 do
      IncidenciasStock.abrir(attrs.brand_id, attrs.product_id, "agotado", nil, attrs.stock_item.brand_location_id)
    end

    if total_nuevo > 0 and total_nuevo <= brand.umbral_poco_stock and total_anterior > brand.umbral_poco_stock do
      IncidenciasStock.abrir(attrs.brand_id, attrs.product_id, "poco_stock", nil, attrs.stock_item.brand_location_id)
    end

    if cn > 0 do
      IncidenciasStock.resolver_abiertas(attrs.product_id, "talle_agotado", attrs.stock_item.codigo_talle, attrs.user_id)
    end

    if total_nuevo > 0 do
      IncidenciasStock.resolver_abiertas(attrs.product_id, "agotado", nil, attrs.user_id)
    end

    if total_nuevo > brand.umbral_poco_stock do
      IncidenciasStock.resolver_abiertas(attrs.product_id, "poco_stock", nil, attrs.user_id)
    end
  end

  defp concat_si(lista, nil), do: lista
  defp concat_si(lista, mensaje), do: lista ++ [mensaje]

  defp total_stock_producto(product_id) do
    Repo.aggregate(from(s in StockItem, where: s.product_id == ^product_id), :sum, :cantidad) || 0
  end

  # --- Regla 1: un talle específico se agotó ---
  defp regla_talle_agotado(%{cantidad_anterior: ca, cantidad_nueva: cn, stock_item: item, nombre_producto: nombre})
       when ca > 0 and cn == 0 do
    "El talle #{StockItem.nombre_talle(item.codigo_talle)} de \"#{nombre}\" se agotó"
  end

  defp regla_talle_agotado(_attrs), do: nil

  # --- Regla 2: el producto se quedó sin stock en ningún talle ---
  defp regla_producto_agotado(%{nombre_producto: nombre}, total_anterior, 0) when total_anterior > 0 do
    "\"#{nombre}\" se quedó sin stock en ningún talle"
  end

  defp regla_producto_agotado(_attrs, _total_anterior, _total_nuevo), do: nil

  # --- Regla 3: el producto cruzó a "poco stock" ---
  defp regla_poco_stock(brand, %{nombre_producto: nombre}, total_anterior, total_nuevo) when total_nuevo > 0 do
    umbral = brand.umbral_poco_stock

    if total_anterior > umbral and total_nuevo <= umbral do
      "\"#{nombre}\" llegó a poco stock (quedan #{total_nuevo} unidades)"
    else
      nil
    end
  end

  defp regla_poco_stock(_brand, _attrs, _total_anterior, _total_nuevo), do: nil

  # Se llama al entrar a Stock Inteligente. items viene de Products.stock_sin_movimiento/3
  def revisar_rotacion(brand, items_sin_movimiento) do
    if brand && brand.notificaciones_stock_activas do
      Enum.each(items_sin_movimiento, fn item ->
        if not DaleApp.Products.alerta_rotacion_reciente?(item.producto.id, item.codigo_talle) do
          mensaje =
            "\"#{item.producto.name}\" (talle #{StockItem.nombre_talle(item.codigo_talle)}) lleva #{item.dias} días sin venderse"

          enviar(brand, mensaje)
          DaleApp.Products.registrar_alerta_rotacion(brand.id, item.producto.id, item.codigo_talle)
        end
      end)
    end
  end

  # --- Envío real ---
  defp enviar(brand, mensaje) do
    suscripciones = Accounts.listar_push_subscriptions(brand.user_id)

    Enum.each(suscripciones, fn sub ->
      if sub.endpoint && sub.p256dh && sub.auth do
        try do
          subscription_json =
            Jason.encode!(%{endpoint: sub.endpoint, keys: %{p256dh: sub.p256dh, auth: sub.auth}})

          payload = Jason.encode!(%{titulo: "Alerta de stock", cuerpo: mensaje, url: "/mi-tienda/stock"})

          WebPushElixir.send_notification(subscription_json, payload)
        rescue
          _ -> :ok
        end
      end
    end)
  end
end
