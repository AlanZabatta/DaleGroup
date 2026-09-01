defmodule DaleApp.Products.EmpleadoDelMes do
  @moduledoc """
  Empleado del mes: dos podios corren cada ciclo de 30 dias, DENTRO DE UNA
  SEDE (o de toda la marca si no se pasa sede_id — no tiene sentido hacer
  competir a alguien de Palermo contra alguien de Recoleta con ritmos de
  cliente totalmente distintos).

  1. El podio de la CATEGORIA de cada empleado (ventas, gestores o
     multitask) — mide el trabajo especifico de su rol.
  2. El podio de ASISTENCIA — comun a todos los roles, porque venir a
     trabajar es lo unico que se puede comparar igual entre categorias
     distintas sin inventar ningun tipo de cambio.

  Cada podio calcula la POSICION REAL de cada empleado (1ro, 2do, ... N),
  guardada siempre, sin importar cuan lejos quede del primer puesto — eso
  es lo que se muestra al usuario ("llegaste 5to en Ventas"). Aparte, solo
  el top 4 reparte BONUS DE LOGRO (10/8/6/4), que es lo que decide quien
  gana el mes — dos cosas relacionadas pero no iguales.

  DESEMPATE AUTOMATICO: si dos o mas empatan en el puntaje maximo, se
  desempata en cadena, sin comparar nada entre categorias distintas:
  1. Suma de posiciones cruda mas baja (categoria + asistencia) — mas fino
     que el bonus por escalon, que puede esconder diferencias reales.
  2. Si sigue empatado: mejor posicion en SU PROPIA categoria — el trabajo
     especifico del rol pesa mas que la asistencia, que es mas generica.
  3. Si sigue empatado: mas puntos CRUDOS generados ESE CICLO (no
     historicos, no el bonus por escalon) — practicamente nunca da empate.
  Si ni con eso se rompe, es un empate genuino: quedan todos marcados como
  ganadores, igual que antes. El dueño podra elegir a mano si quiere (fuera
  de este modulo).

  Gerente no compite: no genera puntos por venta/stock (ver RegistroPuntos),
  asi que no tiene podio de categoria propio.
  """
  import Ecto.Query
  alias DaleApp.Repo
  alias DaleApp.Accounts
  alias DaleApp.Accounts.Asistencia
  alias DaleApp.Products.{MovimientoPuntos, LogroMensual, RegistroPuntos}

  @bonus_por_posicion %{1 => 10, 2 => 8, 3 => 6, 4 => 4}

  @doc """
  Calcula y guarda los logros de un ciclo cerrado EN UNA SEDE (sede_id nil
  = toda la marca sin filtrar). Si ya existen filas para ese ciclo+sede, no
  las toca. Devuelve la lista de logros del ciclo+sede.
  """
  def calcular_ciclo(brand, ciclo_inicio, ciclo_fin, sede_id \\ nil) do
    ya_calculado? =
      from(l in LogroMensual, where: l.brand_id == ^brand.id and l.ciclo_inicio == ^ciclo_inicio)
      |> filtrar_logro_por_sede(sede_id)
      |> Repo.exists?()

    if ya_calculado? do
      logros_del_ciclo(brand.id, ciclo_inicio, sede_id)
    else
      empleados = empleados_de_sede(brand, sede_id)

      {posiciones_categoria, bonus_categoria} =
        podio_por_categoria(brand, empleados, ciclo_inicio, ciclo_fin, sede_id)

      {posiciones_asistencia, bonus_asistencia} =
        podio_asistencia(empleados, ciclo_inicio, ciclo_fin, sede_id)

      totales =
        Map.new(empleados, fn u ->
          {u.id,
           Map.get(bonus_categoria, u.id, 0) + Map.get(bonus_asistencia, u.id, 0)}
        end)
        |> Enum.reject(fn {_uid, total} -> total == 0 end)

      maximo = totales |> Enum.map(fn {_uid, total} -> total end) |> Enum.max(fn -> 0 end)

      candidatos =
        totales
        |> Enum.filter(fn {_uid, total} -> total == maximo and maximo > 0 end)
        |> Enum.map(fn {uid, _total} -> uid end)

      crudos_por_usuario =
        if length(candidatos) > 1 do
          puntos_crudos_por_usuario(brand, empleados, ciclo_inicio, ciclo_fin, sede_id)
        else
          %{}
        end

      ganadores_ids =
        desempatar_ganadores(candidatos, bonus_categoria, bonus_asistencia, crudos_por_usuario)
        |> MapSet.new()

      Enum.each(totales, fn {user_id, total} ->
        %LogroMensual{}
        |> LogroMensual.changeset(%{
          brand_id: brand.id,
          brand_location_id: sede_id,
          user_id: user_id,
          ciclo_inicio: ciclo_inicio,
          ciclo_fin: ciclo_fin,
          puntos_logro: total,
          posicion_categoria: Map.get(posiciones_categoria, user_id),
          posicion_asistencia: Map.get(posiciones_asistencia, user_id),
          es_ganador: MapSet.member?(ganadores_ids, user_id)
        })
        |> Repo.insert()
      end)

      logros_del_ciclo(brand.id, ciclo_inicio, sede_id)
    end
  end

  @doc "Logros ya calculados de un ciclo en una sede (nil = toda la marca), con el usuario precargado."
  def logros_del_ciclo(brand_id, ciclo_inicio, sede_id \\ nil) do
    from(l in LogroMensual,
      where: l.brand_id == ^brand_id and l.ciclo_inicio == ^ciclo_inicio,
      order_by: [desc: l.puntos_logro],
      preload: [:user]
    )
    |> filtrar_logro_por_sede(sede_id)
    |> Repo.all()
  end

  @doc """
  El dueño desempata: entre los ganadores actuales de un ciclo+sede, deja a
  UNO solo como es_ganador y marca la eleccion como manual. Queda para el
  caso de empate genuino que el desempate automatico no pudo resolver.
  """
  def desempatar(brand_id, ciclo_inicio, user_id_elegido, sede_id \\ nil) do
    logros = logros_del_ciclo(brand_id, ciclo_inicio, sede_id)
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

      {:ok, logros_del_ciclo(brand_id, ciclo_inicio, sede_id)}
    else
      {:error, :no_estaba_empatado}
    end
  end

  # --- Desempate automatico ---

  defp desempatar_ganadores([], _bonus_categoria, _bonus_asistencia, _crudos), do: []
  defp desempatar_ganadores([unico], _bonus_categoria, _bonus_asistencia, _crudos), do: [unico]

  defp desempatar_ganadores(candidatos, bonus_categoria, bonus_asistencia, crudos_por_usuario) do
    con_datos =
      Enum.map(candidatos, fn uid ->
        pos_cat = posicion_desde_bonus(bonus_categoria, uid) || 99
        pos_asis = posicion_desde_bonus(bonus_asistencia, uid) || 99

        %{
          uid: uid,
          suma_posiciones: pos_cat + pos_asis,
          pos_categoria: pos_cat,
          crudos: Map.get(crudos_por_usuario, uid, 0)
        }
      end)

    minimo_suma = con_datos |> Enum.map(& &1.suma_posiciones) |> Enum.min()
    paso1 = Enum.filter(con_datos, &(&1.suma_posiciones == minimo_suma))

    resultado =
      if length(paso1) == 1 do
        paso1
      else
        minima_pos_cat = paso1 |> Enum.map(& &1.pos_categoria) |> Enum.min()
        paso2 = Enum.filter(paso1, &(&1.pos_categoria == minima_pos_cat))

        if length(paso2) == 1 do
          paso2
        else
          maximo_crudos = paso2 |> Enum.map(& &1.crudos) |> Enum.max()
          Enum.filter(paso2, &(&1.crudos == maximo_crudos))
        end
      end

    Enum.map(resultado, & &1.uid)
  end

  defp puntos_crudos_por_usuario(brand, empleados, ciclo_inicio, ciclo_fin, sede_id) do
    ids = Enum.map(empleados, & &1.id)

    crudos_movimientos =
      from(m in MovimientoPuntos,
        where:
          m.brand_id == ^brand.id and m.user_id in ^ids and m.fecha >= ^ciclo_inicio and
            m.fecha < ^ciclo_fin,
        group_by: m.user_id,
        select: {m.user_id, sum(m.puntos_crudos)}
      )
      |> filtrar_movimiento_por_sede(sede_id)
      |> Repo.all()
      |> Map.new()

    crudos_asistencia =
      from(a in Asistencia,
        where: a.user_id in ^ids and a.fecha >= ^ciclo_inicio and a.fecha < ^ciclo_fin,
        group_by: a.user_id,
        select: {a.user_id, sum(a.puntos)}
      )
      |> filtrar_asistencia_por_sede(sede_id)
      |> Repo.all()
      |> Map.new()

    Map.merge(crudos_movimientos, crudos_asistencia, fn _uid, a, b -> a + b end)
  end

  # --- Internos ---

  defp empleados_de_sede(brand, nil), do: Accounts.list_cajeros(brand.id)

  defp empleados_de_sede(brand, sede_id) do
    ids_en_sede = Accounts.usuarios_en_sede(sede_id) |> MapSet.new()
    Accounts.list_cajeros(brand.id) |> Enum.filter(&MapSet.member?(ids_en_sede, &1.id))
  end

  # Devuelve {posiciones_reales, bonus}. posiciones_reales tiene la posicion
  # de TODOS los que generaron puntos (1ro, 2do, ... Nmo, sin tope). bonus
  # solo tiene entradas para el top 4, que es lo unico que cuenta para
  # decidir el ganador del mes.
  defp podio_por_categoria(brand, empleados, ciclo_inicio, ciclo_fin, sede_id) do
    puntos_por_usuario =
      from(m in MovimientoPuntos,
        where: m.brand_id == ^brand.id and m.fecha >= ^ciclo_inicio and m.fecha < ^ciclo_fin,
        group_by: m.user_id,
        select: {m.user_id, sum(m.puntos_finales)}
      )
      |> filtrar_movimiento_por_sede(sede_id)
      |> Repo.all()
      |> Map.new()

    pares_posicion =
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

    posiciones = Map.new(pares_posicion)

    bonus =
      pares_posicion
      |> Enum.filter(fn {_uid, posicion} -> posicion <= 4 end)
      |> Map.new(fn {uid, posicion} -> {uid, Map.get(@bonus_por_posicion, posicion, 0)} end)

    {posiciones, bonus}
  end

  defp podio_asistencia(empleados, ciclo_inicio, ciclo_fin, sede_id) do
    ids = Enum.map(empleados, & &1.id)

    pares_posicion =
      from(a in Asistencia,
        where: a.user_id in ^ids and a.fecha >= ^ciclo_inicio and a.fecha < ^ciclo_fin,
        group_by: a.user_id,
        select: {a.user_id, sum(a.puntos)}
      )
      |> filtrar_asistencia_por_sede(sede_id)
      |> Repo.all()
      |> Enum.sort_by(fn {_uid, puntos} -> puntos end, :desc)
      |> Enum.with_index(1)
      |> Enum.map(fn {{uid, _puntos}, posicion} -> {uid, posicion} end)

    posiciones = Map.new(pares_posicion)

    bonus =
      pares_posicion
      |> Enum.filter(fn {_uid, posicion} -> posicion <= 4 end)
      |> Map.new(fn {uid, posicion} -> {uid, Map.get(@bonus_por_posicion, posicion, 0)} end)

    {posiciones, bonus}
  end

  defp filtrar_movimiento_por_sede(query, nil), do: query
  defp filtrar_movimiento_por_sede(query, sede_id), do: from(m in query, where: m.brand_location_id == ^sede_id)

  defp filtrar_asistencia_por_sede(query, nil), do: query
  defp filtrar_asistencia_por_sede(query, sede_id), do: from(a in query, where: a.brand_location_id == ^sede_id)

  defp filtrar_logro_por_sede(query, nil), do: from(l in query, where: is_nil(l.brand_location_id))
  defp filtrar_logro_por_sede(query, sede_id), do: from(l in query, where: l.brand_location_id == ^sede_id)

  defp posicion_desde_bonus(bonus_map, user_id) do
    case Map.get(bonus_map, user_id) do
      nil -> nil
      bonus -> Enum.find_value(@bonus_por_posicion, fn {pos, b} -> if b == bonus, do: pos end)
    end
  end
end
