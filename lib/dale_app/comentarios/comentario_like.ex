defmodule DaleApp.Comentarios.ComentarioLike do
  use Ecto.Schema
  import Ecto.Changeset

  schema "comentario_likes" do
    belongs_to :user, DaleApp.Accounts.User
    belongs_to :comentario, DaleApp.Comentarios.Comentario
    timestamps()
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:user_id, :comentario_id])
    |> validate_required([:user_id, :comentario_id])
    |> unique_constraint([:user_id, :comentario_id])
  end
end
