defmodule DaleApp.Likes.Like do
  use Ecto.Schema
  import Ecto.Changeset

  schema "likes" do
    belongs_to :user, DaleApp.Accounts.User
    belongs_to :publicacion, DaleApp.Publicaciones.Publicacion
    timestamps()
  end

  def changeset(like, attrs) do
    like
    |> cast(attrs, [:user_id, :publicacion_id])
    |> validate_required([:user_id, :publicacion_id])
    |> unique_constraint([:user_id, :publicacion_id])
  end
end
