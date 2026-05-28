defmodule DaleApp.Brands.Brand do
  use Ecto.Schema
  import Ecto.Changeset

  schema "brands" do
    field :name, :string
    field :logo, :string
    field :description, :string
    field :address, :string
    field :latitude, :float
    field :longitude, :float
    field :image_limit, :integer, default: 10
    field :active, :boolean, default: true
    belongs_to :user, DaleApp.Accounts.User

    timestamps()
  end

  def changeset(brand, attrs) do
    brand
    |> cast(attrs, [:name, :logo, :description, :address, :latitude, :longitude, :image_limit, :active, :user_id])
    |> validate_required([:name, :user_id])
  end
end
