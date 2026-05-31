defmodule DaleApp.MapSaves.MapSave do
  use Ecto.Schema
  import Ecto.Changeset

  schema "map_saves" do
    belongs_to :user, DaleApp.Accounts.User
    belongs_to :brand, DaleApp.Brands.Brand
    field :expires_at, :utc_datetime
    timestamps()
  end

  def changeset(map_save, attrs) do
    map_save
    |> cast(attrs, [:user_id, :brand_id, :expires_at])
    |> validate_required([:user_id, :brand_id, :expires_at])
    |> unique_constraint([:user_id, :brand_id])
  end
end
