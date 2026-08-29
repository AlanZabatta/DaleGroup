defmodule DaleApp.Products.EmpleadoDelMes do
  @moduledoc """
  Empleado del mes: dos podios corren cada ciclo de 30 dias.

  1. El podio de la CATEGORIA de cada empleado (ventas, gestores o
     multitask) — mide el trabajo especifico de su rol.
  2. El podio de ASISTENCIA — comun a todos los roles, porque venir a
     trabajar es lo unico que se puede comparar igual entre categorias
     distintas sin inventar ningun tipo de cambio.

  Cada podio reparte bonus de LOGRO por posicion (10/8/6/4 para 1-4 lugar),
  separado de los puntos de canje. La suma de los dos bonus de un empleado
  es su puntaje de logro del ciclo. Gana quien mas sumo.

  Gerente no compite: no genera puntos por venta/stock (ver RegistroPuntos),
  asi que no tiene podio de categoria propio. Si algun dia gana sentido que
  compita solo por asistencia, es una decision aparte — hoy queda afuera del
  todo, igual que en la generacion de puntos.
  """
  import Ecto.Query
  alias DaleApp.Repo
  alias DaleApp.Accounts
  alias DaleApp.Accounts.Asistencia
  alias DaleApp.Products.{MovimientoPuntos, LogroMensual, RegistroPuntos}

  @bonus_por_posicion %{1 => 10, 2 => 8, 3 => 6, 4 => 4}

  @doc """
  Calcula y guarda los logros de un ciclo cerrado. Si ya existen filas para
  ese ciclo, no las toca — un ciclo se calcula una sola vez. Devuelve la
  lista de logros del ciclo (incluye ganadores y no ganadores).
  """
  def calcular_ciclo(brand, ciclo_inicio, ciclo_fin) do
    ya_calculado? =
      Repo.exists?(
        from l in LogroMensual,
          where: l.brand_id == ^brand.id and l.ciclo_inicio == ^ciclo_inicio
      )

    if ya_calculado? do
      logros_del_ciclo(brand.id, ciclo_inicio)
    else
      empleados = Accounts.list_cajeros(brand.id)

      bonus_categoria = podio_por_categoria(brand, empleados, ciclo_inicio, ciclo_fin)
      bonus_asistencia = podio_asistencia(empleados, ciclo_inicio, ciclo_fin)

      totales =
        Map.new(empleados, fn u ->
          {u.id,
           Map.get(bonus_categoria, u.id, 0) + Map.get(bonus_asistencia, u.id, 0)}
        end)
        |> Enum.reject(fn {_uid, total} -> total == 0 end)

      maximo = totales |> Enum.map(fn {_uid, total} -> total end) |> Enum.max(fn -> 0 end)

      Enum.each(totales, fn {user_id, total} ->
        %LogroMensual{}
        |> LogroMensual.changeset(%{
          brand_id: brand.id,
          user_id: user_id,
          ciclo_inicio: ciclo_inicio,
          ciclo_fin: ciclo_fin,
          puntos_logro: total,
          posicion_categoria: posicion_de(bonus_categoria, user_id),
          posicion_asistencia: posicion_de(bonus_asistencia, user_id),
          es_ganador: total == maximo and maximo > 0
        })
        |> Repo.insert()
      end)

      logros_del_ciclo(brand.id, ciclo_inicio)
    end
  end

  @doc "Logros ya calculados de un ciclo, con el usuario precargado."
  def logros_del_ciclo(brand_id, ciclo_inicio) do
    from(l in LogroMensual,
      where: l.brand_id == ^brand_id and l.ciclo_inicio == ^ciclo_inicio,
      order_by: [desc: l.puntos_logro],
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc """
  El dueño desempata: entre los ganadores actuales de un ciclo, deja a UNO
  solo como es_ganador y marca la eleccion como manual para que no se
  vuelva a recalcular. Falla si el usuario elegido no era uno de los
  empatados — no se puede "elegir" a alguien que no estaba en el podio.
  """
  def desempatar(brand_id, ciclo_inicio, user_id_elegido) do
    logros = logros_del_ciclo(brand_id, ciclo_inicio)
    empatados = Enum.filter(logros, & &1.es_ganador)

    if Enum.any?(empatados, &(&1.user_id == user_id_elegido)) do
      Enum.each(empatados, fn logro ->
        gana? = logro.user_id == user_id_elegido

        logro
        |> LogroMensual.changeset(%{
          es_ganador: gana?,
          ganador_elegido_manualmente: gana?
        })
        |> Repo.update()
      end)

      {:ok, logros_del_ciclo(brand_id, ciclo_inicio)}
    else
      {:error, :no_estaba_empatado}
    end
  end

  # --- Podios internos ---

  defp podio_por_categoria(brand, empleados, ciclo_inicio, ciclo_fin) do
    puntos_por_usuario =
      from(m in MovimientoPuntos,
        where: m.brand_id == ^brand.id and m.fecha >= ^ciclo_inicio and m.fecha < ^ciclo_fin,
        group_by: m.user_id,
        select: {m.user_id, sum(m.puntos_finales)}
      )
      |> Repo.all()
      |> Map.new()

    empleados
    |> Enum.group_by(&RegistroPuntos.categoria_de_rol/1)
    |> Enum.reject(fn {categoria, _lista} -> is_nil(categoria) end)
    |> Enum.flat_map(fn {_categoria, lista} ->
      lista
      |> Enum.map(fn u -> {u.id, Map.get(puntos_por_usuario, u.id, 0)} end)
      |> Enum.filter(fn {_uid, puntos} -> puntos > 0 end)
      |> Enum.sort_by(fn {_uid, puntos} -> puntos end, :desc)
      |> Enum.with_index(1)
      |> Enum.map(fn {{uid, _puntos}, posicion} -> {uid, posicion} end)
    end)
    |> Map.new(fn {uid, posicion} -> {uid, {posicion, Map.get(@bonus_por_posicion, posicion, 0)}} end)
    |> Map.new(fn {uid, {_pos, bonus}} -> {uid, bonus} end)
  end

  defp podio_asistencia(empleados, ciclo_inicio, ciclo_fin) do
    ids = Enum.map(empleados, & &1.id)

    from(a in Asistencia,
      where: a.user_id in ^ids and a.inserted_at >= ^ciclo_inicio and a.inserted_at < ^ciclo_fin,
      group_by: a.user_id,
      select: {a.user_id, sum(a.puntos)}
    )
    |> Repo.all()
    |> Enum.sort_by(fn {_uid, puntos} -> puntos end, :desc)
    |> Enum.with_index(1)
    |> Map.new(fn {{uid, _puntos}, posicion} -> {uid, Map.get(@bonus_por_posicion, posicion, 0)} end)
  end

  defp posicion_de(bonus_map, user_id) do
    case Map.get(bonus_map, user_id) do
      nil -> nil
      bonus -> Enum.find_value(@bonus_por_posicion, fn {pos, b} -> if b == bonus, do: pos end)
    end
  end

end
