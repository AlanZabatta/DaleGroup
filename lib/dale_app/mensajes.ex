defmodule DaleApp.Mensajes do
  import Ecto.Query
  alias DaleApp.Repo
  alias DaleApp.Mensajes.Mensaje

  # Enviar un mensaje
  def enviar(remitente_id, destinatario_id, texto) do
    %Mensaje{}
    |> Mensaje.changeset(%{
      remitente_id: remitente_id,
      destinatario_id: destinatario_id,
      texto: texto
    })
    |> Repo.insert()
  end

  # Traer la conversacion entre dos usuarios (ordenada por fecha)
  def conversacion(user_id, otro_id) do
    Repo.all(
      from m in Mensaje,
      where:
        (m.remitente_id == ^user_id and m.destinatario_id == ^otro_id) or
        (m.remitente_id == ^otro_id and m.destinatario_id == ^user_id),
      order_by: [asc: m.inserted_at]
    )
  end

  # Marcar como leidos los mensajes que me mando el otro
  def marcar_leidos(user_id, otro_id) do
    from(m in Mensaje,
      where: m.destinatario_id == ^user_id and m.remitente_id == ^otro_id and m.leido == false
    )
    |> Repo.update_all(set: [leido: true])
  end

  # Contar mensajes sin leer (para el puntito de notificacion)
  def no_leidos(user_id) do
    Repo.aggregate(
      from(m in Mensaje, where: m.destinatario_id == ^user_id and m.leido == false),
      :count,
      :id
    )
  end

  # Lista de chats: cada amigo con su ultimo mensaje, no leidos y fecha
  def lista_chats(user_id) do
    amigos = DaleApp.Friends.friends_list(user_id)

    Enum.map(amigos, fn amigo ->
      ultimo =
        Repo.one(
          from m in Mensaje,
          where:
            (m.remitente_id == ^user_id and m.destinatario_id == ^amigo.id) or
            (m.remitente_id == ^amigo.id and m.destinatario_id == ^user_id),
          order_by: [desc: m.inserted_at],
          limit: 1
        )

      no_leidos =
        Repo.aggregate(
          from(m in Mensaje,
            where: m.destinatario_id == ^user_id and m.remitente_id == ^amigo.id and m.leido == false
          ),
          :count,
          :id
        )

      %{
        amigo: amigo,
        ultimo_texto: (ultimo && ultimo.texto) || nil,
        ultimo_mio: (ultimo && ultimo.remitente_id == user_id) || false,
        fecha: (ultimo && ultimo.inserted_at) || nil,
        no_leidos: no_leidos
      }
    end)
    |> Enum.sort_by(fn chat ->
      # primero los que tienen no leidos, despues por fecha mas reciente
      tiene_sin_leer = if chat.no_leidos > 0, do: 0, else: 1
      fecha_orden = case chat.fecha do
        nil -> ~N[2000-01-01 00:00:00]
        f -> f
      end
      {tiene_sin_leer, fecha_orden}
    end, fn {a1, f1}, {a2, f2} ->
      cond do
        a1 != a2 -> a1 <= a2
        true -> NaiveDateTime.compare(f1, f2) != :lt
      end
    end)
  end

end
