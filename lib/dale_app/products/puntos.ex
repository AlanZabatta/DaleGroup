defmodule DaleApp.Products.Puntos do
  @moduledoc """
  Reglas base de puntos por venta.

  El sistema de tipo de cambio y saldos por categoria que vivia aca antes
  quedo reemplazado por movimientos_puntos + RegistroPuntos + SaldoPuntos:
  monedas separadas sin conversion (ver esos modulos). Lo que queda aca es
  solo el calculo puro de cuantos puntos vale una venta, el tope diario
  sobre eso, y el armado de ciclos de 30 dias que usa EmpleadoDelMes.
  """

  @tope_diario_ventas 200
  @dias_ciclo 30

  @doc "Valor del tope diario de ventas chicas. Publico para que otros modulos lo usen sin duplicar el numero."
  def tope_diario_ventas, do: @tope_diario_ventas

  @doc """
  Puntos crudos que vale una venta segun su cantidad de items: 10 pts por
  item, con un multiplicador por combo (1 item x1, 2 items x1.5, 3 items
  x2, 4+ items x3).
  """
  def puntos_venta(cantidad_items) do
    multiplicador =
      cond do
        cantidad_items <= 1 -> 1.0
        cantidad_items == 2 -> 1.5
        cantidad_items == 3 -> 2.0
        true -> 3.0
      end

    round(10 * cantidad_items * multiplicador)
  end

  @doc """
  Tope diario suave: ventas de 1-2 ítems cuentan completo hasta que el
  acumulado del día llega a #{@tope_diario_ventas}; después, mitad.
  Combos de 3+ ítems SIEMPRE cuentan completo.
  """
  def aplicar_tope_diario_ventas(cantidades_items_del_dia) do
    {_acumulado_chicas, total} =
      Enum.reduce(cantidades_items_del_dia, {0, 0}, fn cantidad_items, {acumulado_chicas, total} ->
        base = puntos_venta(cantidad_items)

        if cantidad_items >= 3 do
          {acumulado_chicas, total + base}
        else
          if acumulado_chicas >= @tope_diario_ventas do
            {acumulado_chicas, total + div(base, 2)}
          else
            {acumulado_chicas + base, total + base}
          end
        end
      end)

    total
  end

  @doc "Ciclos de 30 dias desde una fecha de activacion hasta ahora, el ultimo puede estar en curso."
  def ciclos_desde(activada_en, ahora \\ DateTime.utc_now()) do
    dias_transcurridos = DateTime.diff(ahora, activada_en, :day)
    cantidad_ciclos = div(dias_transcurridos, @dias_ciclo) + 1

    for i <- 0..(cantidad_ciclos - 1) do
      inicio = DateTime.add(activada_en, i * @dias_ciclo * 86400, :second) |> DateTime.to_date()
      fin = Date.add(inicio, @dias_ciclo)
      {inicio, fin}
    end
  end

  @doc "Filtra ciclos_desde/2 a solo los que ya terminaron (fin <= hoy)."
  def ciclos_cerrados(ciclos, hoy \\ Date.utc_today()) do
    Enum.filter(ciclos, fn {_inicio, fin} -> Date.compare(fin, hoy) != :gt end)
  end
end
