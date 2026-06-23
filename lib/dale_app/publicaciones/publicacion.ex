defmodule DaleApp.Publicaciones.Publicacion do
  use Ecto.Schema
  import Ecto.Changeset

  schema "publicaciones" do
    field :imagen_url, :string
    field :descripcion, :string
    field :likes_count, :integer, default: 0
    field :comentarios_count, :integer, default: 0
    belongs_to :user, DaleApp.Accounts.User

    timestamps()
  end

  def changeset(publicacion, attrs) do
    publicacion
    |> cast(attrs, [:imagen_url, :descripcion, :user_id])
    |> validate_required([:imagen_url, :user_id])
    |> validate_length(:descripcion, max: 1000)
  end
end
