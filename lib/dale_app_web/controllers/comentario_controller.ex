defmodule DaleAppWeb.ComentarioController do
  use DaleAppWeb, :controller
  alias DaleApp.Comentarios

  def crear(conn, %{"publicacion_id" => publicacion_id, "contenido" => contenido}) do
    user = conn.assigns.current_user
    unless user, do: json(conn, %{ok: false})
    case Comentarios.crear(%{
      user_id: user.id,
      publicacion_id: String.to_integer(publicacion_id),
      contenido: contenido
    }) do
      {:ok, _c} ->
        mis_likes = Comentarios.mis_likes_comentarios(user.id, String.to_integer(publicacion_id))
        comentarios = Comentarios.listar(String.to_integer(publicacion_id))
        lista = Enum.map(comentarios, fn c ->
          %{id: c.id, username: c.user.username, contenido: c.contenido, avatar: c.user.avatar, likes_count: c.likes_count, liked: MapSet.member?(mis_likes, c.id)}
        end)
        json(conn, %{ok: true, comentarios: lista})
      {:error, _} ->
        json(conn, %{ok: false})
    end
  end

  def listar(conn, %{"publicacion_id" => publicacion_id}) do
    user = conn.assigns.current_user
    mis_likes = if user, do: Comentarios.mis_likes_comentarios(user.id, String.to_integer(publicacion_id)), else: MapSet.new()
    comentarios = Comentarios.listar(String.to_integer(publicacion_id))
    lista = Enum.map(comentarios, fn c ->
      %{id: c.id, username: c.user.username, contenido: c.contenido, avatar: c.user.avatar, likes_count: c.likes_count, liked: MapSet.member?(mis_likes, c.id)}
    end)
    json(conn, %{ok: true, comentarios: lista})
  end
end
