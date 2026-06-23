defmodule DaleAppWeb.LikeController do
  use DaleAppWeb, :controller
  alias DaleApp.Likes

  def toggle(conn, %{"publicacion_id" => publicacion_id}) do
    user = conn.assigns.current_user
    unless user, do: json(conn, %{ok: false})

    {status, accion} = Likes.toggle(user.id, String.to_integer(publicacion_id))
    conteo = Likes.contar(String.to_integer(publicacion_id))
    json(conn, %{ok: true, accion: accion, conteo: conteo})
  end
end
