defmodule DaleApp.Products.ReferenciaPrecios do
  @moduledoc """
  Le dice al dueno cuanto cuesta un premio en TIEMPO, no en puntos.

  El problema que resuelve: nadie sabe si 3000 puntos es mucho o poco. Depende
  del ritmo de ese local, que el dueno no tiene por que calcular. Este modulo
  mira lo que realmente genero cada categoria y traduce: "un premio de 3000
  se alcanza en unos 45 dias".

  Usa la MEDIANA, no el promedio: si un vendedor estrella genera el triple que
  el resto, el promedio deja precios que solo el puede pagar. La mediana
  representa al empleado tipico.
  """
  import Ecto.Query
  alias DaleApp.Repo
  alias DaleApp.Products.MovimientoPuntos

  @ventana_dias 30
  @minimo_dias_para_datos_reales 30

  # Ritmos supuestos mientras la marca no tenga historial. Salen de las reglas
  # base con un local de actividad modesta: un vendedor con 4 ventas de 2 items
  # por dia (30 pts c/u), un gestor cargando 8 items por dia (10 pts c/u).
  @estimado_ventas_por_dia 120
  @estimado_gestores_por_dia 80

  @doc """
  Devuelve los tres horizontes para una categoria:

      %{
        por_dia: 140,
        dias_30: 4200, dias_60: 8400, dias_90: 12600,
        estimado?: false
      }

  `estimado?: true` significa que todavia no hay datos reales y los numeros
  salen de un supuesto — hay que avisarselo al dueno en pantalla.
  """
  def horizontes(brand, categoria) do
    case ritmo_diario(brand, categoria) do
      {:real, por_dia} -> armar(por_dia, false)
      {:estimado, por_dia} -> armar(por_dia, true)
    end
  end

  @doc "Dias que tarda el empleado tipico de esa categoria en llegar a `puntos`."
  def dias_para(brand, categoria, puntos) when is_integer(puntos) and puntos > 0 do
    {_origen, por_dia} = ritmo_diario(brand, categoria)
    if por_dia > 0, do: round(puntos / por_dia), else: nil
  end

  def dias_para(_brand, _categoria, _puntos), do: nil

  defp armar(por_dia, estimado?) do
    %{
      por_dia: round(por_dia),
      dias_30: round(por_dia * 30),
      dias_60: round(por_dia * 60),
      dias_90: round(por_dia * 90),
      estimado?: estimado?
    }
  end

  defp ritmo_diario(brand, categoria) do
    desde = Date.add(Date.utc_today(), -@ventana_dias)

    totales =
      from(m in MovimientoPuntos,
        where: m.brand_id == ^brand.id and m.categoria == ^categoria and m.fecha >= ^desde,
        group_by: m.user_id,
        select: sum(m.puntos_finales)
      )
      |> Repo.all()
      |> Enum.reject(&is_nil/1)

    dias_activa = dias_desde_activacion(brand)

    cond do
      totales == [] or dias_activa < @minimo_dias_para_datos_reales ->
        {:estimado, estimado_de(categoria)}

      true ->
        {:real, mediana(totales) / @ventana_dias}
    end
  end

  defp estimado_de("gestores"), do: @estimado_gestores_por_dia
  defp estimado_de(_), do: @estimado_ventas_por_dia

  defp dias_desde_activacion(%{empleado_puntos_activada_en: nil}), do: 0

  defp dias_desde_activacion(%{empleado_puntos_activada_en: fecha}),
    do: DateTime.diff(DateTime.utc_now(), fecha, :day)

  defp dias_desde_activacion(_), do: 0

  defp mediana(lista) do
    ordenada = Enum.sort(lista)
    n = length(ordenada)
    medio = div(n, 2)

    if rem(n, 2) == 1 do
      Enum.at(ordenada, medio)
    else
      (Enum.at(ordenada, medio - 1) + Enum.at(ordenada, medio)) / 2
    end
  end
end
