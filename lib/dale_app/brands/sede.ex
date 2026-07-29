defmodule DaleApp.Brands.Sede do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sedes" do
    field :nombre, :string
    field :direccion, :string
    field :latitude, :float
    field :longitude, :float
    belongs_to :brand, DaleApp.Brands.Brand

    timestamps()
  end

  def changeset(sede, attrs) do
    sede
    |> cast(attrs, [:nombre, :direccion, :latitude, :longitude, :brand_id])
    |> validate_required([:brand_id])
  end
end
