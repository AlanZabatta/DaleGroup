defmodule DaleApp.Products.NotificacionesSeguridad do
  import Ecto.Query
  alias DaleApp.Repo
  alias DaleApp.Accounts
  alias DaleApp.Brands.HorarioTrabajo
  alias DaleApp.Products.MovimientoStock

  @dias_espanol %{
    1 => "lunes", 2 => "martes", 3 => "miercoles",
    4 => "jueves", 5 => "viernes", 6 => "sabado", 7 => "domingo"
  }

  # attrs: %{brand: brand, user_id: user_id, nombre_empleado: string, nombre_producto: string,
  #          tipo_accion: "creado" | "eliminado" | "aumentado" | "disminuido" | "editado",
  #          precio_anterior: integer | nil, precio_nuevo: integer | nil}
  alias DaleApp.Brands.Brand

  # attrs: %{brand_id: id, user_id: user_id, tipo_accion: ..., nombre_producto: string,
  #          precio_anterior: integer | nil, precio_nuevo: integer | nil}
  def revisar(attrs) do
    brand = Repo.get(Brand, attrs.brand_id)

    if brand && brand.notificaciones_seguridad_activas do
      attrs = attrs |> Map.put(:brand, brand) |> Map.put(:nombre_empleado, nombre_de_usuario(attrs.user_id))

      mensajes =
        []
        |> concat_si(regla_borrados_seguidos(brand, attrs))
        |> concat_si(regla_precio(attrs))
        |> concat_si(regla_horario(attrs))

      Enum.each(mensajes, fn mensaje -> enviar(brand, mensaje) end)
    end
  end

  defp concat_si(lista, nil), do: lista
  defp concat_si(lista, mensaje), do: lista ++ [mensaje]

  defp nombre_de_usuario(user_id) do
    usuario = Accounts.get_user(user_id)

    cond do
      is_nil(usuario) -> "Alguien"
      usuario.apellido_visible not in [nil, ""] and usuario.nombre_visible not in [nil, ""] ->
        "#{usuario.nombre_visible} #{usuario.apellido_visible}"
      usuario.nombre_visible not in [nil, ""] -> usuario.nombre_visible
      true -> usuario.name || "Alguien"
    end
  end

  # --- Regla 1: muchos borrados seguidos ---
  defp regla_borrados_seguidos(_brand, %{tipo_accion: "eliminado"} = attrs) do
    hace_10_min = NaiveDateTime.add(NaiveDateTime.utc_now(), -10 * 60, :second)

    cantidad =
      Repo.aggregate(
        from(m in MovimientoStock,
          where:
            m.brand_id == ^attrs.brand.id and
              m.user_id == ^attrs.user_id and
              m.tipo_accion == "eliminado" and
              m.inserted_at >= ^hace_10_min
        ),
        :count
      )

    if cantidad == 3 do
      "#{attrs.nombre_empleado} eliminó 3 productos en los últimos 10 minutos"
    else
      nil
    end
  end

  defp regla_borrados_seguidos(_brand, _attrs), do: nil

  # --- Regla 2: cambios de precio drásticos ---
  defp regla_precio(%{precio_anterior: pa, precio_nuevo: pn, nombre_empleado: nombre, nombre_producto: producto})
       when is_integer(pa) and is_integer(pn) and pa > 0 do
    cond do
      pn <= pa * 0.7 ->
        porcentaje = round((1 - pn / pa) * 100)
        "#{nombre} bajó el precio de \"#{producto}\" un #{porcentaje}% (de $#{pa} a $#{pn})"

      pn >= pa * 2 ->
        "#{nombre} cambió el precio de \"#{producto}\" de $#{pa} a $#{pn}"

      true ->
        nil
    end
  end

  defp regla_precio(_attrs), do: nil

  # --- Regla 3: fuera de horario laboral ---
  defp regla_horario(attrs) do
    usuario = Accounts.get_user(attrs.user_id)

    if usuario && usuario.horario_id do
      horario = Repo.get(HorarioTrabajo, usuario.horario_id)
      ahora_ar = NaiveDateTime.add(NaiveDateTime.utc_now(), -3 * 3600, :second)
      dia_semana = Map.get(@dias_espanol, Date.day_of_week(NaiveDateTime.to_date(ahora_ar)))
      hora_actual = NaiveDateTime.to_time(ahora_ar)

      {hora_entrada, hora_salida} = horario_del_dia(horario, dia_semana)

      cond do
        is_nil(hora_entrada) ->
          nil

        fuera_de_ventana?(hora_actual, hora_entrada, hora_salida) ->
          "#{attrs.nombre_empleado} modificó stock a las #{format_hora(hora_actual)}, fuera de su horario habitual"

        true ->
          nil
      end
    else
      nil
    end
  end

  defp horario_del_dia(nil, _dia_semana), do: {nil, nil}

  defp horario_del_dia(horario, dia_semana) do
    cond do
      horario.tipo == "especifico" && Map.has_key?(horario.horario_por_dia || %{}, dia_semana) ->
        datos = Map.get(horario.horario_por_dia, dia_semana)
        {parsear_hora(datos["entrada"]), parsear_hora(datos["salida"])}

      horario.tipo == "general" && dia_semana in (horario.dias || []) ->
        {parsear_hora(horario.hora_entrada_general), parsear_hora(horario.hora_salida_general)}

      true ->
        {nil, nil}
    end
  end

  defp parsear_hora(nil), do: nil
  defp parsear_hora(""), do: nil

  defp parsear_hora(texto) do
    case String.split(texto, ":") do
      [h, m] -> Time.new!(String.to_integer(h), String.to_integer(m), 0)
      _ -> nil
    end
  end

  defp fuera_de_ventana?(hora_actual, hora_entrada, nil) do
    Time.compare(hora_actual, hora_entrada) == :lt
  end

  defp fuera_de_ventana?(hora_actual, hora_entrada, hora_salida) do
    Time.compare(hora_actual, hora_entrada) == :lt or Time.compare(hora_actual, hora_salida) == :gt
  end

  defp format_hora(%Time{hour: h, minute: m}) do
    "#{String.pad_leading(Integer.to_string(h), 2, "0")}:#{String.pad_leading(Integer.to_string(m), 2, "0")}"
  end

  # --- Envío real ---
  defp enviar(brand, mensaje) do
    suscripciones = Accounts.listar_push_subscriptions(brand.user_id)

    suscripciones
    |> Enum.filter(fn sub -> sub.endpoint && sub.p256dh && sub.auth end)
    |> Enum.each(fn sub ->
      subscription_json =
        Jason.encode!(%{endpoint: sub.endpoint, keys: %{p256dh: sub.p256dh, auth: sub.auth}})

      payload = Jason.encode!(%{titulo: "Alerta de seguridad", cuerpo: mensaje, url: "/mi-tienda/stock/bitacora"})

      try do
        WebPushElixir.send_notification(subscription_json, payload)
      rescue
        _ -> :ok
      end
    end)
  end
end
