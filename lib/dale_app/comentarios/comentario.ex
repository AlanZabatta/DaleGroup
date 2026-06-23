defmodule DaleApp.Comentarios.Comentario do
  use Ecto.Schema
  import Ecto.Changeset

  schema "comentarios" do
    field :contenido, :string
    field :likes_count, :integer, default: 0
    belongs_to :user, DaleApp.Accounts.User
    belongs_to :publicacion, DaleApp.Publicaciones.Publicacion
    timestamps()
  end

  def changeset(comentario, attrs) do
    comentario
    |> cast(attrs, [:contenido, :user_id, :publicacion_id])
    |> validate_required([:contenido, :user_id, :publicacion_id])
    |> validate_length(:contenido, max: 500)
  end
end
