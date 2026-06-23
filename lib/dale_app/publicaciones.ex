defmodule DaleApp.Publicaciones do
  import Ecto.Query
  alias DaleApp.Repo
  alias DaleApp.Publicaciones.Publicacion

  def crear(attrs) do
    %Publicacion{}
    |> Publicacion.changeset(attrs)
    |> Repo.insert()
  end

  def listar_de_amigos(user_id, amigo_ids) do
    ids = [user_id | amigo_ids]
    Repo.all(
      from p in Publicacion,
      where: p.user_id in ^ids,
      order_by: [desc: p.inserted_at],
      limit: 50,
      preload: [:user]
    )
  end
end
