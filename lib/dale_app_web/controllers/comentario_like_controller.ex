defmodule DaleAppWeb.ComentarioLikeController do
  use DaleAppWeb, :controller
  alias DaleApp.Comentarios

  def toggle(conn, %{"comentario_id" => comentario_id}) do
    user = conn.assigns.current_user
    unless user, do: json(conn, %{ok: false})
    {:ok, accion} = Comentarios.toggle_like(user.id, String.to_integer(comentario_id))
    json(conn, %{ok: true, accion: accion})
  end
end
