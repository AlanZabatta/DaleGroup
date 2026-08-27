defmodule DaleApp.Products.SaldoPuntos do
  @moduledoc """
  Saldo real de un empleado, por categoria, leyendo de movimientos_puntos en
  vez de recalcular sobre una ventana de 90 dias.

  Es lo que reemplaza a Puntos.saldo_del_usuario/2: aquella funcion
  recalculaba desde ventas y stock cada vez (y los puntos se evaporaban
  pasados los 90 dias). Esta suma lo generado (movimientos_puntos) menos lo
  gastado (canjes, siguiendo la categoria del PREMIO comprado, no del rol
  del usuario — asi un empleado multitask tiene sus dos saldos correctos).
  """
  import Ecto.Query
  alias DaleApp.Repo
  alias DaleApp.Products.{MovimientoPuntos, Canje}

  @doc "Saldo de un usuario en una categoria puntual: generado - gastado."
  def saldo(brand_id, user_id, categoria) do
    generado(brand_id, user_id, categoria) - gastado(brand_id, user_id, categoria)
  end

  @doc "Los dos saldos de un usuario a la vez: %{\"ventas\" => n, \"gestores\" => n}"
  def saldos(brand_id, user_id) do
    %{
      "ventas" => saldo(brand_id, user_id, "ventas"),
      "gestores" => saldo(brand_id, user_id, "gestores")
    }
  end

  @doc "Saldo de TODOS los empleados de una marca en una categoria, para listas y rankings."
  def saldos_por_usuario(brand_id, categoria) do
    generados = generado_por_usuario(brand_id, categoria)
    gastados = gastado_por_usuario(brand_id, categoria)

    generados
    |> Map.keys()
    |> Kernel.++(Map.keys(gastados))
    |> Enum.uniq()
    |> Map.new(fn user_id ->
      {user_id, Map.get(generados, user_id, 0) - Map.get(gastados, user_id, 0)}
    end)
  end

  defp generado(brand_id, user_id, categoria) do
    from(m in MovimientoPuntos,
      where: m.brand_id == ^brand_id and m.user_id == ^user_id and m.categoria == ^categoria,
      select: sum(m.puntos_finales)
    )
    |> Repo.one()
    |> or_zero()
  end

  defp gastado(brand_id, user_id, categoria) do
    from(c in Canje,
      join: p in assoc(c, :premio),
      where: c.brand_id == ^brand_id and c.user_id == ^user_id and c.es_dueño == false and p.categoria == ^categoria,
      select: sum(c.puntos_costo)
    )
    |> Repo.one()
    |> or_zero()
  end

  defp generado_por_usuario(brand_id, categoria) do
    from(m in MovimientoPuntos,
      where: m.brand_id == ^brand_id and m.categoria == ^categoria,
      group_by: m.user_id,
      select: {m.user_id, sum(m.puntos_finales)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp gastado_por_usuario(brand_id, categoria) do
    from(c in Canje,
      join: p in assoc(c, :premio),
      where: c.brand_id == ^brand_id and c.es_dueño == false and p.categoria == ^categoria,
      group_by: c.user_id,
      select: {c.user_id, sum(c.puntos_costo)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp or_zero(nil), do: 0
  defp or_zero(n), do: n
end
