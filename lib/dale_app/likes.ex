defmodule DaleApp.Likes do
  import Ecto.Query
  alias DaleApp.Repo
  alias DaleApp.Likes.Like

  def toggle(user_id, publicacion_id) do
    case Repo.get_by(Like, user_id: user_id, publicacion_id: publicacion_id) do
      nil ->
        %Like{}
        |> Like.changeset(%{user_id: user_id, publicacion_id: publicacion_id})
        |> Repo.insert()
        contar(publicacion_id)
        {:ok, :liked}
      like ->
        Repo.delete(like)
        contar(publicacion_id)
        {:ok, :unliked}
    end
  end

  def contar(publicacion_id) do
    Repo.aggregate(from(l in Like, where: l.publicacion_id == ^publicacion_id), :count)
  end

  def liked?(user_id, publicacion_id) do
    Repo.exists?(from l in Like, where: l.user_id == ^user_id and l.publicacion_id == ^publicacion_id)
  end

  def likes_por_publicaciones(publicacion_ids, user_id) do
    conteos = Repo.all(from l in Like, where: l.publicacion_id in ^publicacion_ids, group_by: l.publicacion_id, select: {l.publicacion_id, count(l.id)})
    mis_likes = Repo.all(from l in Like, where: l.publicacion_id in ^publicacion_ids and l.user_id == ^user_id, select: l.publicacion_id)
    {Map.new(conteos), MapSet.new(mis_likes)}
  end
end
