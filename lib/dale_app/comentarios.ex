defmodule DaleApp.Comentarios do
  import Ecto.Query
  alias DaleApp.Repo
  alias DaleApp.Comentarios.Comentario
  alias DaleApp.Comentarios.ComentarioLike

  def crear(attrs) do
    %Comentario{}
    |> Comentario.changeset(attrs)
    |> Repo.insert()
  end

  def listar(publicacion_id) do
    Repo.all(
      from c in Comentario,
      where: c.publicacion_id == ^publicacion_id,
      order_by: [desc: c.likes_count, asc: c.inserted_at],
      preload: [:user]
    )
  end

  def toggle_like(user_id, comentario_id) do
    existing = Repo.get_by(ComentarioLike, user_id: user_id, comentario_id: comentario_id)
    if existing do
      Repo.delete(existing)
      Repo.update_all(
        from(c in Comentario, where: c.id == ^comentario_id),
        inc: [likes_count: -1]
      )
      {:ok, :unliked}
    else
      %ComentarioLike{}
      |> ComentarioLike.changeset(%{user_id: user_id, comentario_id: comentario_id})
      |> Repo.insert()
      Repo.update_all(
        from(c in Comentario, where: c.id == ^comentario_id),
        inc: [likes_count: 1]
      )
      {:ok, :liked}
    end
  end

  def mis_likes_comentarios(user_id, publicacion_id) do
    comentario_ids =
      from(c in Comentario, where: c.publicacion_id == ^publicacion_id, select: c.id)
    Repo.all(
      from cl in ComentarioLike,
      where: cl.user_id == ^user_id and cl.comentario_id in subquery(comentario_ids),
      select: cl.comentario_id
    )
    |> MapSet.new()
  end
end
