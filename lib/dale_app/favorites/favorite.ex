defmodule DaleApp.Favorites.Favorite do
  use Ecto.Schema
  import Ecto.Changeset

  schema "favorites" do
    belongs_to :user, DaleApp.Accounts.User
    belongs_to :product, DaleApp.Products.Product
    timestamps()
  end

  def changeset(favorite, attrs) do
    favorite
    |> cast(attrs, [:user_id, :product_id])
    |> validate_required([:user_id, :product_id])
    |> unique_constraint([:user_id, :product_id])
  end
end
