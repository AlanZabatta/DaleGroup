defmodule DaleApp.Products.Puntos do
  @moduledoc """
  Sistema de puntos de empleados.

  Arquitectura:
  - Cada empleado tiene DOS saldos separados, cada uno pura suma de
    puntos crudos históricos (Asistencia + su categoría + podios de su
    categoría). Los saldos NUNCA se convierten ni se tocan
    retroactivamente — solo crecen con lo que se gana.
  - Lo que varía día a día es el PRECIO EFECTIVO que paga un empleado
    de Gestores por un premio, según el tipo de cambio del día. El
    precio que puso el dueño (en moneda Ventas) nunca cambia.
  - El tipo de cambio se recalibra una vez por día, con la circulación
    real (generado - gastado) de los últimos 90 días de cada categoría,
    mezclada con un empujón chico y constante hacia la paridad 1:1
    (por si el patrón de gasto de una marca puntual tira para el lado
    contrario). Nunca varía más de ±10% respecto al día anterior.
  - Se guarda una fila por marca por día (tabla tipos_cambio_diarios);
    se retienen 100 días y se podan los más viejos.
  """

  import Ecto.Query
  alias DaleApp.Repo
  alias DaleApp.Accounts.{Asistencia, RolEmpleado}
  alias DaleApp.Products.{Venta, MovimientoStock, IncidenciaStock, Canje, TipoCambioDiario}

  @dias_ciclo 30
  @tope_diario_ventas 200
  @dias_ventana_circulacion 90
  @dias_retencion 100
  @tope_variacion_diaria 0.10
  @peso_convergencia_inicial 0.15
  @peso_convergencia_incremento_por_ciclo 0.10
  @peso_convergencia_maximo 0.95

  # Minimo de personas que generaron puntos en una categoria para confiar en
  # el dato. Al medir por persona (y no por pool total), alcanza con una.
  @minimo_activos_para_calibrar 1

  # Factor de arranque cuando todavia no hay datos. No es un numero al azar:
  # es la asimetria que crean las propias reglas. Una venta tipica (2 items)
  # paga 30 puntos; cargar un item paga 10. Tres a uno. Mientras la marca no
  # tenga historial, se asume esa relacion y despues el promedio movil la
  # ajusta contra lo que realmente pase en ese local.
  #
  # NO poner 1.0: significa que Gestores paga el precio completo, el peor
  # caso posible para ellos. Sin datos, el sistema falla hacia el lado
  # generoso, no hacia el que castiga.
  @factor_inicial_sin_datos 3.0

  @bonus_podio_ventas %{1 => 200, 2 => 120, 3 => 80, 4 => 50}
  @bonus_podio_gestores %{1 => 400, 2 => 300, 3 => 250, 4 => 200}
  @bonus_podio_default_gestores 150
  @bonus_podio_default_ventas 0

  # --- Fórmulas base ---

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

  def bonus_podio_ventas(posicion) when posicion >= 1,
    do: Map.get(@bonus_podio_ventas, posicion, @bonus_podio_default_ventas)

  def bonus_podio_gestores(posicion) when posicion >= 1,
    do: Map.get(@bonus_podio_gestores, posicion, @bonus_podio_default_gestores)

  # --- Categoría del empleado ---

  @doc "Categoría de competencia: 'ventas' o 'gestores', según el rol (campo zona)."
  def categoria_del_usuario(usuario) do
    case usuario && RolEmpleado.categoria_ranking(usuario.role) do
      "gestiones" -> "gestores"
      _ -> "ventas"
    end
  end

  # --- Ciclos de 30 días (para podios) ---

  def ciclos_desde(activada_en, ahora \\ DateTime.utc_now()) do
    dias_transcurridos = DateTime.diff(ahora, activada_en, :day)
    cantidad_ciclos = div(dias_transcurridos, @dias_ciclo) + 1

    for i <- 0..(cantidad_ciclos - 1) do
      inicio = DateTime.add(activada_en, i * @dias_ciclo * 86400, :second) |> DateTime.to_date()
      fin = Date.add(inicio, @dias_ciclo)
      {inicio, fin}
    end
  end

  def ciclos_cerrados(ciclos, hoy \\ Date.utc_today()) do
    Enum.filter(ciclos, fn {_inicio, fin} -> Date.compare(fin, hoy) != :gt end)
  end

  defp rango_naive(desde, hasta) do
    desde_dt = if desde, do: NaiveDateTime.new!(desde, ~T[00:00:00]), else: nil
    hasta_dt = if hasta, do: NaiveDateTime.new!(hasta, ~T[00:00:00]), else: nil
    {desde_dt, hasta_dt}
  end

  @doc "Puntos crudos de Ventas por usuario (con tope diario), en un rango opcional."
  def puntos_ventas_por_usuario(brand_id, desde \\ nil, hasta \\ nil) do
    {desde_dt, hasta_dt} = rango_naive(desde, hasta)

    query = from(v in Venta, where: v.brand_id == ^brand_id and not is_nil(v.user_id))
    query = if desde_dt, do: from(v in query, where: v.inserted_at >= ^desde_dt), else: query
    query = if hasta_dt, do: from(v in query, where: v.inserted_at < ^hasta_dt), else: query

    from(v in query,
      group_by: [v.user_id, v.grupo_venta],
      select: {v.user_id, count(v.id), min(v.inserted_at)}
    )
    |> Repo.all()
    |> Enum.group_by(
      fn {user_id, _c, _f} -> user_id end,
      fn {_user_id, c, f} -> {NaiveDateTime.to_date(f), c} end
    )
    |> Enum.map(fn {user_id, grupos} ->
      puntos =
        grupos
        |> Enum.group_by(fn {dia, _c} -> dia end, fn {_dia, c} -> c end)
        |> Enum.map(fn {_dia, cantidades} -> aplicar_tope_diario_ventas(cantidades) end)
        |> Enum.sum()

      {user_id, puntos}
    end)
    |> Map.new()
  end

  @doc "Puntos crudos de Gestores por usuario, en un rango opcional."
  def puntos_gestores_por_usuario(brand_id, desde \\ nil, hasta \\ nil) do
    {desde_dt, hasta_dt} = rango_naive(desde, hasta)

    query_movs =
      from(m in MovimientoStock, where: m.brand_id == ^brand_id and m.tipo_accion == "creado" and not is_nil(m.user_id))

    query_movs = if desde_dt, do: from(m in query_movs, where: m.inserted_at >= ^desde_dt), else: query_movs
    query_movs = if hasta_dt, do: from(m in query_movs, where: m.inserted_at < ^hasta_dt), else: query_movs

    puntos_creaciones =
      from(m in query_movs, group_by: m.user_id, select: {m.user_id, count(m.id) * 10})
      |> Repo.all()
      |> Map.new()

    query_inc =
      from(i in IncidenciaStock, where: i.brand_id == ^brand_id and i.resuelta == true and not is_nil(i.resuelto_por_user_id))

    query_inc = if desde_dt, do: from(i in query_inc, where: i.fecha_resolucion >= ^desde_dt), else: query_inc
    query_inc = if hasta_dt, do: from(i in query_inc, where: i.fecha_resolucion < ^hasta_dt), else: query_inc

    puntos_incidencias =
      from(i in query_inc, group_by: i.resuelto_por_user_id, select: {i.resuelto_por_user_id, sum(i.puntos_otorgados)})
      |> Repo.all()
      |> Map.new()

    Map.merge(puntos_creaciones, puntos_incidencias, fn _user_id, a, b -> a + b end)
  end

  defp bonus_podios(_brand_id, nil, _calcular_puntos_fn, _bonus_fn), do: %{}

  defp bonus_podios(brand_id, activada_en, calcular_puntos_fn, bonus_fn) do
    activada_en
    |> ciclos_desde()
    |> ciclos_cerrados()
    |> Enum.reduce(%{}, fn {inicio, fin}, acc ->
      calcular_puntos_fn.(brand_id, inicio, fin)
      |> Enum.sort_by(fn {_user_id, puntos} -> puntos end, :desc)
      |> Enum.with_index(1)
      |> Enum.reduce(acc, fn {{user_id, _puntos}, posicion}, acc2 ->
        Map.update(acc2, user_id, bonus_fn.(posicion), &(&1 + bonus_fn.(posicion)))
      end)
    end)
  end

  def bonus_podios_ventas(brand),
    do: bonus_podios(brand.id, brand.ventas_activada_en, &puntos_ventas_por_usuario/3, &bonus_podio_ventas/1)

  def bonus_podios_gestores(brand),
    do: bonus_podios(brand.id, brand.gestiones_activada_en, &puntos_gestores_por_usuario/3, &bonus_podio_gestores/1)

  defp puntos_asistencia_por_usuario(brand_id) do
    from(a in Asistencia, where: a.brand_id == ^brand_id, group_by: a.user_id, select: {a.user_id, sum(a.puntos)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Saldo crudo en moneda Ventas de cada empleado: Asistencia + Ventas + podio Ventas. NUNCA se convierte."
  def saldo_ventas_por_usuario(brand) do
    asistencia = puntos_asistencia_por_usuario(brand.id)
    ventas = puntos_ventas_por_usuario(brand.id)
    bonus = bonus_podios_ventas(brand)

    (Map.keys(asistencia) ++ Map.keys(ventas) ++ Map.keys(bonus))
    |> Enum.uniq()
    |> Enum.map(fn uid ->
      {uid, Map.get(asistencia, uid, 0) + Map.get(ventas, uid, 0) + Map.get(bonus, uid, 0)}
    end)
    |> Map.new()
  end

  @doc "Saldo crudo en moneda Gestores de cada empleado: Asistencia + Gestores + podio Gestores. NUNCA se convierte."
  def saldo_gestores_por_usuario(brand) do
    asistencia = puntos_asistencia_por_usuario(brand.id)
    gestores = puntos_gestores_por_usuario(brand.id)
    bonus = bonus_podios_gestores(brand)

    (Map.keys(asistencia) ++ Map.keys(gestores) ++ Map.keys(bonus))
    |> Enum.uniq()
    |> Enum.map(fn uid ->
      {uid, Map.get(asistencia, uid, 0) + Map.get(gestores, uid, 0) + Map.get(bonus, uid, 0)}
    end)
    |> Map.new()
  end

  @doc "Saldo crudo del usuario en su propia categoría (según su rol)."
  def saldo_del_usuario(brand, usuario) do
    case categoria_del_usuario(usuario) do
      "gestores" -> saldo_gestores_por_usuario(brand) |> Map.get(usuario.id, 0)
      _ -> saldo_ventas_por_usuario(brand) |> Map.get(usuario.id, 0)
    end
  end

  # --- Circulación y tipo de cambio diario ---

  defp gastado_categoria(brand_id, categoria, desde_dt, hasta_dt) do
    from(c in Canje,
      where: c.brand_id == ^brand_id and c.es_dueño == false and
        c.inserted_at >= ^desde_dt and c.inserted_at < ^hasta_dt and
        not is_nil(c.puntos_antes) and not is_nil(c.puntos_despues),
      select: {c.user_id, c.puntos_antes - c.puntos_despues}
    )
    |> Repo.all()
    |> Enum.filter(fn {user_id, _gastado} ->
      usuario = DaleApp.Accounts.get_user(user_id)
      categoria_del_usuario(usuario) == categoria
    end)
    |> Enum.map(fn {_user_id, gastado} -> gastado end)
    |> Enum.sum()
  end

  defp circulacion_ventana(brand_id, hasta_date) do
    desde_date = Date.add(hasta_date, -@dias_ventana_circulacion)
    {desde_dt, hasta_dt} = rango_naive(desde_date, hasta_date)

    puntos_ventas = puntos_ventas_por_usuario(brand_id, desde_date, hasta_date)
    puntos_gestores = puntos_gestores_por_usuario(brand_id, desde_date, hasta_date)

    generado_ventas = puntos_ventas |> Map.values() |> Enum.sum()
    generado_gestores = puntos_gestores |> Map.values() |> Enum.sum()

    gastado_ventas = gastado_categoria(brand_id, "ventas", desde_dt, hasta_dt)
    gastado_gestores = gastado_categoria(brand_id, "gestores", desde_dt, hasta_dt)

    circulacion_ventas = max(generado_ventas - gastado_ventas, 0)
    circulacion_gestores = max(generado_gestores - gastado_gestores, 0)

    {circulacion_ventas, circulacion_gestores, contar_activos(puntos_ventas),
     contar_activos(puntos_gestores)}
  end

  # Cuenta empleados que REALMENTE generaron puntos en la ventana. No usamos la
  # nomina: alguien cargado en el sistema que nunca trabajo bajaria el promedio
  # y volveria a meter el mismo ruido que estamos sacando.
  defp contar_activos(mapa_puntos) do
    mapa_puntos |> Map.values() |> Enum.count(&(&1 > 0))
  end

  @doc """
  Peso de la convergencia hacia la paridad 1:1, creciente con el tiempo:
  arranca en #{@peso_convergencia_inicial} apenas termina el período
  regulatorio, y sube #{@peso_convergencia_incremento_por_ciclo} por cada
  ciclo de 30 días transcurrido desde entonces, hasta un máximo de
  #{@peso_convergencia_maximo} (nunca 100%, siempre queda algo de señal real).
  """
  def peso_convergencia_vigente(brand) do
    fin_regulacion =
      brand.empleado_puntos_activada_en &&
        DateTime.add(brand.empleado_puntos_activada_en, @dias_ventana_circulacion * 86400, :second)

    if is_nil(fin_regulacion) or DateTime.compare(DateTime.utc_now(), fin_regulacion) == :lt do
      @peso_convergencia_inicial
    else
      dias_desde_fin = DateTime.diff(DateTime.utc_now(), fin_regulacion, :day)
      ciclos_transcurridos = div(dias_desde_fin, @dias_ciclo)
      peso = @peso_convergencia_inicial + ciclos_transcurridos * @peso_convergencia_incremento_por_ciclo
      min(peso, @peso_convergencia_maximo)
    end
  end

  # El ratio se mide POR PERSONA, no por pool total. Un pool total escala con
  # la cantidad de gente: 20 vendedores contra 2 gestores da un 10x que no
  # tiene nada que ver con el esfuerzo, y si un gestor se va el ratio se
  # duplica solo. Dividido por activos, un equipo de 2 y uno de 40 dan el
  # mismo numero si trabajan al mismo ritmo.
  defp factor_objetivo(
         {circ_ventas, circ_gestores, activos_ventas, activos_gestores},
         _peso_convergencia,
         _factor_resguardo
       )
       when activos_ventas >= @minimo_activos_para_calibrar and
              activos_gestores >= @minimo_activos_para_calibrar and
              circ_ventas > 0 and circ_gestores > 0 do
    promedio_ventas = circ_ventas / activos_ventas
    promedio_gestores = circ_gestores / activos_gestores
    promedio_ventas / promedio_gestores
  end

  # Sin nadie activo en alguna categoria (o sin circulacion): no hay dato que
  # leer, el sistema mantiene el factor que traia.
  defp factor_objetivo(_circulacion, _peso_convergencia, factor_resguardo),
    do: factor_resguardo

  @doc """
  Suaviza el movimiento del factor con un promedio móvil: cada día se
  acerca al objetivo solo una fracción chica (#{trunc(@tope_variacion_diaria * 100)}%),
  nunca salta directo. A diferencia de un tope multiplicativo día contra
  día (que permite saltos enormes acumulados en un mes), esto es estable
  sin importar cuántos días pasen ni qué tan chico/volátil sea el pool
  de una categoría — funciona igual de bien para cualquier tamaño de marca.
  """
  defp suavizar_hacia_objetivo(objetivo, anterior) do
    anterior + (objetivo - anterior) * @tope_variacion_diaria
  end

  defp factor_de_ayer(brand_id, hoy) do
    from(t in TipoCambioDiario,
      where: t.brand_id == ^brand_id and t.fecha < ^hoy,
      order_by: [desc: t.fecha],
      limit: 1,
      select: t.factor
    )
    |> Repo.one()
  end

  @doc """
  Tipo de cambio vigente HOY para una marca. Si ya se calculó hoy, lo
  devuelve. Si no, lo calcula (circulación de los últimos #{@dias_ventana_circulacion}
  días + empujón de convergencia, topado a ±#{trunc(@tope_variacion_diaria * 100)}%
  respecto a ayer), lo guarda, y poda filas viejas.
  """
  def factor_vigente(brand) do
    hoy = Date.utc_today()

    case Repo.get_by(TipoCambioDiario, brand_id: brand.id, fecha: hoy) do
      %TipoCambioDiario{factor: factor} ->
        factor

      nil ->
        circulacion = circulacion_ventana(brand.id, hoy)
        {circulacion_ventas, circulacion_gestores, _, _} = circulacion
        peso_convergencia = peso_convergencia_vigente(brand)
        anterior = factor_de_ayer(brand.id, hoy)
        factor_resguardo = anterior || @factor_inicial_sin_datos
        objetivo = factor_objetivo(circulacion, peso_convergencia, factor_resguardo)

        dentro_del_periodo_regulatorio? =
          brand.empleado_puntos_activada_en &&
            DateTime.diff(DateTime.utc_now(), brand.empleado_puntos_activada_en, :day) < @dias_ventana_circulacion

        factor_final =
          cond do
            dentro_del_periodo_regulatorio? -> objetivo
            is_nil(anterior) -> objetivo
            true -> suavizar_hacia_objetivo(objetivo, anterior)
          end

        %TipoCambioDiario{}
        |> TipoCambioDiario.changeset(%{
          brand_id: brand.id,
          fecha: hoy,
          factor: factor_final,
          ventas_generado: circulacion_ventas,
          gestores_generado: circulacion_gestores
        })
        |> Repo.insert()

        podar_filas_viejas(brand.id, hoy)

        factor_final
    end
  end

  defp podar_filas_viejas(brand_id, hoy) do
    limite = Date.add(hoy, -@dias_retencion)
    from(t in TipoCambioDiario, where: t.brand_id == ^brand_id and t.fecha < ^limite)
    |> Repo.delete_all()
  end

  # Garantía dura: sin importar qué tan volátil esté el mercado interno de
  # la marca, el costo efectivo para Gestores nunca cae por debajo de este
  # piso del precio original. Esto acota la brecha máxima posible, protegiendo
  # el objetivo de "esfuerzos parecidos" incluso en marcas con poco personal
  # en una categoría (donde la circulación real puede ser muy ruidosa).
  @piso_minimo_costo_efectivo 0.15

  @doc "Costo efectivo en puntos de Gestores para un precio original, según el factor vigente. Nunca cae por debajo del #{trunc(@piso_minimo_costo_efectivo * 100)}% del precio original."
  def costo_efectivo_gestores(precio_original, factor) when factor > 0 do
    piso = round(precio_original * @piso_minimo_costo_efectivo)
    round(precio_original / factor) |> max(piso)
  end

  def costo_efectivo_gestores(precio_original, _factor), do: precio_original

  @doc "Costo que le corresponde pagar a un usuario específico por un premio, según su categoría."
  def costo_para_usuario(brand, usuario, precio_original) do
    case categoria_del_usuario(usuario) do
      "gestores" -> costo_efectivo_gestores(precio_original, factor_vigente(brand))
      _ -> precio_original
    end
  end
end
