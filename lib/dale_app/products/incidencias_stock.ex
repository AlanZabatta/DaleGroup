defmodule DaleApp.Products.IncidenciasStock do
  @moduledoc """
  Abre y resuelve incidencias de stock (agotado / talle_agotado / poco_stock)
  y calcula los puntos que le da al Gestor que las resuelve, segun:
  - 0 puntos si el que resuelve es quien creo el producto Y el producto tiene <= 14 dias
  - si no: 30 puntos si resuelve dentro de las primeras 24hs desde que aparecio
           20 puntos si resuelve entre 24 y 48hs
           10 puntos si resuelve despues de 48hs
  """
  import Ecto.Query
  alias DaleApp.Repo
  alias DaleApp.Products.{IncidenciaStock, Product}
  def abrir(brand_id, product_id, tipo, codigo_talle \\ nil, brand_location_id \\ nil) do
    ya_abierta =
      Repo.exists?(
        from(i in IncidenciaStock,
          where:
            i.product_id == ^product_id and i.tipo == ^tipo and i.resuelta == false and
              ((is_nil(^codigo_talle) and is_nil(i.codigo_talle)) or i.codigo_talle == ^codigo_talle)
        )
      )
    if not ya_abierta do
      producto = Repo.get(Product, product_id)
      if producto do
        %IncidenciaStock{}
        |> IncidenciaStock.changeset(%{
          brand_id: brand_id,
          product_id: product_id,
          codigo_talle: codigo_talle,
          tipo: tipo,
          creado_por_user_id: producto.creado_por_user_id,
          producto_creado_en: producto.inserted_at,
          fecha_apertura: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
          brand_location_id: brand_location_id
        })
        |> Repo.insert()
      end
    end
  end
  def resolver_abiertas(product_id, tipo, codigo_talle, resuelto_por_user_id) do
    base = from(i in IncidenciaStock, where: i.product_id == ^product_id and i.tipo == ^tipo and i.resuelta == false)
    query =
      if is_nil(codigo_talle) do
        from(i in base, where: is_nil(i.codigo_talle))
      else
        from(i in base, where: i.codigo_talle == ^codigo_talle)
      end
    Repo.all(query)
    |> Enum.each(fn incidencia -> resolver(incidencia, resuelto_por_user_id) end)
  end
  def resolver_todas_de_producto(product_id, resuelto_por_user_id) do
    Repo.all(from(i in IncidenciaStock, where: i.product_id == ^product_id and i.resuelta == false))
    |> Enum.each(fn incidencia -> resolver(incidencia, resuelto_por_user_id) end)
  end
  defp resolver(incidencia, resuelto_por_user_id) do
    ahora = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    puntos = calcular_puntos(incidencia, resuelto_por_user_id, ahora)
    incidencia
    |> IncidenciaStock.changeset(%{
      resuelta: true,
      resuelto_por_user_id: resuelto_por_user_id,
      fecha_resolucion: ahora,
      puntos_otorgados: puntos
    })
    |> Repo.update()
  end
  defp calcular_puntos(incidencia, resuelto_por_user_id, ahora) do
    dias_desde_creacion_producto =
      if incidencia.producto_creado_en do
        div(NaiveDateTime.diff(ahora, incidencia.producto_creado_en, :second), 86400)
      else
        999
      end
    propio_reciente =
      incidencia.creado_por_user_id == resuelto_por_user_id and dias_desde_creacion_producto <= 14
    if propio_reciente do
      0
    else
      horas_desde_apertura = NaiveDateTime.diff(ahora, incidencia.fecha_apertura, :second) / 3600
      cond do
        horas_desde_apertura <= 24 -> 30
        horas_desde_apertura <= 48 -> 20
        true -> 10
      end
    end
  end
end
