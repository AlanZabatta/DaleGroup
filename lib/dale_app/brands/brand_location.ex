defmodule DaleApp.Brands.BrandLocation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "brand_locations" do
    field :nombre, :string
    field :address, :string
    field :latitude, :float
    field :longitude, :float
    belongs_to :brand, DaleApp.Brands.Brand

    timestamps()
  end

  def changeset(location, attrs) do
    location
    |> cast(attrs, [:nombre, :address, :latitude, :longitude, :brand_id])
    |> validate_required([:brand_id])
  end
end
