defmodule DaleAppWeb.MensajeController do
  use DaleAppWeb, :controller
  alias DaleApp.Mensajes
  alias DaleApp.Accounts

  # Pantalla del chat con un amigo
  def chat(conn, %{"id" => otro_id}) do
    user_id = get_session(conn, :user_id)
    if is_nil(user_id) do
      redirect(conn, to: "/auth/google")
    else
      otro = Accounts.get_user(otro_id)
      mensajes = Mensajes.conversacion(user_id, String.to_integer(otro_id))
      Mensajes.marcar_leidos(user_id, String.to_integer(otro_id))
      current_user = Accounts.get_user(user_id)
      render(conn, :chat, current_user: current_user, otro: otro, mensajes: mensajes)
    end
  end

  # Enviar un mensaje (devuelve JSON)
  def enviar(conn, %{"destinatario_id" => dest_id, "texto" => texto}) do
    user_id = get_session(conn, :user_id)
    texto = String.trim(texto)
    cond do
      is_nil(user_id) -> json(conn, %{ok: false, error: "No logueado"})
      texto == "" -> json(conn, %{ok: false, error: "Mensaje vacio"})
      true ->
        case Mensajes.enviar(user_id, String.to_integer(dest_id), texto) do
          {:ok, m} -> json(conn, %{ok: true, id: m.id, texto: m.texto})
          {:error, _} -> json(conn, %{ok: false, error: "No se pudo enviar"})
        end
    end
  end

  # Traer mensajes nuevos (para refrescar el chat)
  def listar(conn, %{"id" => otro_id}) do
    user_id = get_session(conn, :user_id)
    if is_nil(user_id) do
      json(conn, %{ok: false})
    else
      otro = String.to_integer(otro_id)
      mensajes = Mensajes.conversacion(user_id, otro)
      Mensajes.marcar_leidos(user_id, otro)
      data = Enum.map(mensajes, fn m ->
        %{id: m.id, texto: m.texto, mio: m.remitente_id == user_id}
      end)
      json(conn, %{ok: true, mensajes: data})
    end
  end
end
