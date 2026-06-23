defmodule DaleAppWeb.FriendController do
  use DaleAppWeb, :controller
  alias DaleApp.Friends

  def buscar(conn, %{"username" => username}) do
    user_id = get_session(conn, :user_id)
    case Friends.find_by_username(String.trim(username), user_id) do
      nil ->
        json(conn, %{ok: false, error: "not_found"})
      user ->
        relacion = Friends.relation_status(user_id, user.id)
        estado = cond do
          is_nil(relacion) -> "none"
          relacion.status == "accepted" -> "friends"
          relacion.status == "pending" and relacion.requester_id == user_id -> "sent"
          relacion.status == "pending" -> "received"
          true -> "none"
        end
        json(conn, %{ok: true, id: user.id, username: user.username, name: user.name, avatar: user.avatar, estado: estado})
    end
  end

  def solicitar(conn, %{"id" => addressee_id}) do
    user_id = get_session(conn, :user_id)
    case Friends.send_request(user_id, if(is_binary(addressee_id), do: String.to_integer(addressee_id), else: addressee_id)) do
      {:ok, _} -> json(conn, %{ok: true})
      {:error, _} -> json(conn, %{ok: false})
    end
  end

  def aceptar(conn, %{"id" => id}) do
    user_id = get_session(conn, :user_id)
    case Friends.accept_request(String.to_integer(id), user_id) do
      {:ok, _} -> json(conn, %{ok: true})
      {:error, _} -> json(conn, %{ok: false})
    end
  end

  def rechazar(conn, %{"id" => id}) do
    user_id = get_session(conn, :user_id)
    Friends.reject_request(String.to_integer(id), user_id)
    json(conn, %{ok: true})
  end
end
